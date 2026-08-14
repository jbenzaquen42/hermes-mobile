import SwiftUI

enum MemoryStorePresentation: String, CaseIterable, Identifiable {
  case all = "All"
  case userProfile = "USER"
  case agentMemory = "MEMORY"
  case learnedSkill = "SKILLS"

  var id: Self { self }

  var systemImage: String {
    switch self {
    case .all: "tray.full"
    case .userProfile: "person.text.rectangle"
    case .agentMemory: "brain.head.profile"
    case .learnedSkill: "graduationcap"
    }
  }
}

struct MemoryCapacityPresentation: Equatable {
  let title: String
  let used: Int
  let limit: Int?
  let entryCount: Int
  let unitLabel: String

  var fraction: Double? {
    guard let limit, limit > 0 else { return nil }
    return min(1, max(0, Double(used) / Double(limit)))
  }

  var usageLabel: String {
    guard let limit else { return "\(used.formatted()) \(unitLabel) used" }
    return "\(used.formatted()) of \(limit.formatted()) \(unitLabel) used"
  }

  var isNearLimit: Bool {
    guard let fraction else { return false }
    return fraction >= 0.85
  }
}

struct MemoryEntryPresentation: Equatable, Identifiable {
  let id: String
  let store: MemoryStorePresentation
  let title: String
  let summary: String
  let content: String
  let category: String?
  let tags: [String]
  let source: String?
  let createdLabel: String?
  let updatedLabel: String?
  let isArchived: Bool
  let operationLabel: String
  let operationIsDestructive: Bool
}

enum MemoryLoadPresentation: Equatable {
  case loading
  case loaded
  case failed(String)
  case unsupported(String)
}

enum MemoryMutationPresentation: Equatable {
  case idle
  case saving
  case saved(String)
  case deleting
  case deleted(String)
  case archived(String)
  case partial(String)
  case failed(String)
  case unsupported(String)
}

struct MemoryListPresentation: Equatable {
  let profileName: String
  let scopeLabel: String
  let loadState: MemoryLoadPresentation
  let entries: [MemoryEntryPresentation]
  let totalCount: Int
  let capacities: [MemoryCapacityPresentation]
  let capacityMessage: String?
  let mutationState: MemoryMutationPresentation
  let errorBanner: String?
  let sessionSnapshotExplanation: String
}

struct MemoryListBindings {
  let store: Binding<MemoryStorePresentation>
  let searchText: Binding<String>
}

struct MemoryListActions {
  let onClose: () -> Void
  let onReload: () -> Void
  let onSelect: (MemoryEntryPresentation) -> Void
}

/// Server-default-profile structured USER, MEMORY, and learned-skill entries. The reducer
/// supplies filtered entries; this view never reads or replaces whole USER.md/MEMORY.md files.
struct MemoryManagementContent: View {
  let presentation: MemoryListPresentation
  let bindings: MemoryListBindings
  let actions: MemoryListActions

