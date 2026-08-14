import ComposableArchitecture
import HermesKit
import SwiftUI

/// Thin `ProfileEditorFeature` adapter for the reducer-agnostic profile editor form.
/// Server behavior, draft recovery, dirty-state protection, and mutation confirmation all
/// remain in HermesKit; this view only maps typed state into presentation values.
struct ProfileEditorView: View {
  @Bindable var store: StoreOf<ProfileEditorFeature>

  var body: some View {
    ProfileEditorContent(
      presentation: presentation,
      bindings: ProfileEditorBindings(
        name: $store.renameDraft,
        description: $store.description,
        model: $store.model,
        provider: $store.provider,
        reasoningEffort: $store.reasoningEffort,
        soul: $store.soul,
        soulMode: soulModeBinding($store.soulMode)
      ),
      actions: ProfileEditorActions(
        onClose: { store.send(.closeTapped) },
        onReload: { store.send(.reloadTapped) },
        onSave: { store.send(.saveTapped) },
        onRestoreDraft: { store.send(.restoreDraftTapped) },
        onDiscardRecoveredDraft: { store.send(.discardRecoveredDraftTapped) },
        onSetCapabilityEnabled: setCapabilityEnabled,
        onRename: { store.send(.renameTapped) },
        onDelete: { store.send(.deleteTapped) }
      )
    )
    .confirmationDialog(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
    .task { store.send(.task) }
  }

  private var presentation: ProfileEditorPresentation {
    ProfileEditorPresentation(
      profileName: store.profileName,
      isDefault: store.isDefault,
      loadState: loadPresentation,
      isDirty: store.isDirty,
      canSave: store.canSave,
      canRename: store.canRename,
      isRenaming: store.isRenaming,
      isDeleting: store.isDeleting,
      nameError: store.nameError,
      characterCount: store.characterCount,
      estimatedTokenCount: store.estimatedTokenCount,
      errorBanner: standaloneErrorBanner,
      saveState: savePresentation,
      recoveredDraft: recoveredDraftPresentation,
      capabilities: capabilityPresentations,
      reasoningOptions: store.reasoningOptions
    )
  }

  private var loadPresentation: ProfileEditorLoadPresentation {
    switch store.loadState {
    case .idle, .loading:
      .loading
    case .loaded:
      .loaded
    case let .failed(message):
      .failed(message)
    case .unsupported:
      .unsupported(ProfileAdminError.unsupported.message)
    }
  }

  private var savePresentation: ProfileEditorSavePresentation {
    switch store.saveState {
    case .idle:
      .idle
    case .saving:
      .saving
    case let .saved(report):
      .saved(savedMessage(report))
    case let .partial(report):
      .partial(saved: report.appliedNames, failed: report.failedNames)
    case let .failed(message):
      .failed(message)
    case .unsupported:
      .failed(ProfileAdminError.unsupported.message)
    }
  }

  /// A transport/save failure is already represented by `savePresentation`; suppress the
  /// reducer's matching banner so the form never announces the same error twice.
  private var standaloneErrorBanner: String? {
    switch store.saveState {
    case .failed, .unsupported:
      nil
    default:
      store.errorBanner
    }
  }

  private var recoveredDraftPresentation: ProfileRecoveredDraftPresentation? {
    guard let draft = store.recoveredDraft else { return nil }
    let savedAt = draft.savedAt.formatted(date: .abbreviated, time: .shortened)
    if store.recoveredDraftConflictsWithServer {
      return ProfileRecoveredDraftPresentation(
        message: "A draft saved \(savedAt) was based on an older server version. Review it before saving."
      )
    }
    return ProfileRecoveredDraftPresentation(
      message: "A locally recovered draft from \(savedAt) is available."
    )
  }

  private var capabilityPresentations: [ProfileCapabilitySummaryPresentation] {
    [
      ProfileCapabilitySummaryPresentation(
        kind: .skill,
        title: "Skills",
        systemImage: "sparkles",
        options: store.skills.map {
          ProfileCapabilityOptionPresentation(
            name: $0.name,
            detail: nil,
            isEnabled: $0.enabled
          )
        }
      ),
      ProfileCapabilitySummaryPresentation(
        kind: .toolset,
        title: "Toolsets",
        systemImage: "wrench.and.screwdriver",
        options: store.toolsets.map {
          ProfileCapabilityOptionPresentation(
            name: $0.name,
            detail: toolsetDetail($0),
            isEnabled: $0.enabled
          )
        }
      ),
      ProfileCapabilitySummaryPresentation(
        kind: .mcpServer,
        title: "MCP servers",
        systemImage: "server.rack",
        options: store.mcpServers.map {
          ProfileCapabilityOptionPresentation(
            name: $0.name,
            detail: $0.transport.isEmpty ? nil : $0.transport,
            isEnabled: $0.enabled
          )
        }
      ),
    ]
  }

  private func soulModeBinding(
    _ source: Binding<ProfileEditorFeature.State.SoulMode>
  ) -> Binding<ProfileSoulModePresentation> {
    Binding(
      get: { source.wrappedValue == .edit ? .edit : .preview },
      set: { source.wrappedValue = $0 == .edit ? .edit : .preview }
    )
  }

  private func setCapabilityEnabled(
    _ kind: ProfileCapabilityKind,
    _ name: String,
    _ enabled: Bool
  ) {
    switch kind {
    case .skill:
      store.send(.setSkillEnabled(name: name, enabled: enabled))
    case .toolset:
      store.send(.setToolsetEnabled(name: name, enabled: enabled))
    case .mcpServer:
      store.send(.setMCPServerEnabled(name: name, enabled: enabled))
    }
  }

  private func savedMessage(_ report: ProfileEditorFeature.SaveReport) -> String {
    let sections = report.appliedNames
    return sections.isEmpty
      ? "Hermes accepted the profile settings."
      : "Saved \(sections.joined(separator: ", "))."
  }

  private func toolsetDetail(_ toolset: ProfileToolset) -> String? {
    let label = toolset.label.trimmingCharacters(in: .whitespacesAndNewlines)
    let description = toolset.toolsetDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    let toolCount = toolset.toolCount == 1 ? "1 tool" : "\(toolset.toolCount) tools"
    return [label, description, toolCount]
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
  }
}
