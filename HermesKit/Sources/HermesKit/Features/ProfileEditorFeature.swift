import ComposableArchitecture
import Foundation

/// Server-authoritative profile settings and SOUL editor.
///
/// Every read/write carries `profileName`; this feature never changes Hermes' process-wide
/// active profile. Configure is an explicit, section-aware Save: the server may apply some
/// sections and reject or omit others, so the reducer retains unconfirmed edits and reports
/// exactly what Hermes acknowledged.
@Reducer
public struct ProfileEditorFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    public var profileName: String
    public var isDefault: Bool
    public var renameDraft: String
    public var description: String
    public var soul: String
    public var provider: String
    public var model: String
    public var reasoningEffort: String
    public var skills: [ProfileSkill]
    public var toolsets: [ProfileToolset]
    public var toolsetsPinned: Bool
    public var mcpServers: [ProfileMCPServer]
    public var soulMode: SoulMode
    public var loadState: LoadState
    public var saveState: SaveState
    public var errorBanner: String?
    public var recoveredDraft: ProfileEditorDraft?
    public var isRenaming: Bool
    public var isDeleting: Bool
    public var nameError: String?
    public var describeSupported: Bool?
    public var configureSupported: Bool?
    @Presents public var confirmationDialog: ConfirmationDialogState<Action.Dialog>?

    /// The latest server-authoritative baseline. `nil` until describe succeeds.
    var original: Values?

    public init(
      connection: ServerConnection,
      summary: ProfileAdminSummary,
      soulMode: SoulMode = .edit
    ) {
      self.connection = connection
      profileName = summary.name
      isDefault = summary.isDefault
      renameDraft = summary.name
      description = summary.profileDescription
      soul = ""
      provider = summary.provider ?? ""
      model = summary.model ?? ""
      reasoningEffort = ""
      skills = []
      toolsets = []
      toolsetsPinned = false
      mcpServers = []
      self.soulMode = soulMode
      loadState = .idle
      saveState = .idle
      errorBanner = nil
      recoveredDraft = nil
      isRenaming = false
      isDeleting = false
      nameError = nil
      describeSupported = nil
      configureSupported = nil
      original = nil
    }

    public enum SoulMode: String, Equatable, Sendable, CaseIterable {
      case edit
      case preview
    }

    public enum LoadState: Equatable, Sendable {
      case idle
      case loading
      case loaded
      case failed(String)
      case unsupported
    }

    public enum SaveState: Equatable, Sendable {
      case idle
      case saving
      case saved(SaveReport)
      case partial(SaveReport)
      case failed(String)
      case unsupported
    }

    public var isDirty: Bool {
      guard let original else { return false }
      return currentValues != original || renameDraft != profileName
    }

    public var canSave: Bool {
      guard original != nil, currentValues != original else { return false }
      guard configureSupported != false, !isRenaming, !isDeleting else { return false }
      if case .saving = saveState { return false }
      return true
    }

    public var canRename: Bool {
      let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      return !isDefault && !isRenaming && !isDeleting && trimmed != profileName
        && ProfileName.isValid(trimmed)
    }

    public var characterCount: Int { soul.count }

    /// A deliberately approximate count for a mixed prose/Markdown prompt. Four characters
    /// per token is the familiar planning estimate; the UI labels it "About", never exact.
    public var estimatedTokenCount: Int {
      guard !soul.isEmpty else { return 0 }
      return (soul.count + 3) / 4
    }

    public var reasoningOptions: [String] { ["", "none", "low", "medium", "high"] }

    public var recoveredDraftConflictsWithServer: Bool {
      guard let recoveredDraft else { return false }
      return recoveredDraft.baseline != original.map {
        ProfileEditorDraft.Snapshot(values: $0)
      }
    }

    var currentValues: Values {
      get {
        Values(
          description: description,
          soul: soul,
          provider: provider,
          model: model,
          reasoningEffort: reasoningEffort,
          skills: skills,
          toolsets: toolsets,
          toolsetsPinned: toolsetsPinned,
          mcpServers: mcpServers
        )
      }
      set {
        description = newValue.description
        soul = newValue.soul
        provider = newValue.provider
        model = newValue.model
        reasoningEffort = newValue.reasoningEffort
        skills = newValue.skills
        toolsets = newValue.toolsets
        toolsetsPinned = newValue.toolsetsPinned
        mcpServers = newValue.mcpServers
      }
    }
  }

  public struct SaveReport: Equatable, Sendable {
    public var applied: [ProfileConfigureSection]
    public var failed: [ProfileConfigureSection]
    public var unreported: [ProfileConfigureSection]
    public var reloadError: String?

    public init(
      applied: [ProfileConfigureSection] = [],
      failed: [ProfileConfigureSection] = [],
      unreported: [ProfileConfigureSection] = [],
      reloadError: String? = nil
    ) {
      self.applied = applied
      self.failed = failed
      self.unreported = unreported
      self.reloadError = reloadError
    }

    public var appliedNames: [String] { applied.map(\.displayName) }
    public var failedNames: [String] { (failed + unreported).map(\.displayName) }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case task
    case load
    case reloadTapped
    case loadResponse(LoadResponse)
    case saveTapped
    case saveResponse(SaveResponse)
    case closeTapped
    case restoreDraftTapped
    case discardRecoveredDraftTapped
    case setSkillEnabled(name: String, enabled: Bool)
    case setToolsetEnabled(name: String, enabled: Bool)
    case setMCPServerEnabled(name: String, enabled: Bool)
    case renameTapped
    case renameResponse(Result<RenameResult, ProfileMutationFailure>)
    case deleteTapped
    case deleteResponse(Result<String, ProfileMutationFailure>)
    case confirmationDialog(PresentationAction<Dialog>)
    case delegate(Delegate)

    @CasePathable
    public enum Dialog: Equatable, Sendable {
      case discardAndClose
      case discardAndReload
      case confirmRename(oldName: String, newName: String)
      case confirmDelete(name: String)
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case closed
      case renamed(oldName: String, newName: String)
      case deleted(name: String)
    }
  }

  @CasePathable
  public enum LoadResponse: Equatable, Sendable {
    case loaded(ProfileDescription, ProfileEditorDraft?)
    case unsupported
    case failed(String)
  }

  @CasePathable
  public enum SaveResponse: Equatable, Sendable {
    case configured(
      result: ProfileConfigureResult,
      submission: Values,
      authoritative: ProfileDescription?,
      reloadError: String?
    )
    case unsupported
    case failed(String)
  }

  public struct RenameResult: Equatable, Sendable {
    public var oldName: String
    public var newName: String

    public init(oldName: String, newName: String) {
      self.oldName = oldName
      self.newName = newName
    }
  }

  public struct ProfileMutationFailure: Error, Equatable, Sendable {
    public var message: String
    public init(message: String) { self.message = message }
  }

  /// Codable, non-secret draft payload. Capability metadata is reduced to name/selection;
  /// current server metadata wins when a draft is restored.
  public struct ProfileEditorDraft: Equatable, Codable, Sendable {
    public var baseline: Snapshot
    public var edited: Snapshot
    public var renameDraft: String
    public var savedAt: Date

    public init(baseline: Snapshot, edited: Snapshot, renameDraft: String, savedAt: Date) {
      self.baseline = baseline
      self.edited = edited
      self.renameDraft = renameDraft
      self.savedAt = savedAt
    }

    public struct Snapshot: Equatable, Codable, Sendable {
      public var description: String
      public var soul: String
      public var provider: String
      public var model: String
      public var reasoningEffort: String
      public var skills: [Selection]
      public var toolsets: [Selection]
      public var toolsetsPinned: Bool
      public var mcpServers: [Selection]

      public init(values: Values) {
        description = values.description
        soul = values.soul
        provider = values.provider
        model = values.model
        reasoningEffort = values.reasoningEffort
        skills = values.skills.map { Selection(name: $0.name, enabled: $0.enabled) }
        toolsets = values.toolsets.map { Selection(name: $0.name, enabled: $0.enabled) }
        toolsetsPinned = values.toolsetsPinned
        mcpServers = values.mcpServers.map { Selection(name: $0.name, enabled: $0.enabled) }
      }
    }

    public struct Selection: Equatable, Codable, Sendable {
      public var name: String
      public var enabled: Bool
      public init(name: String, enabled: Bool) {
        self.name = name
        self.enabled = enabled
      }
    }
  }

  public struct Values: Equatable, Sendable {
    public var description: String
    public var soul: String
    public var provider: String
    public var model: String
    public var reasoningEffort: String
    public var skills: [ProfileSkill]
    public var toolsets: [ProfileToolset]
    public var toolsetsPinned: Bool
    public var mcpServers: [ProfileMCPServer]

    public init(
      description: String,
      soul: String,
      provider: String,
      model: String,
      reasoningEffort: String,
      skills: [ProfileSkill],
      toolsets: [ProfileToolset],
      toolsetsPinned: Bool,
      mcpServers: [ProfileMCPServer]
    ) {
      self.description = description
      self.soul = soul
      self.provider = provider
      self.model = model
      self.reasoningEffort = reasoningEffort
      self.skills = skills
      self.toolsets = toolsets
      self.toolsetsPinned = toolsetsPinned
      self.mcpServers = mcpServers
    }

    init(_ description: ProfileDescription) {
      self.init(
        description: description.description,
        soul: description.soul,
        provider: description.model.provider,
        model: description.model.defaultModel,
        reasoningEffort: description.reasoningEffort ?? "",
        skills: description.skills,
        toolsets: description.toolsets,
        toolsetsPinned: description.toolsetsPinned,
        mcpServers: description.mcpServers
      )
    }
  }

  @Dependency(\.hermesProfileAdmin) var profileAdmin
  @Dependency(\.hermesProfiles) var profilesREST
  @Dependency(\.profileDraft) var profileDraft
  @Dependency(\.date.now) var now

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .task:
        guard state.loadState == .idle else { return .none }
        return .send(.load)

      case .load:
        state.loadState = .loading
        state.errorBanner = nil
        let connection = state.connection
        let name = state.profileName
        return .run { [profileAdmin, profileDraft] send in
          do {
            let description = try await profileAdmin.describe(connection, name)
            let recovered = profileDraft.load(connection.baseURL, name)
              .flatMap { try? JSONDecoder().decode(ProfileEditorDraft.self, from: $0) }
            await send(.loadResponse(.loaded(description, recovered)))
          } catch let error as ProfileAdminError {
            await send(.loadResponse(error == .unsupported ? .unsupported : .failed(error.message)))
          } catch {
            await send(.loadResponse(.failed("Couldn’t load the profile.")))
          }
        }

      case .reloadTapped:
        guard !state.isDirty else {
          state.confirmationDialog = Self.discardDialog(action: .discardAndReload)
          return .none
        }
        return .send(.load)

      case let .loadResponse(.loaded(description, recovered)):
        guard description.name == state.profileName else {
          state.loadState = .failed("Hermes returned a different profile than requested.")
          state.errorBanner = "The profile response was not scoped to \(state.profileName)."
          return .none
        }
        let values = Values(description)
        state.currentValues = values
        state.original = values
        state.renameDraft = state.profileName
        state.loadState = .loaded
        state.describeSupported = true
        state.errorBanner = nil
        state.saveState = .idle
        if let recovered,
           recovered.edited != ProfileEditorDraft.Snapshot(values: values)
             || recovered.renameDraft != state.profileName {
          state.recoveredDraft = recovered
        } else {
          state.recoveredDraft = nil
          profileDraft.remove(state.connection.baseURL, state.profileName)
        }
        return .none

      case .loadResponse(.unsupported):
        state.loadState = .unsupported
        state.describeSupported = false
        state.configureSupported = false
        state.errorBanner = ProfileAdminError.unsupported.message
        return .none

      case let .loadResponse(.failed(message)):
        state.loadState = .failed(message)
        state.errorBanner = message
        return .none

      case .binding:
        guard state.loadState == .loaded else { return .none }
        state.nameError = nil
        if case .saved = state.saveState { state.saveState = .idle }
        return persistDraft(for: state)

      case let .setSkillEnabled(name, enabled):
        guard let index = state.skills.firstIndex(where: { $0.name == name }) else { return .none }
        state.skills[index].enabled = enabled
        state.saveState = .idle
        return persistDraft(for: state)

      case let .setToolsetEnabled(name, enabled):
        guard let index = state.toolsets.firstIndex(where: { $0.name == name }) else { return .none }
        state.toolsets[index].enabled = enabled
        // An empty list has a defined Hermes meaning: clear the explicit pin and inherit the
        // server defaults. A non-empty edited selection is an explicit pin.
        state.toolsetsPinned = state.toolsets.contains(where: \.enabled)
        state.saveState = .idle
        return persistDraft(for: state)

      case let .setMCPServerEnabled(name, enabled):
        guard let index = state.mcpServers.firstIndex(where: { $0.name == name }) else { return .none }
        state.mcpServers[index].enabled = enabled
        state.saveState = .idle
        return persistDraft(for: state)

      case .restoreDraftTapped:
        guard let draft = state.recoveredDraft, let original = state.original else { return .none }
        state.currentValues = Self.restore(draft.edited, over: original)
        state.renameDraft = state.isDefault ? state.profileName : draft.renameDraft
        state.recoveredDraft = nil
        state.saveState = .idle
        return persistDraft(for: state)

      case .discardRecoveredDraftTapped:
        state.recoveredDraft = nil
        profileDraft.remove(state.connection.baseURL, state.profileName)
        return .none

      case .saveTapped:
        guard state.canSave, let original = state.original else { return .none }
        let submission = state.currentValues
        let request = Self.configureRequest(
          name: state.profileName, original: original, edited: submission
        )
        guard !request.requestedSections.isEmpty else { return .none }
        state.saveState = .saving
        state.errorBanner = nil
        let connection = state.connection
        let name = state.profileName
        return .run { [profileAdmin] send in
          do {
            let result = try await profileAdmin.configure(connection, request)
            var authoritative: ProfileDescription?
            var reloadError: String?
            do {
              let reloaded = try await profileAdmin.describe(connection, name)
              if reloaded.name == name {
                authoritative = reloaded
              } else {
                reloadError = "Hermes returned a different profile while reloading."
              }
            } catch let error as ProfileAdminError {
              reloadError = error.message
            } catch {
              reloadError = "The saved profile could not be reloaded."
            }
            await send(.saveResponse(.configured(
              result: result,
              submission: submission,
              authoritative: authoritative,
              reloadError: reloadError
            )))
          } catch let error as ProfileAdminError {
            await send(.saveResponse(error == .unsupported ? .unsupported : .failed(error.message)))
          } catch {
            await send(.saveResponse(.failed("Couldn’t save the profile.")))
          }
        }

      case let .saveResponse(.configured(result, submission, authoritative, reloadError)):
        state.configureSupported = true
        let report = SaveReport(
          applied: result.appliedSections.sorted(by: Self.sectionOrder),
          failed: result.failedSections.sorted(by: Self.sectionOrder),
          unreported: result.unreportedSections.sorted(by: Self.sectionOrder),
          reloadError: reloadError
        )
        Self.reconcile(
          state: &state,
          result: result,
          submission: submission,
          authoritative: authoritative.map { Values($0) }
        )
        if result.isCompleteSuccess {
          state.saveState = .saved(report)
        } else {
          state.saveState = .partial(report)
        }
        state.errorBanner = reloadError
        return persistDraft(for: state)

      case .saveResponse(.unsupported):
        state.configureSupported = false
        state.saveState = .unsupported
        state.errorBanner = ProfileAdminError.unsupported.message
        return persistDraft(for: state)

      case let .saveResponse(.failed(message)):
        state.saveState = .failed(message)
        state.errorBanner = message
        return persistDraft(for: state)

      case .closeTapped:
        guard state.isDirty else { return .send(.delegate(.closed)) }
        state.confirmationDialog = Self.discardDialog(action: .discardAndClose)
        return .none

      case .renameTapped:
        guard !state.isDefault else { return .none }
        let newName = state.renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newName != state.profileName else {
          state.nameError = nil
          return .none
        }
        guard ProfileName.isValid(newName) else {
          state.nameError = ProfileName.hint
          return .none
        }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Rename profile?")
        } actions: {
          ButtonState(
            role: .destructive,
            action: .confirmRename(oldName: state.profileName, newName: newName)
          ) { TextState("Rename") }
          ButtonState(role: .cancel) { TextState("Cancel") }
        } message: {
          TextState("Sessions and local recovery state will move to the new profile name.")
        }
        return .none

      case let .confirmationDialog(.presented(.confirmRename(oldName, newName))):
        guard !state.isDefault, oldName == state.profileName, state.canRename else { return .none }
        state.isRenaming = true
        state.errorBanner = nil
        let connection = state.connection
        return .run { [profilesREST] send in
          do {
            try await profilesREST.rename(connection, oldName, newName)
            await send(.renameResponse(.success(.init(oldName: oldName, newName: newName))))
          } catch let error as RESTError {
            await send(.renameResponse(.failure(.init(message: error.message))))
          } catch {
            await send(.renameResponse(.failure(.init(message: "Couldn’t rename the profile."))))
          }
        }

      case let .renameResponse(.success(result)):
        state.isRenaming = false
        profileDraft.remove(state.connection.baseURL, result.oldName)
        state.profileName = result.newName
        state.renameDraft = result.newName
        let persistence = persistDraft(for: state)
        return .merge(
          persistence,
          .send(.delegate(.renamed(oldName: result.oldName, newName: result.newName)))
        )

      case let .renameResponse(.failure(failure)):
        state.isRenaming = false
        state.errorBanner = failure.message
        return .none

      case .deleteTapped:
        guard !state.isDefault else { return .none }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Delete profile?")
        } actions: {
          ButtonState(role: .destructive, action: .confirmDelete(name: state.profileName)) {
            TextState("Delete")
          }
          ButtonState(role: .cancel) { TextState("Cancel") }
        } message: {
          TextState("This permanently deletes the profile and its sessions on the server.")
        }
        return .none

      case let .confirmationDialog(.presented(.confirmDelete(name))):
        guard !state.isDefault, name == state.profileName, !state.isDeleting else { return .none }
        state.isDeleting = true
        state.errorBanner = nil
        let connection = state.connection
        return .run { [profilesREST] send in
          do {
            try await profilesREST.delete(connection, name)
            await send(.deleteResponse(.success(name)))
          } catch let error as RESTError {
            await send(.deleteResponse(.failure(.init(message: error.message))))
          } catch {
            await send(.deleteResponse(.failure(.init(message: "Couldn’t delete the profile."))))
          }
        }

      case let .deleteResponse(.success(name)):
        state.isDeleting = false
        profileDraft.remove(state.connection.baseURL, name)
        return .send(.delegate(.deleted(name: name)))

      case let .deleteResponse(.failure(failure)):
        state.isDeleting = false
        state.errorBanner = failure.message
        return .none

      case .confirmationDialog(.presented(.discardAndClose)):
        profileDraft.remove(state.connection.baseURL, state.profileName)
        return .send(.delegate(.closed))

      case .confirmationDialog(.presented(.discardAndReload)):
        profileDraft.remove(state.connection.baseURL, state.profileName)
        state.recoveredDraft = nil
        return .send(.load)

      case .confirmationDialog:
        return .none

      case .delegate:
        return .none
      }
    }
    .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
  }

  private func persistDraft(for state: State) -> Effect<Action> {
    guard let original = state.original else { return .none }
    guard state.isDirty else {
      profileDraft.remove(state.connection.baseURL, state.profileName)
      return .none
    }
    let draft = ProfileEditorDraft(
      baseline: .init(values: original),
      edited: .init(values: state.currentValues),
      renameDraft: state.renameDraft,
      savedAt: now
    )
    if let data = try? JSONEncoder().encode(draft) {
      profileDraft.save(state.connection.baseURL, state.profileName, data)
    }
    return .none
  }
}

