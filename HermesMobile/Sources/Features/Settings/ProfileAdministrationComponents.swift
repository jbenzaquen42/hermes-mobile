import SwiftUI

/// Reducer-agnostic presentation models for the profile administration screens.
///
/// `ProfileEditorFeature` owns all behavior and server state. These small value types keep
/// the SwiftUI layout independently snapshot-testable while its reducer contract evolves.
struct ProfileSummaryPresentation: Equatable, Hashable, Identifiable {
  let name: String
  let isDefault: Bool
  let description: String
  let model: String?
  let provider: String?
  let skillCount: Int

  var id: String { name }

  var modelSummary: String {
    switch (provider?.nilIfBlank, model?.nilIfBlank) {
    case let (.some(provider), .some(model)):
      return "\(provider) · \(model)"
    case let (.some(provider), .none):
      return provider
    case let (.none, .some(model)):
      return model
    case (.none, .none):
      return "Uses server defaults"
    }
  }
}

enum ProfileAdministrationLoadPresentation: Equatable {
  case loading
  case loaded
  case failed(String)
  case unsupported(String)
}

/// Native profile list used as the Settings destination. Selection is an action so the
/// owning reducer can synchronously create the scoped editor destination before SwiftUI
/// pushes it onto the navigation stack.
struct ProfileAdministrationList: View {
  let profiles: [ProfileSummaryPresentation]
  let loadState: ProfileAdministrationLoadPresentation
  let onReload: () -> Void
  let onAdd: () -> Void
  let onSelect: (ProfileSummaryPresentation) -> Void

  var body: some View {
    Group {
      switch loadState {
      case .loading where profiles.isEmpty:
        ProgressView("Loading profiles…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case let .failed(message) where profiles.isEmpty:
        unavailable(
          title: "Couldn't load profiles",
          systemImage: "person.crop.circle.badge.exclamationmark",
          description: message,
          retryTitle: "Try again"
        )
      case let .unsupported(message):
        unavailable(
          title: "Profiles aren't available",
          systemImage: "person.crop.circle.badge.questionmark",
          description: message,
          retryTitle: nil
        )
      default:
        profileList
      }
    }
    .navigationTitle("Profiles")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if allowsAddingProfiles {
        ToolbarItem(placement: .primaryAction) {
          Button(action: onAdd) {
            Label("Add profile", systemImage: "plus")
          }
        }
      }
    }
  }

  private var profileList: some View {
    List {
      if loadState == .loading {
        Label("Refreshing profiles…", systemImage: "arrow.clockwise")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if case let .failed(message) = loadState {
        ProfileNoticeView(
          title: "Profiles may be out of date",
          message: message,
          systemImage: "exclamationmark.triangle.fill",
          tint: .orange,
          actions: [("Reload", onReload)]
        )
      }

      Section {
        ForEach(profiles) { profile in
          Button {
            onSelect(profile)
          } label: {
            HStack(spacing: 10) {
              ProfileAdministrationRow(profile: profile)
              Spacer(minLength: 4)
              Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityHint("Opens profile settings")
        }
      } footer: {
        Text("Each profile has its own model, persona, skills, toolsets, and MCP servers.")
      }
    }
    .refreshable { onReload() }
  }

  private var allowsAddingProfiles: Bool {
    if case .unsupported = loadState { return false }
    return true
  }

  private func unavailable(
    title: String,
    systemImage: String,
    description: String,
    retryTitle: String?
  ) -> some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(description)
    } actions: {
      if let retryTitle {
        Button(retryTitle, action: onReload)
          .buttonStyle(.borderedProminent)
      }
    }
  }
}

private struct ProfileAdministrationRow: View {
  let profile: ProfileSummaryPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(profile.name)
          .font(.body.weight(.semibold))
        if profile.isDefault {
          Text("Default")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.14), in: .capsule)
        }
      }

      if !profile.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(profile.description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          Label(profile.modelSummary, systemImage: "cpu")
          Label("\(profile.skillCount) skills", systemImage: "sparkles")
        }
        VStack(alignment: .leading, spacing: 4) {
          Label(profile.modelSummary, systemImage: "cpu")
          Label("\(profile.skillCount) skills", systemImage: "sparkles")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilitySummary)
  }

  private var accessibilitySummary: String {
    let role = profile.isDefault ? ", default profile" : ""
    return "\(profile.name)\(role). \(profile.modelSummary). \(profile.skillCount) skills."
  }
}

