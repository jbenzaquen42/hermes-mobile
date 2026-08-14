import Foundation
import SwiftUI

enum CapabilitySegmentPresentation: String, CaseIterable, Identifiable {
  case skills = "Skills"
  case toolsets = "Toolsets"
  case mcpServers = "MCP"

  var id: Self { self }

  var systemImage: String {
    switch self {
    case .skills: "sparkles"
    case .toolsets: "wrench.and.screwdriver"
    case .mcpServers: "server.rack"
    }
  }
}

enum CapabilityHealthPresentation: Equatable {
  case healthy(String)
  case warning(String)
  case unavailable(String)
  case unknown(String)

  var label: String {
    switch self {
    case let .healthy(label), let .warning(label), let .unavailable(label), let .unknown(label):
      label
    }
  }

  var systemImage: String {
    switch self {
    case .healthy: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .unavailable: "xmark.circle.fill"
    case .unknown: "questionmark.circle"
    }
  }
}

struct CapabilityItemPresentation: Equatable, Identifiable {
  let id: String
  let segment: CapabilitySegmentPresentation
  let name: String
  let summary: String
  let details: String
  let source: String?
  let category: String?
  let documentation: String?
  let toolCount: Int?
  let toolNames: [String]
  let transport: String?
  let health: CapabilityHealthPresentation?
  let warning: String?
  let isEnabled: Bool

  var toolCountLabel: String? {
    guard let toolCount else { return nil }
    return toolCount == 1 ? "1 tool" : "\(toolCount) tools"
  }
}

enum CapabilityCatalogLoadPresentation: Equatable {
  case loading
  case loaded
  case failed(String)
  case unsupported(String)
}

enum CapabilityCatalogSavePresentation: Equatable {
  case idle
  case saving
  case saved(String)
  case partial(saved: [String], failed: [String], notes: [String])
  case failed(String)
  case unsupported(String)
}

struct CapabilityCatalogPresentation: Equatable {
  let profileName: String
  let loadState: CapabilityCatalogLoadPresentation
  let saveState: CapabilityCatalogSavePresentation
  let visibleItems: [CapabilityItemPresentation]
  let totalCount: Int
  let isDirty: Bool
  let canSave: Bool
  let canLoadMore: Bool
  let isLoadingMore: Bool
  let warningBanner: String?
  let errorBanner: String?
}

struct CapabilityCatalogBindings {
  let segment: Binding<CapabilitySegmentPresentation>
  let searchText: Binding<String>
}

struct CapabilityCatalogActions {
  let onClose: () -> Void
  let onReload: () -> Void
  let onSave: () -> Void
  let onLoadMore: () -> Void
  let onSelect: (CapabilityItemPresentation) -> Void
  let onSetEnabled: (CapabilityItemPresentation, Bool) -> Void
}

/// Searchable, profile-scoped Skills/Toolsets/MCP catalog. Filtering and dirty/save state are
/// inputs from the reducer; this view only renders the selected segment and dispatches edits.
struct CapabilityManagementContent: View {
  let presentation: CapabilityCatalogPresentation
  let bindings: CapabilityCatalogBindings
  let actions: CapabilityCatalogActions