private extension ProfileEditorFeature {
  static func discardDialog(
    action: Action.Dialog
  ) -> ConfirmationDialogState<Action.Dialog> {
    ConfirmationDialogState {
      TextState("Discard unsaved changes?")
    } actions: {
      ButtonState(role: .destructive, action: action) { TextState("Discard Changes") }
      ButtonState(role: .cancel) { TextState("Keep Editing") }
    } message: {
      TextState("Your local recovery draft will also be removed.")
    }
  }

  static func configureRequest(
    name: String,
    original: Values,
    edited: Values
  ) -> ProfileConfigureRequest {
    ProfileConfigureRequest(
      name: name,
      description: original.description == edited.description ? nil : edited.description,
      soul: original.soul == edited.soul ? nil : edited.soul,
      model: original.provider == edited.provider && original.model == edited.model
        ? nil
        : ProfileModelConfiguration(provider: edited.provider, defaultModel: edited.model),
      reasoningEffort: original.reasoningEffort == edited.reasoningEffort
        ? nil : edited.reasoningEffort,
      disabledSkills: selectionChanged(original.skills, edited.skills)
        ? edited.skills.filter { !$0.enabled }.map(\.name).sorted() : nil,
      enabledToolsets: original.toolsets != edited.toolsets
          || original.toolsetsPinned != edited.toolsetsPinned
        ? (edited.toolsetsPinned ? edited.toolsets.filter(\.enabled).map(\.name).sorted() : [])
        : nil,
      enabledMCPServers: selectionChanged(original.mcpServers, edited.mcpServers)
        ? edited.mcpServers.filter(\.enabled).map(\.name).sorted() : nil
    )
  }