enum ProfileSoulModePresentation: String, CaseIterable, Identifiable {
  case edit = "Edit"
  case preview = "Preview"

  var id: Self { self }
}

enum ProfileEditorLoadPresentation: Equatable {
  case loading
  case loaded
  case failed(String)
  case unsupported(String)
}

enum ProfileEditorSavePresentation: Equatable {
  case idle
  case saving
  case saved(String)
  case partial(saved: [String], failed: [String])
  case failed(String)
}

enum ProfileCapabilityKind: Equatable {
  case skill
  case toolset
  case mcpServer
}

struct ProfileCapabilityOptionPresentation: Equatable, Identifiable {
  let name: String
  let detail: String?
  let isEnabled: Bool

  var id: String { name }
}

struct ProfileCapabilitySummaryPresentation: Equatable {
  let kind: ProfileCapabilityKind
  let title: String
  let systemImage: String
  let options: [ProfileCapabilityOptionPresentation]
  var isSupported = true

  var selectedNames: [String] {
    options.filter(\.isEnabled).map(\.name)
  }

  var countSummary: String {
    guard isSupported else { return "Unavailable" }
    return "\(selectedNames.count) of \(options.count) enabled"
  }
}

struct ProfileRecoveredDraftPresentation: Equatable {
  let message: String
}

/// Pure form state consumed by `ProfileEditorContent`. Counts, dirty state, load/save
/// phases, and recovery decisions are intentionally inputs rather than re-derived here.
struct ProfileEditorPresentation: Equatable {
  let profileName: String
  let isDefault: Bool
  let loadState: ProfileEditorLoadPresentation
  let isDirty: Bool
  let canSave: Bool
  let canRename: Bool
  let isRenaming: Bool
  let isDeleting: Bool
  let nameError: String?
  let characterCount: Int
  let estimatedTokenCount: Int
  let errorBanner: String?
  let saveState: ProfileEditorSavePresentation
  let recoveredDraft: ProfileRecoveredDraftPresentation?
  let capabilities: [ProfileCapabilitySummaryPresentation]
  let reasoningOptions: [String]
}

/// All bindings/actions needed by the editor view. Keeping this as a single value prevents
/// the eventual store adapter from spreading feature-action knowledge through every section.
struct ProfileEditorBindings {
  let name: Binding<String>
  let description: Binding<String>
  let model: Binding<String>
  let provider: Binding<String>
  let reasoningEffort: Binding<String>
  let soul: Binding<String>
  let soulMode: Binding<ProfileSoulModePresentation>
}

struct ProfileEditorActions {
  let onClose: () -> Void
  let onReload: () -> Void
  let onSave: () -> Void
  let onRestoreDraft: () -> Void
  let onDiscardRecoveredDraft: () -> Void
  let onSetCapabilityEnabled: (ProfileCapabilityKind, String, Bool) -> Void
  let onRename: () -> Void
  let onDelete: () -> Void
}

/// Profile detail/editor form. It deliberately contains no persistence or mutation logic:
/// every field is bound to reducer state and every operation dispatches a feature action.
struct ProfileEditorContent: View {
  let presentation: ProfileEditorPresentation
  let bindings: ProfileEditorBindings
  let actions: ProfileEditorActions

  @ScaledMetric(relativeTo: .body) private var soulEditorHeight: CGFloat = 190

  var body: some View {
    Group {
      switch presentation.loadState {
      case .loading:
        ProgressView("Loading \(presentation.profileName)…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case let .failed(message):
        ContentUnavailableView {
          Label("Couldn't load profile", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
          Text(message)
        } actions: {
          Button("Try again", action: actions.onReload)
            .buttonStyle(.borderedProminent)
        }
      case let .unsupported(message):
        ContentUnavailableView {
          Label("Profile editing isn't available", systemImage: "person.crop.circle.badge.questionmark")
        } description: {
          Text(message)
        }
      case .loaded:
        editorForm
      }
    }
    .navigationTitle(presentation.profileName)
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(action: actions.onClose) {
          Label("Back to profiles", systemImage: "chevron.backward")
            .labelStyle(.iconOnly)
        }
        .accessibilityHint(
          presentation.isDirty
            ? "Shows a confirmation before discarding unsaved changes"
            : "Returns to the profile list"
        )
      }
      if presentation.loadState == .loaded {
        ToolbarItem(placement: .confirmationAction) {
          Button(action: actions.onSave) {
            if presentation.saveState == .saving {
              ProgressView()
                .accessibilityLabel("Saving profile")
            } else {
              Text("Save")
            }
          }
          .disabled(!presentation.canSave || presentation.saveState == .saving)
          .accessibilityHint("Saves all profile changes")
        }
      }
    }
  }

