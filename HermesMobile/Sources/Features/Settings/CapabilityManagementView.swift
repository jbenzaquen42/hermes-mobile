import ComposableArchitecture
import Foundation
import HermesKit
import SwiftUI

/// Thin Store adapter for the independently snapshot-tested capability catalog and detail
/// views. Catalog filtering, selection baselines, warnings, saving, and reload reconciliation
/// remain entirely in `CapabilityManagementFeature`.
struct CapabilityManagementView: View {
  @Bindable var store: StoreOf<CapabilityManagementFeature>

  var body: some View {
    CapabilityManagementContent(
      presentation: presentation,
      bindings: CapabilityCatalogBindings(
        segment: segmentBinding,
        searchText: searchBinding
      ),
      actions: CapabilityCatalogActions(
        onClose: { store.send(.closeTapped) },
        onReload: { store.send(.reloadTapped) },
        onSave: { store.send(.saveTapped) },
        onLoadMore: { store.send(.loadMoreSkills) },
        onSelect: { item in
          store.send(.detailTapped(detailID(for: item)))
        },
        onSetEnabled: setEnabled
      )
    )
    .navigationDestination(isPresented: detailIsPresented) {
      if let item = selectedDetailPresentation {
        CapabilityDetailView(
          item: item,
          onSetEnabled: { setEnabled(item, $0) }
        )
      } else {
        ProgressView("Loading details…")
      }
    }
    .confirmationDialog(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
    .task { store.send(.task) }
  }

  private var presentation: CapabilityCatalogPresentation {
    CapabilityCatalogPresentation(
      profileName: store.profileName,
      loadState: loadPresentation,
      saveState: savePresentation,
      visibleItems: visibleItems,
      totalCount: store.totalCount,
      isDirty: store.isDirty,
      canSave: store.canSave,
      canLoadMore: isBrowsingSkills && store.hasMoreBrowsedSkills,
      isLoadingMore: isBrowsingSkills && store.skillBrowseState == .loading,
      warningBanner: store.activeWorkflowWarning,
      errorBanner: standaloneErrorBanner
    )
  }

  private var isBrowsingSkills: Bool {
    store.selectedSegment == .skills
      && store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var loadPresentation: CapabilityCatalogLoadPresentation {
    if case let .unsupported(message) = store.profileLoadState {
      return .unsupported(message)
    }

    // A single catalog method can be unsupported while the other segments remain useful.
    // Render it as a section failure so the segmented control stays reachable.
    if case let .unsupported(message) = selectedSectionLoadState {
      return .failed(message)
    }

    switch store.loadState {
    case .idle, .loading:
      return .loading
    case .loaded:
      return .loaded
    case let .failed(message):
      return .failed(message)
    case let .unsupported(message):
      return .unsupported(message)
    }
  }

  private var selectedSectionLoadState: CapabilityManagementFeature.LoadState {
    switch store.selectedSegment {
    case .skills: store.skillsLoadState
    case .toolsets: store.toolsetsLoadState
    case .mcpServers: store.mcpLoadState
    }
  }

  private var savePresentation: CapabilityCatalogSavePresentation {
    switch store.saveState {
    case .idle:
      .idle
    case .saving:
      .saving
    case let .saved(report):
      .saved(savedMessage(report))
    case let .partial(report):
      .partial(
        saved: report.appliedNames,
        failed: report.failedNames,
        notes: report.reloadErrors
      )
    case let .failed(message):
      .failed(message)
    case let .unsupported(message):
      .unsupported(message)
    }
  }

  private var visibleItems: [CapabilityItemPresentation] {
    switch store.selectedSegment {
    case .skills:
      store.filteredSkills.map { skillPresentation($0) }
    case .toolsets:
      store.filteredToolsets.map(toolsetPresentation)
    case .mcpServers:
      store.filteredMCPServers.map(mcpPresentation)
    }
  }

  private var standaloneErrorBanner: String? {
    switch store.saveState {
    case .failed, .unsupported:
      return nil
    case let .saved(report) where !report.reloadErrors.isEmpty:
      return nil
    case let .partial(report) where !report.reloadErrors.isEmpty:
      return nil
    default:
      break
    }
    if case let .failed(message) = store.loadState, message == store.errorBanner {
      return nil
    }
    return store.errorBanner
  }

  private var segmentBinding: Binding<CapabilitySegmentPresentation> {
    Binding(
      get: { segmentPresentation(store.selectedSegment) },
      set: { store.send(.segmentSelected(featureSegment($0))) }
    )
  }

  private var searchBinding: Binding<String> {
    Binding(
      get: { store.searchQuery },
      set: { store.send(.searchQueryChanged($0)) }
    )
  }

  private var detailIsPresented: Binding<Bool> {
    Binding(
      get: { store.selectedDetail != nil },
      set: { isPresented in
        if !isPresented { store.send(.detailDismissed) }
      }
    )
  }

  private var selectedDetailPresentation: CapabilityItemPresentation? {
    guard let detail = store.selectedDetail else { return nil }
    switch detail {
    case let .skill(row):
      return skillPresentation(row, warning: store.errorBanner)
    case let .toolset(row):
      return toolsetPresentation(row)
    case let .mcpServer(row):
      return mcpPresentation(row)
    }
  }

  private func skillPresentation(
    _ row: CapabilityManagementFeature.SkillRow,
    warning: String? = nil
  ) -> CapabilityItemPresentation {
    CapabilityItemPresentation(
      id: row.name,
      segment: .skills,
      name: row.title,
      summary: row.summary,
      details: row.summary,
      source: row.source,
      category: row.category,
      documentation: row.documentation,
      toolCount: nil,
      toolNames: [],
      transport: nil,
      health: nil,
      warning: warning,
      isEnabled: row.enabled
    )
  }

  private func toolsetPresentation(
    _ row: CapabilityManagementFeature.ToolsetRow
  ) -> CapabilityItemPresentation {
    CapabilityItemPresentation(
      id: row.name,
      segment: .toolsets,
      name: row.title,
      summary: row.summary,
      details: row.summary,
      source: nil,
      category: nil,
      documentation: nil,
      toolCount: row.toolCount,
      toolNames: [],
      transport: nil,
      health: nil,
      warning: nil,
      isEnabled: row.enabled
    )
  }

  private func mcpPresentation(
    _ row: CapabilityManagementFeature.MCPServerRow
  ) -> CapabilityItemPresentation {
    CapabilityItemPresentation(
      id: row.name,
      segment: .mcpServers,
      name: row.title,
      summary: row.summary,
      details: row.summary,
      source: nil,
      category: nil,
      documentation: nil,
      toolCount: row.toolCount,
      toolNames: row.tools,
      transport: row.transport.isEmpty ? nil : row.transport,
      health: row.health.map { healthPresentation($0) },
      warning: nil,
      isEnabled: row.enabled
    )
  }

  private func setEnabled(_ item: CapabilityItemPresentation, _ enabled: Bool) {
    switch item.segment {
    case .skills:
      store.send(.setSkillEnabled(name: item.id, enabled: enabled))
    case .toolsets:
      store.send(.setToolsetEnabled(name: item.id, enabled: enabled))
    case .mcpServers:
      store.send(.setMCPServerEnabled(name: item.id, enabled: enabled))
    }
  }

  private func detailID(
    for item: CapabilityItemPresentation
  ) -> CapabilityManagementFeature.DetailID {
    CapabilityManagementFeature.DetailID(
      segment: featureSegment(item.segment),
      name: item.id
    )
  }

  private func featureSegment(
    _ segment: CapabilitySegmentPresentation
  ) -> CapabilityManagementFeature.Segment {
    switch segment {
    case .skills: .skills
    case .toolsets: .toolsets
    case .mcpServers: .mcpServers
    }
  }

  private func segmentPresentation(
    _ segment: CapabilityManagementFeature.Segment
  ) -> CapabilitySegmentPresentation {
    switch segment {
    case .skills: .skills
    case .toolsets: .toolsets
    case .mcpServers: .mcpServers
    }
  }

  private func healthPresentation(
    _ health: CapabilityManagementFeature.MCPHealth
  ) -> CapabilityHealthPresentation {
    switch health {
    case let .healthy(label): .healthy(label)
    case let .warning(label): .warning(label)
    case let .unavailable(label): .unavailable(label)
    case let .unknown(label): .unknown(label)
    }
  }

  private func savedMessage(_ report: CapabilityManagementFeature.SaveReport) -> String {
    let names = report.appliedNames
    let base = names.isEmpty
      ? "Hermes accepted the capability settings."
      : "Saved \(names.joined(separator: ", "))."
    guard !report.reloadErrors.isEmpty else { return base }
    return "\(base) Verification: \(report.reloadErrors.joined(separator: " "))"
  }
}