  var body: some View {
    Group {
      switch presentation.loadState {
      case .loading where presentation.totalCount == 0:
        ProgressView("Loading capabilities…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case let .unsupported(message):
        unavailable(
          title: "Capability management isn't available",
          systemImage: "nosign",
          message: message,
          retryTitle: nil
        )
      default:
        catalog
      }
    }
    .navigationTitle("Capabilities")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(action: actions.onClose) {
          Label("Back to profile", systemImage: "chevron.backward")
            .labelStyle(.iconOnly)
        }
        .accessibilityHint(
          presentation.isDirty
            ? "Shows a confirmation before discarding unsaved changes"
            : "Returns to the profile editor"
        )
      }

      if allowsManagement {
        ToolbarItemGroup(placement: .confirmationAction) {
          Button(action: actions.onReload) {
            Label("Reload", systemImage: "arrow.clockwise")
          }
          .disabled(presentation.saveState == .saving)

          Button(action: actions.onSave) {
            if presentation.saveState == .saving {
              ProgressView()
                .accessibilityLabel("Saving capabilities")
            } else {
              Text("Save")
            }
          }
          .disabled(!presentation.canSave || presentation.saveState == .saving)
          .accessibilityHint("Saves capability changes for \(presentation.profileName)")
        }
      }
    }
  }

  private var catalog: some View {
    List {
      Section {
        Picker("Capability type", selection: bindings.segment) {
          ForEach(CapabilitySegmentPresentation.allCases) { segment in
            Text(segment.rawValue).tag(segment)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Filters the capability catalog by type")
      }

      if let warning = presentation.warningBanner {
        CapabilityNoticeView(
          title: "Review before saving",
          message: warning,
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange
        )
      }

      if let error = presentation.errorBanner {
        CapabilityNoticeView(
          title: "Capability error",
          message: error,
          systemImage: "xmark.circle.fill",
          tint: .red
        )
      }

      if case let .failed(message) = presentation.loadState,
         presentation.errorBanner != message {
        CapabilityNoticeView(
          title: "Catalog may be out of date",
          message: message,
          systemImage: "arrow.triangle.2.circlepath",
          tint: .orange,
          actionTitle: "Reload",
          action: actions.onReload
        )
      }

      saveStatus

      if case .loading = presentation.loadState {
        Label("Refreshing catalog…", systemImage: "arrow.clockwise")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if presentation.visibleItems.isEmpty {
        if bindings.searchText.wrappedValue.isEmpty {
          ContentUnavailableView(
            "No \(bindings.segment.wrappedValue.rawValue)",
            systemImage: bindings.segment.wrappedValue.systemImage,
            description: Text("No entries were returned for this profile.")
          )
          .listRowBackground(Color.clear)
        } else {
          ContentUnavailableView.search(text: bindings.searchText.wrappedValue)
            .listRowBackground(Color.clear)
        }
      } else {
        Section {
          ForEach(presentation.visibleItems) { item in
            CapabilityCatalogRow(
              item: item,
              onSelect: { actions.onSelect(item) },
              onSetEnabled: { actions.onSetEnabled(item, $0) }
            )
          }
        } header: {
          Text("\(bindings.segment.wrappedValue.rawValue) · \(presentation.visibleItems.count)")
        } footer: {
          if presentation.isDirty {
            Label("Unsaved changes", systemImage: "circle.fill")
              .foregroundStyle(.orange)
              .accessibilityHint("Use Save to apply changes to this profile")
          } else {
            Text("Changes apply only to \(presentation.profileName).")
          }
        }

        if presentation.canLoadMore || presentation.isLoadingMore {
          Button(action: actions.onLoadMore) {
            HStack {
              Spacer()
              if presentation.isLoadingMore {
                ProgressView()
                  .accessibilityLabel("Loading more skills")
              } else {
                Label("Load more skills", systemImage: "arrow.down.circle")
              }
              Spacer()
            }
          }
          .disabled(presentation.isLoadingMore)
        }
      }
    }
    .refreshable { actions.onReload() }
    .searchable(
      text: bindings.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search \(bindings.segment.wrappedValue.rawValue.lowercased())"
    )
  }

  private var allowsManagement: Bool {
    if case .unsupported = presentation.loadState { return false }
    return true
  }

  @ViewBuilder
  private var saveStatus: some View {
    switch presentation.saveState {
    case .idle, .saving:
      EmptyView()
    case let .saved(message):
      CapabilityNoticeView(
        title: "Capabilities saved",
        message: message,
        systemImage: "checkmark.circle.fill",
        tint: .green
      )
    case let .partial(saved, failed, notes):
      CapabilityNoticeView(
        title: "Some changes weren't saved",
        message: partialSaveMessage(saved: saved, failed: failed, notes: notes),
        systemImage: "exclamationmark.triangle.fill",
        tint: .orange,
        actionTitle: "Retry save",
        action: actions.onSave
      )
    case let .failed(message):
      CapabilityNoticeView(
        title: "Couldn't save capabilities",
        message: message,
        systemImage: "xmark.circle.fill",
        tint: .red,
        actionTitle: "Try again",
        action: actions.onSave
      )
    case let .unsupported(message):
      CapabilityNoticeView(
        title: "Saving isn't supported",
        message: message,
        systemImage: "nosign",
        tint: .secondary
      )
    }
  }

  private func partialSaveMessage(
    saved: [String],
    failed: [String],
    notes: [String]
  ) -> String {
    let savedText = saved.isEmpty
      ? "No groups were confirmed saved."
      : "Saved: \(saved.joined(separator: ", "))."
    let failedText = failed.isEmpty
      ? "Reload to verify the remaining changes."
      : "Not saved: \(failed.joined(separator: ", "))."
    let notesText = notes.isEmpty ? "" : " Verification: \(notes.joined(separator: " "))"
    return "\(savedText) \(failedText) Your unconfirmed choices are still here.\(notesText)"
  }

  private func unavailable(
    title: String,
    systemImage: String,
    message: String,
    retryTitle: String?
  ) -> some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(message)
    } actions: {
      if let retryTitle {
        Button(retryTitle, action: actions.onReload)
          .buttonStyle(.borderedProminent)
      }
    }
  }
}