  private var editorForm: some View {
    Form {
      if let recoveredDraft = presentation.recoveredDraft {
        ProfileNoticeView(
          title: "Recovered SOUL draft",
          message: recoveredDraft.message,
          systemImage: "clock.arrow.circlepath",
          tint: .blue,
          actions: [
            ("Restore", actions.onRestoreDraft),
            ("Keep server version", actions.onDiscardRecoveredDraft),
          ]
        )
      }

      if let errorBanner = presentation.errorBanner {
        ProfileNoticeView(
          title: "Profile error",
          message: errorBanner,
          systemImage: "exclamationmark.triangle.fill",
          tint: .red
        )
      }

      saveStatus
      identitySection
      modelSection
      soulSection
      capabilitiesSection
      destructiveSection
    }
  }

  private var identitySection: some View {
    Section {
      TextField("Name", text: bindings.name)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .disabled(presentation.isDefault)
        .foregroundStyle(presentation.nameError == nil ? Color.primary : Color.red)
        .accessibilityHint(
          presentation.isDefault
            ? "The default profile cannot be renamed"
            : "Profile identifier"
        )

      TextField("Description", text: bindings.description, axis: .vertical)
        .lineLimit(2...6)
    } header: {
      Text("Identity")
    } footer: {
      if let nameError = presentation.nameError {
        Text(nameError)
          .foregroundStyle(.red)
      } else if presentation.isDefault {
        Text("The default profile's name can't be changed.")
      } else {
        Text("Change the name here, then use Rename profile below.")
      }
    }
  }

  private var modelSection: some View {
    Section {
      TextField("Provider", text: bindings.provider)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      TextField("Model", text: bindings.model)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

      Picker("Reasoning effort", selection: bindings.reasoningEffort) {
        ForEach(reasoningChoices, id: \.self) { effort in
          Text(effort.isEmpty ? "Server default" : effort.capitalized)
            .tag(effort)
        }
      }
    } header: {
      Text("Model & reasoning")
    } footer: {
      Text("Leave provider or model blank to inherit the server default.")
    }
  }

  private var soulSection: some View {
    Section {
      Picker("SOUL view", selection: bindings.soulMode) {
        ForEach(ProfileSoulModePresentation.allCases) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityHint("Switches between editing and rendered Markdown preview")

      switch bindings.soulMode.wrappedValue {
      case .edit:
        ZStack(alignment: .topLeading) {
          if bindings.soul.wrappedValue.isEmpty {
            Text("Describe this profile's persona, priorities, and boundaries in Markdown.")
              .foregroundStyle(.tertiary)
              .padding(.horizontal, 5)
              .padding(.vertical, 8)
              .accessibilityHidden(true)
          }
          TextEditor(text: bindings.soul)
            .font(.body.monospaced())
            .frame(minHeight: min(soulEditorHeight, 320))
            .scrollContentBackground(.hidden)
            .accessibilityLabel("SOUL Markdown")
        }
      case .preview:
        Group {
          if bindings.soul.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
              "Nothing to preview",
              systemImage: "doc.plaintext",
              description: Text("Add SOUL Markdown in Edit mode.")
            )
          } else {
            MarkdownText(
              text: bindings.soul.wrappedValue,
              copiedToken: nil,
              tokenPrefix: "profile-soul",
              onCopyCode: nil
            )
            .padding(.vertical, 6)
          }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .accessibilityLabel("SOUL Markdown preview")
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          Text("\(presentation.characterCount.formatted()) characters")
          Spacer(minLength: 8)
          Text("About \(presentation.estimatedTokenCount.formatted()) tokens")
        }
        VStack(alignment: .leading, spacing: 3) {
          Text("\(presentation.characterCount.formatted()) characters")
          Text("About \(presentation.estimatedTokenCount.formatted()) tokens")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityElement(children: .combine)

      if presentation.isDirty {
        Label("Unsaved changes", systemImage: "circle.fill")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.orange)
          .accessibilityHint("Leaving this screen will ask before discarding changes")
      }
    } header: {
      Text("SOUL.md")
    } footer: {
      Text(
        "SOUL is the profile's system persona. Preview renders the Markdown that will be saved."
      )
    }
  }