  static func selectionChanged(_ lhs: [ProfileSkill], _ rhs: [ProfileSkill]) -> Bool {
    lhs != rhs
  }

  static func selectionChanged(_ lhs: [ProfileMCPServer], _ rhs: [ProfileMCPServer]) -> Bool {
    lhs != rhs
  }

  static func restore(
    _ snapshot: ProfileEditorDraft.Snapshot,
    over server: Values
  ) -> Values {
    var result = server
    result.description = snapshot.description
    result.soul = snapshot.soul
    result.provider = snapshot.provider
    result.model = snapshot.model
    result.reasoningEffort = snapshot.reasoningEffort
    let skills = snapshot.skills.reduce(into: [String: Bool]()) { values, selection in
      values[selection.name] = selection.enabled
    }
    let toolsets = snapshot.toolsets.reduce(into: [String: Bool]()) { values, selection in
      values[selection.name] = selection.enabled
    }
    let mcp = snapshot.mcpServers.reduce(into: [String: Bool]()) { values, selection in
      values[selection.name] = selection.enabled
    }
    for index in result.skills.indices {
      result.skills[index].enabled = skills[result.skills[index].name] ?? result.skills[index].enabled
    }
    for index in result.toolsets.indices {
      result.toolsets[index].enabled = toolsets[result.toolsets[index].name]
        ?? result.toolsets[index].enabled
    }
    result.toolsetsPinned = snapshot.toolsetsPinned
    for index in result.mcpServers.indices {
      result.mcpServers[index].enabled = mcp[result.mcpServers[index].name]
        ?? result.mcpServers[index].enabled
    }
    return result
  }