  var body: some View {
    Group {
      switch presentation.loadState {
      case .loading where presentation.totalCount == 0:
        ProgressView("Loading memory…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case let .unsupported(message):
        ContentUnavailableView {
          Label("Structured memory isn't available", systemImage: "brain.head.profile")
        } description: {
          Text(message)
        }
      default:
        memoryList
      }
    }
    .navigationTitle("Memory & USER")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(action: actions.onClose) {
          Label("Back to profiles", systemImage: "chevron.backward")
            .labelStyle(.iconOnly)
        }
        .accessibilityHint("Returns to the profile list")
      }
      if allowsReload {
        ToolbarItem(placement: .primaryAction) {
          Button(action: actions.onReload) {
            Label("Reload memory", systemImage: "arrow.clockwise")
          }
        }
      }
    }
  }

  private var memoryList: some View {
    List {
      Section {
        Picker("Memory store", selection: bindings.store) {
          ForEach(MemoryStorePresentation.allCases) { store in
            Text(store.rawValue).tag(store)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Filters USER profile, agent MEMORY, and learned skill entries")
      }

      Section {
        Label(presentation.scopeLabel, systemImage: "server.rack")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        LabeledContent("Server entries", value: presentation.totalCount.formatted())
      } header: {
        Text("Scope")
      } footer: {
        Text("Hermes exposes structured memory for the server's default profile only.")
      }

      ForEach(presentation.capacities, id: \.title) { capacity in
        MemoryCapacityView(capacity: capacity)
      }

      if let capacityMessage = presentation.capacityMessage {
        Section {
          Label(capacityMessage, systemImage: "gauge.with.dots.needle.67percent")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
          Text("Capacity")
        }
      }

      Section {
        Label {
          Text(presentation.sessionSnapshotExplanation)
        } icon: {
          Image(systemName: "camera.aperture")
            .foregroundStyle(.blue)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
      } header: {
        Text("Session behavior")
      }

      if let error = presentation.errorBanner {
        MemoryNoticeView(
          title: "Memory error",
          message: error,
          systemImage: "exclamationmark.triangle.fill",
          tint: .red,
          actionTitle: "Reload",
          action: actions.onReload
        )
      } else if case let .failed(message) = presentation.loadState {
        MemoryNoticeView(
          title: "Memory may be out of date",
          message: message,
          systemImage: "arrow.triangle.2.circlepath",
          tint: .orange,
          actionTitle: "Reload",
          action: actions.onReload
        )
      }

      listMutationStatus

      if case .loading = presentation.loadState {
        Label("Refreshing memory…", systemImage: "arrow.clockwise")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if presentation.entries.isEmpty {
        if bindings.searchText.wrappedValue.isEmpty {
          ContentUnavailableView(
            "No entries",
            systemImage: bindings.store.wrappedValue.systemImage,
            description: Text("Hermes returned no structured entries for this filter.")
          )
          .listRowBackground(Color.clear)
        } else {
          ContentUnavailableView.search(text: bindings.searchText.wrappedValue)
            .listRowBackground(Color.clear)
        }
      } else {
        Section {
          ForEach(presentation.entries) { entry in
            Button {
              actions.onSelect(entry)
            } label: {
              MemoryEntryRow(entry: entry)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens structured memory details")
          }
        } header: {
          Text("\(bindings.store.wrappedValue.rawValue) · \(presentation.entries.count)")
        }
      }
    }
    .refreshable { actions.onReload() }
    .searchable(
      text: bindings.searchText,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search structured memory"
    )
  }

  private var allowsReload: Bool {
    if case .unsupported = presentation.loadState { return false }
    return true
  }

  @ViewBuilder
  private var listMutationStatus: some View {
    switch presentation.mutationState {
    case .idle, .saving, .deleting:
      EmptyView()
    case let .saved(message):
      MemoryNoticeView(
        title: "Entry saved",
        message: message,
        systemImage: "checkmark.circle.fill",
        tint: .green
      )
    case let .deleted(message):
      MemoryNoticeView(
        title: "Entry deleted",
        message: message,
        systemImage: "trash.fill",
        tint: .green
      )
    case let .archived(message):
      MemoryNoticeView(
        title: "Learned skill archived",
        message: message,
        systemImage: "archivebox.fill",
        tint: .blue
      )
    case let .partial(message):
      MemoryNoticeView(
        title: "Change applied; refresh incomplete",
        message: message,
        systemImage: "exclamationmark.triangle.fill",
        tint: .orange,
        actionTitle: "Reload",
        action: actions.onReload
      )
    case let .failed(message):
      MemoryNoticeView(
        title: "Couldn't update entry",
        message: message,
        systemImage: "xmark.circle.fill",
        tint: .red
      )
    case let .unsupported(message):
      MemoryNoticeView(
        title: "Memory changes aren't supported",
        message: message,
        systemImage: "nosign",
        tint: .secondary
      )
    }
  }
}

private struct MemoryCapacityView: View {
  let capacity: MemoryCapacityPresentation

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Label(
            "\(capacity.title) capacity",
            systemImage: "gauge.with.dots.needle.67percent"
          )
            .font(.subheadline.weight(.semibold))
          Spacer(minLength: 8)
          Text("\(capacity.entryCount.formatted()) entries")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let fraction = capacity.fraction {
          ProgressView(value: fraction)
            .tint(capacity.isNearLimit ? .orange : .blue)
        }

        Text(capacity.usageLabel)
          .font(.footnote)
          .foregroundStyle(capacity.isNearLimit ? Color.orange : Color.secondary)

        if capacity.isNearLimit {
          Label(
            "Memory is nearing its server-reported capacity.",
            systemImage: "exclamationmark.triangle.fill"
          )
            .font(.footnote)
            .foregroundStyle(.orange)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(
        "\(capacity.title) capacity. \(capacity.usageLabel). \(capacity.entryCount) entries."
      )
    }
  }
}

private struct MemoryEntryRow: View {
  let entry: MemoryEntryPresentation

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
          Text(entry.title)
            .font(.body.weight(.semibold))
          Text(entry.store.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(storeTint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
              storeTint.opacity(0.14),
              in: .capsule
            )
          if entry.isArchived {
            Text("Archived")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
          }
        }

        if !entry.summary.isEmpty {
          Text(entry.summary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        ViewThatFits(in: .horizontal) {
          HStack(spacing: 10) { metadata }
          VStack(alignment: .leading, spacing: 3) { metadata }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Image(systemName: "chevron.forward")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 3)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var metadata: some View {
    if let category = entry.category, !category.isEmpty {
      Label(category, systemImage: "tag")
    }
    if let updated = entry.updatedLabel, !updated.isEmpty {
      Label(updated, systemImage: "clock")
    }
  }

  private var storeTint: Color {
    switch entry.store {
    case .all: .secondary
    case .userProfile: .blue
    case .agentMemory: .purple
    case .learnedSkill: .green
    }
  }
}

struct MemoryDetailPresentation: Equatable {
  let entry: MemoryEntryPresentation
  let loadState: MemoryLoadPresentation
  let mutationState: MemoryMutationPresentation
  let isDirty: Bool
  let canSave: Bool
  let canDeleteOrArchive: Bool
  let errorBanner: String?
  let sessionSnapshotExplanation: String
}

struct MemoryEditBindings {
  let content: Binding<String>
}

struct MemoryDetailActions {
  let onClose: () -> Void
  let onReload: () -> Void
  let onSave: () -> Void
  let onDeleteOrArchive: () -> Void
}

/// Structured entry detail/editor. Editing is intentionally field-based plain text; there is
/// no raw Markdown/document replacement surface.
struct MemoryDetailContent: View {
  let presentation: MemoryDetailPresentation
  let bindings: MemoryEditBindings
  let actions: MemoryDetailActions

  var body: some View {
    Group {
      switch presentation.loadState {
      case .loading:
        ProgressView("Loading entry…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case let .failed(message):
        ContentUnavailableView {
          Label("Couldn't load entry", systemImage: "doc.text.magnifyingglass")
        } description: {
          Text(message)
        } actions: {
          Button("Try again", action: actions.onReload)
            .buttonStyle(.borderedProminent)
        }
      case let .unsupported(message):
        ContentUnavailableView {
          Label("Entry details aren't available", systemImage: "nosign")
        } description: {
          Text(message)
        }
      case .loaded:
        detailForm
      }
    }
    .navigationTitle(presentation.entry.title)
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(action: actions.onClose) {
          Label("Back to memory", systemImage: "chevron.backward")
            .labelStyle(.iconOnly)
        }
        .accessibilityHint(
          presentation.isDirty
            ? "Shows a confirmation before discarding unsaved changes"
            : "Returns to the memory list"
        )
      }

      if presentation.loadState == .loaded {
        ToolbarItem(placement: .confirmationAction) {
          Button(action: actions.onSave) {
            if presentation.mutationState == .saving {
              ProgressView()
                .accessibilityLabel("Saving memory entry")
            } else {
              Text("Save")
            }
          }
          .disabled(!presentation.canSave || presentation.mutationState == .saving)
          .accessibilityHint("Saves this structured entry and verifies it with Hermes")
        }
      }
    }
  }

  private var detailForm: some View {
    Form {
      if let error = presentation.errorBanner {
        MemoryNoticeView(
          title: "Entry error",
          message: error,
          systemImage: "exclamationmark.triangle.fill",
          tint: .red
        )
      }

      mutationStatus

      editSection
      detailMetadata

      Section {
        Label(presentation.sessionSnapshotExplanation, systemImage: "camera.aperture")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } header: {
        Text("Session behavior")
      }

      Section {
        Button(
          presentation.entry.operationLabel,
          role: presentation.entry.operationIsDestructive ? .destructive : nil,
          action: actions.onDeleteOrArchive
        )
        .disabled(!presentation.canDeleteOrArchive || isMutating)
        .accessibilityHint(
          presentation.entry.operationIsDestructive
            ? "Asks for confirmation before permanently deleting this entry"
            : "Asks for confirmation before archiving this learned skill"
        )
      } header: {
        Text("Entry operations")
      }
    }
  }

  private var editSection: some View {
    Section {
      TextField("Entry text", text: bindings.content, axis: .vertical)
        .lineLimit(5...16)
      if presentation.isDirty {
        Label("Unsaved changes", systemImage: "circle.fill")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.orange)
          .accessibilityHint("Leaving will ask before discarding this draft")
      }
    } header: {
      Text("Structured entry")
    } footer: {
      Text(
        "This updates one structured entry. Raw USER or MEMORY document replacement is not available."
      )
    }
  }

  @ViewBuilder
  private var detailMetadata: some View {
    if presentation.entry.category != nil || !presentation.entry.tags.isEmpty
        || presentation.entry.source != nil || presentation.entry.createdLabel != nil
        || presentation.entry.updatedLabel != nil {
      Section("Details") {
        if let category = presentation.entry.category, !category.isEmpty {
          LabeledContent("Category", value: category)
        }
        if let source = presentation.entry.source, !source.isEmpty {
          LabeledContent("Source", value: source)
        }
        if let created = presentation.entry.createdLabel, !created.isEmpty {
          LabeledContent("Created", value: created)
        }
        if let updated = presentation.entry.updatedLabel, !updated.isEmpty {
          LabeledContent("Updated", value: updated)
        }
        if !presentation.entry.tags.isEmpty {
          LabeledContent("Tags", value: presentation.entry.tags.joined(separator: ", "))
        }
      }
    }
  }

  @ViewBuilder
  private var mutationStatus: some View {
    switch presentation.mutationState {
    case .idle, .saving:
      EmptyView()
    case .deleting:
      Section {
        HStack(spacing: 10) {
          ProgressView()
          Text(presentation.entry.operationLabel + "…")
        }
        .foregroundStyle(.secondary)
      }
    case let .saved(message):
      MemoryNoticeView(
        title: "Entry saved",
        message: message,
        systemImage: "checkmark.circle.fill",
        tint: .green
      )
    case let .archived(message):
      MemoryNoticeView(
        title: "Entry updated",
        message: message,
        systemImage: "archivebox.fill",
        tint: .blue
      )
    case let .deleted(message):
      MemoryNoticeView(
        title: "Entry deleted",
        message: message,
        systemImage: "trash.fill",
        tint: .green
      )
    case let .partial(message):
      MemoryNoticeView(
        title: "Change applied; refresh incomplete",
        message: message,
        systemImage: "exclamationmark.triangle.fill",
        tint: .orange,
        actionTitle: "Reload",
        action: actions.onReload
      )
    case let .failed(message):
      MemoryNoticeView(
        title: "Couldn't update entry",
        message: message,
        systemImage: "xmark.circle.fill",
        tint: .red
      )
    case let .unsupported(message):
      MemoryNoticeView(
        title: "Editing isn't supported",
        message: message,
        systemImage: "nosign",
        tint: .secondary
      )
    }
  }

  private var isMutating: Bool {
    presentation.mutationState == .saving || presentation.mutationState == .deleting
  }
}

private struct MemoryNoticeView: View {
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