  @ViewBuilder
  private var capabilitiesSection: some View {
    if !presentation.capabilities.isEmpty {
      Section {
        ForEach(Array(presentation.capabilities.enumerated()), id: \.offset) { _, capability in
          ProfileCapabilitySummaryRow(
            capability: capability,
            onSetEnabled: { name, enabled in
              actions.onSetCapabilityEnabled(capability.kind, name, enabled)
            }
          )
        }
      } header: {
        Text("Capabilities")
      } footer: {
        Text("Unknown server entries are preserved when this profile is saved.")
      }
    }
  }

  @ViewBuilder
  private var destructiveSection: some View {
    Section {
      if presentation.isDefault {
        Label("The default profile can't be renamed or deleted.", systemImage: "lock.fill")
          .font(.footnote)
          .foregroundStyle(.secondary)
      } else {
        Button(action: actions.onRename) {
          HStack {
            Text("Rename profile")
            if presentation.isRenaming {
              Spacer()
              ProgressView()
            }
          }
        }
        .disabled(!presentation.canRename)

        Button(role: .destructive, action: actions.onDelete) {
          HStack {
            Text("Delete profile")
            if presentation.isDeleting {
              Spacer()
              ProgressView()
            }
          }
        }
        .disabled(presentation.isDeleting || presentation.isRenaming)
      }
    } header: {
      Text("Profile operations")
    }
  }

  @ViewBuilder
  private var saveStatus: some View {
    switch presentation.saveState {
    case .idle, .saving:
      EmptyView()
    case let .saved(message):
      ProfileNoticeView(
        title: "Profile saved",
        message: message,
        systemImage: "checkmark.circle.fill",
        tint: .green
      )
    case let .partial(saved, failed):
      ProfileNoticeView(
        title: "Some changes weren't saved",
        message: partialSaveMessage(saved: saved, failed: failed),
        systemImage: "exclamationmark.triangle.fill",
        tint: .orange,
        actions: [("Retry save", actions.onSave)]
      )
    case let .failed(message):
      ProfileNoticeView(
        title: "Couldn't save profile",
        message: message,
        systemImage: "xmark.circle.fill",
        tint: .red,
        actions: [("Try again", actions.onSave)]
      )
    }
  }

  private var reasoningChoices: [String] {
    var choices = presentation.reasoningOptions
    let selection = bindings.reasoningEffort.wrappedValue
    if !choices.contains(selection) { choices.append(selection) }
    return choices
  }

  private func partialSaveMessage(saved: [String], failed: [String]) -> String {
    let savedText = saved.isEmpty
      ? "No sections were confirmed saved."
      : "Saved: \(saved.joined(separator: ", "))."
    let failedText = failed.isEmpty
      ? "Reload to verify the remaining fields."
      : "Not saved: \(failed.joined(separator: ", "))."
    return "\(savedText) \(failedText) Your unsaved values are still here."
  }
}

private struct ProfileCapabilitySummaryRow: View {
  let capability: ProfileCapabilitySummaryPresentation
  let onSetEnabled: (String, Bool) -> Void

  var body: some View {
    if capability.isSupported, !capability.options.isEmpty {
      DisclosureGroup {
        ForEach(capability.options) { option in
          Toggle(
            isOn: Binding(
              get: { option.isEnabled },
              set: { onSetEnabled(option.name, $0) }
            )
          ) {
            VStack(alignment: .leading, spacing: 2) {
              Text(option.name)
              if let detail = option.detail, !detail.isEmpty {
                Text(detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .accessibilityHint("Changes take effect after saving the profile")
        }
      } label: {
        summary
      }
    } else {
      summary
    }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 5) {
      LabeledContent {
        Text(capability.countSummary)
          .foregroundStyle(.secondary)
      } label: {
        Label(capability.title, systemImage: capability.systemImage)
      }
      if capability.isSupported, !capability.selectedNames.isEmpty {
        Text(capability.selectedNames.joined(separator: " · "))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct ProfileNoticeView: View {
  let title: String
  let message: String
  let systemImage: String
  let tint: Color
  var actions: [(String, () -> Void)] = []

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
        if !actions.isEmpty {
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { actionButtons }
            VStack(alignment: .leading, spacing: 8) { actionButtons }
          }
        }
      }
      .accessibilityElement(children: .contain)
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
      Button(action.0, action: action.1)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
  }
}

private extension String {
  var nilIfBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