  static func reconcile(
    state: inout State,
    result: ProfileConfigureResult,
    submission: Values,
    authoritative: Values?
  ) {
    var current = state.currentValues
    var baseline = authoritative ?? state.original ?? submission

    for section in result.requestedSections {
      guard result.status(for: section) == .applied else { continue }
      // A successful section is a valid baseline even if the follow-up describe failed.
      if authoritative == nil {
        set(section, in: &baseline, from: submission)
      }
      // Do not overwrite edits made while Save was in flight. Otherwise prefer the fresh
      // authoritative representation (normalization/default expansion included).
      if sectionEquals(section, current, submission) {
        set(section, in: &current, from: authoritative ?? submission)
      }
    }

    state.original = baseline
    state.currentValues = current
  }

  static func sectionEquals(_ section: ProfileConfigureSection, _ lhs: Values, _ rhs: Values) -> Bool {
    switch section {
    case .description: lhs.description == rhs.description
    case .soul: lhs.soul == rhs.soul
    case .model: lhs.provider == rhs.provider && lhs.model == rhs.model
    case .reasoningEffort: lhs.reasoningEffort == rhs.reasoningEffort
    case .skills: lhs.skills == rhs.skills
    case .toolsets: lhs.toolsets == rhs.toolsets && lhs.toolsetsPinned == rhs.toolsetsPinned
    case .mcpServers: lhs.mcpServers == rhs.mcpServers
    }
  }

  static func set(_ section: ProfileConfigureSection, in target: inout Values, from source: Values) {
    switch section {
    case .description: target.description = source.description
    case .soul: target.soul = source.soul
    case .model:
      target.provider = source.provider
      target.model = source.model
    case .reasoningEffort: target.reasoningEffort = source.reasoningEffort
    case .skills: target.skills = source.skills
    case .toolsets:
      target.toolsets = source.toolsets
      target.toolsetsPinned = source.toolsetsPinned
    case .mcpServers: target.mcpServers = source.mcpServers
    }
  }

  static func sectionOrder(_ lhs: ProfileConfigureSection, _ rhs: ProfileConfigureSection) -> Bool {
    let order = Dictionary(uniqueKeysWithValues: ProfileConfigureSection.allCases.enumerated().map {
      ($0.element, $0.offset)
    })
    return order[lhs, default: 0] < order[rhs, default: 0]
  }
}

public extension ProfileConfigureSection {
  var displayName: String {
    switch self {
    case .description: "Description"
    case .soul: "SOUL.md"
    case .model: "Model"
    case .reasoningEffort: "Reasoning effort"
    case .skills: "Skills"
    case .toolsets: "Toolsets"
    case .mcpServers: "MCP servers"
    }
  }
}
