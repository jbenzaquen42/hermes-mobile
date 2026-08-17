import ComposableArchitecture
import Foundation
import HermesKit
import SwiftUI

/// Thin adapter between `MemoryFeature` and the independently snapshot-tested memory views.
/// Filtering, drafts, authoritative reloads, profile-scope enforcement, and confirmations
/// remain reducer-owned.
struct MemoryManagementView: View {
  @Bindable var store: StoreOf<MemoryFeature>

  var body: some View {
    MemoryManagementContent(
      presentation: listPresentation,
      bindings: MemoryListBindings(
        store: storeFilterBinding,
        searchText: searchBinding
      ),
      actions: MemoryListActions(
        onClose: { store.send(.closeTapped) },
        onReload: { store.send(.reloadTapped) },
        onSelect: { store.send(.entryTapped($0.id)) }
      )
    )
    .navigationDestination(isPresented: detailIsPresented) {
      if let presentation = detailPresentation {
        MemoryDetailContent(
          presentation: presentation,
          bindings: MemoryEditBindings(content: editContentBinding),
          actions: MemoryDetailActions(
            onClose: { store.send(.detailDismissed) },
            onReload: { store.send(.reloadTapped) },
            onSave: { store.send(.saveEditTapped) },
            onDeleteOrArchive: { store.send(.deleteOrArchiveTapped) }
          )
        )
      } else {
        ProgressView("Loading entry…")
      }
    }
    .confirmationDialog(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
    .task { store.send(.task) }
  }

  private var listPresentation: MemoryListPresentation {
    MemoryListPresentation(
      profileName: store.profileName,
      scopeLabel: store.isServerDefaultProfile
        ? "Server default profile · \(store.profileName)"
        : "Custom profile · \(store.profileName)",
      loadState: loadPresentation(store.loadState),
      entries: store.filteredEntries.map { entryPresentation($0) },
      totalCount: store.reportedCount,
      capacities: capacityPresentations,
      capacityMessage: capacityMessage,
      mutationState: mutationPresentation,
      errorBanner: standaloneErrorBanner,
      sessionSnapshotExplanation: store.sessionSnapshotExplanation
    )
  }

  private var detailPresentation: MemoryDetailPresentation? {
    guard let selectedID = store.selectedEntryID,
          let summary = store.entries.first(where: { $0.id == selectedID }) else {
      return nil
    }
    let detail = store.selectedDetail.flatMap { $0.id == selectedID ? $0 : nil }
    return MemoryDetailPresentation(
      entry: entryPresentation(summary, detail: detail),
      loadState: loadPresentation(store.detailLoadState),
      mutationState: mutationPresentation,
      isDirty: store.isEditDirty,
      canSave: store.canSaveEdit,
      canDeleteOrArchive: store.canDeleteOrArchive,
      errorBanner: detailErrorBanner,
      sessionSnapshotExplanation: store.sessionSnapshotExplanation
    )
  }

  private var storeFilterBinding: Binding<MemoryStorePresentation> {
    Binding(
      get: { storePresentation(store.selectedStore) },
      set: { store.send(.storeFilterChanged(featureStore($0))) }
    )
  }

  private var searchBinding: Binding<String> {
    Binding(
      get: { store.searchQuery },
      set: { store.send(.searchQueryChanged($0)) }
    )
  }

  private var editContentBinding: Binding<String> {
    Binding(
      get: { store.editDraft?.content ?? "" },
      set: { store.send(.editContentChanged($0)) }
    )
  }

  private var detailIsPresented: Binding<Bool> {
    Binding(
      get: { store.selectedEntryID != nil },
      set: { isPresented in
        if !isPresented { store.send(.detailDismissed) }
      }
    )
  }

  private var capacityPresentations: [MemoryCapacityPresentation] {
    guard let capacity = store.capacity else { return [] }
    return [
      MemoryCapacityPresentation(
        title: "USER",
        used: capacity.userProfile.usedCharacters,
        limit: capacity.userProfile.limitCharacters,
        entryCount: store.entries.filter { $0.kind == .userProfile }.count,
        unitLabel: "characters"
      ),
      MemoryCapacityPresentation(
        title: "MEMORY",
        used: capacity.agentMemory.usedCharacters,
        limit: capacity.agentMemory.limitCharacters,
        entryCount: store.entries.filter { $0.kind == .agentMemory }.count,
        unitLabel: "characters"
      ),
    ]
  }

  private var capacityMessage: String? {
    guard store.capacity == nil else { return nil }
    switch store.capacityReporting {
    case .notReportedByServer:
      "This server does not report live character usage or configured limits."
    @unknown default:
      "Capacity details are not available for this server response."
    }
  }

  private var mutationPresentation: MemoryMutationPresentation {
    switch store.mutationState {
    case .idle:
      .idle
    case .saving:
      .saving
    case .deleting:
      .deleting
    case let .succeeded(report):
      successPresentation(report)
    case let .partial(report):
      .partial(reportMessage(report, includeReloadErrors: true))
    case let .failed(message):
      .failed(message)
    case let .unsupported(message):
      .unsupported(message)
    }
  }

  private var standaloneErrorBanner: String? {
    if case let .failed(message) = store.loadState, message == store.errorBanner {
      return nil
    }
    switch store.mutationState {
    case .failed, .unsupported, .partial:
      return nil
    default:
      return store.errorBanner
    }
  }

  private var detailErrorBanner: String? {
    switch store.mutationState {
    case .failed, .unsupported, .partial:
      nil
    default:
      store.errorBanner
    }
  }

  private func entryPresentation(
    _ entry: LearningEntrySummary,
    detail: LearningEntryDetail? = nil
  ) -> MemoryEntryPresentation {
    let store = storePresentation(entry.kind)
    return MemoryEntryPresentation(
      id: entry.id,
      store: store,
      title: detail?.label ?? entry.label,
      summary: "",
      content: detail?.content ?? "",
      category: store.rawValue,
      tags: [],
      source: "Server default profile",
      createdLabel: nil,
      updatedLabel: nil,
      isArchived: false,
      operationLabel: entry.kind == .learnedSkill ? "Archive learned skill" : "Delete entry",
      operationIsDestructive: entry.kind != .learnedSkill
    )
  }

  private func successPresentation(
    _ report: MemoryFeature.MutationReport
  ) -> MemoryMutationPresentation {
    let message = reportMessage(report, includeReloadErrors: false)
    switch report.action {
    case .updated: return MemoryMutationPresentation.saved(message)
    case .deleted: return MemoryMutationPresentation.deleted(message)
    case .archived: return MemoryMutationPresentation.archived(message)
    }
  }

  private func reportMessage(
    _ report: MemoryFeature.MutationReport,
    includeReloadErrors: Bool
  ) -> String {
    let nativeMessage = report.message.trimmingCharacters(in: .whitespacesAndNewlines)
    let base: String
    if !nativeMessage.isEmpty {
      base = nativeMessage
    } else {
      switch report.action {
      case .updated: base = "Hermes saved the structured entry."
      case .deleted: base = "Hermes deleted the structured entry."
      case .archived: base = "Hermes archived the learned skill."
      }
    }
    guard includeReloadErrors, !report.reloadErrors.isEmpty else { return base }
    return "\(base) Verification: \(report.reloadErrors.joined(separator: " "))"
  }

  private func loadPresentation(
    _ state: MemoryFeature.LoadState
  ) -> MemoryLoadPresentation {
    switch state {
    case .idle, .loading: .loading
    case .loaded: .loaded
    case let .failed(message): .failed(message)
    case let .unsupported(message): .unsupported(message)
    }
  }

  private func featureStore(
    _ store: MemoryStorePresentation
  ) -> MemoryFeature.StoreFilter {
    switch store {
    case .all: .all
    case .userProfile: .userProfile
    case .agentMemory: .agentMemory
    case .learnedSkill: .learnedSkill
    }
  }

  private func storePresentation(
    _ store: MemoryFeature.StoreFilter
  ) -> MemoryStorePresentation {
    switch store {
    case .all: .all
    case .userProfile: .userProfile
    case .agentMemory: .agentMemory
    case .learnedSkill: .learnedSkill
    }
  }

  private func storePresentation(
    _ kind: LearningEntryKind
  ) -> MemoryStorePresentation {
    switch kind {
    case .userProfile: .userProfile
    case .agentMemory: .agentMemory
    case .learnedSkill: .learnedSkill
    }
  }
}