private struct CapabilityCatalogRow: View {
  let item: CapabilityItemPresentation
  let onSelect: () -> Void
  let onSetEnabled: (Bool) -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Button(action: onSelect) {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 5) {
            Text(item.name)
              .font(.body.weight(.semibold))

            if !item.summary.isEmpty {
              Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }

            ViewThatFits(in: .horizontal) {
              HStack(spacing: 10) { badges }
              VStack(alignment: .leading, spacing: 4) { badges }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.forward")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens capability details")

      Toggle(
        "Enable \(item.name)",
        isOn: Binding(get: { item.isEnabled }, set: onSetEnabled)
      )
      .labelsHidden()
      .accessibilityHint("Changes take effect after saving")
    }
  }

  @ViewBuilder
  private var badges: some View {
    if let category = item.category, !category.isEmpty {
      Label(category, systemImage: "tag")
    }
    if let toolCountLabel = item.toolCountLabel {
      Label(toolCountLabel, systemImage: "hammer")
    }
    if let health = item.health {
      Label(health.label, systemImage: health.systemImage)
        .foregroundStyle(healthColor(health))
    }
  }

  private func healthColor(_ health: CapabilityHealthPresentation) -> Color {
    switch health {
    case .healthy: .green
    case .warning: .orange
    case .unavailable: .red
    case .unknown: .secondary
    }
  }
}

struct CapabilityDetailView: View {
  let item: CapabilityItemPresentation
  let onSetEnabled: (Bool) -> Void

  var body: some View {
    List {
      Section {
        Toggle(
          "Enabled for this profile",
          isOn: Binding(get: { item.isEnabled }, set: onSetEnabled)
        )
        .accessibilityHint("Changes take effect after saving")
      }

      if !item.details.isEmpty {
        Section("About") {
          Text(item.details)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if let warning = item.warning {
        CapabilityNoticeView(
          title: "Capability warning",
          message: warning,
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange
        )
      }

      metadataSection
      documentationSection
      healthSection
      toolsSection
    }
    .navigationTitle(item.name)
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private var metadataSection: some View {
    if item.source != nil || item.category != nil || item.transport != nil
        || item.toolCountLabel != nil {
      Section("Details") {
        if let category = item.category, !category.isEmpty {
          LabeledContent("Category", value: category)
        }
        if let source = item.source, !source.isEmpty {
          LabeledContent("Source", value: source)
        }
        if let transport = item.transport, !transport.isEmpty {
          LabeledContent("Transport", value: transport)
        }
        if let toolCountLabel = item.toolCountLabel {
          LabeledContent("Tools", value: toolCountLabel)
        }
      }
    }
  }

  @ViewBuilder
  private var documentationSection: some View {
    if let documentation = item.documentation,
       !documentation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Section("Documentation") {
        MarkdownText(
          text: documentation,
          copiedToken: nil,
          tokenPrefix: "capability-documentation",
          onCopyCode: nil
        )
      }
    }
  }

  @ViewBuilder
  private var healthSection: some View {
    if let health = item.health {
      Section("Health") {
        Label(health.label, systemImage: health.systemImage)
          .foregroundStyle(healthColor(health))
      }
    }
  }

  @ViewBuilder
  private var toolsSection: some View {
    if !item.toolNames.isEmpty {
      Section("Available tools") {
        ForEach(Array(item.toolNames.enumerated()), id: \.offset) { _, tool in
          Label(tool, systemImage: "hammer")
            .accessibilityLabel("Tool: \(tool)")
        }
      }
    }
  }

  private func healthColor(_ health: CapabilityHealthPresentation) -> Color {
    switch health {
    case .healthy: .green
    case .warning: .orange
    case .unavailable: .red
    case .unknown: .secondary
    }
  }
}

private struct CapabilityNoticeView: View {
  let title: String
  let message: String
  let systemImage: String
  let tint: Color
  var actionTitle: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        Label(title, systemImage: systemImage)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(tint)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let actionTitle, let action {
          Button(actionTitle, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
      }
      .accessibilityElement(children: .contain)
    }
  }
}
