import ComposableArchitecture
import Foundation

/// Profile-scoped capability browsing and selection.
///
/// Catalog reads are independent from the profile description: the catalog owns safe display
/// metadata, while `profiles.describe` owns the complete current selection. Edits stay in this
/// reducer until one explicit Save. The configure request then carries the complete replacement
/// selection for every changed section, including entries an older client does not recognize.
@Reducer
public struct CapabilityManagementFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    public var profileName: String
    public var hasActiveWorkflow: Bool
    public var selectedSegment: Segment
    public var searchQuery: String
    public var skills: [SkillRow]
    public var toolsets: [ToolsetRow]
    public var mcpServers: [MCPServerRow]
    public var profileLoadState: LoadState
    public var skillsLoadState: LoadState
    public var toolsetsLoadState: LoadState
    public var mcpLoadState: LoadState
    public var skillBrowseState: LoadState
    public var skillSearchState: LoadState
    public var reloadState: LoadState
    public var saveState: SaveState
    public var errorBanner: String?
    public var selectedDetail: CapabilityDetail?
    public var browsedSkillPage: Int
    public var browsedSkillTotalPages: Int
    @Presents public var confirmationDialog: ConfirmationDialogState<Action.Dialog>?

    /// Full server-authoritative selection, including rows absent from the safe catalog.
    var originalSelection: Selection?
    /// Locally edited selection. Catalog refreshes enrich rows but never replace this value.
    var selection: Selection?
    /// Browse/search include installable registry entries. Only names proven installed by
    /// `profiles.describe` or `skills.manage list` may enter the editable catalog.
    var installedSkillNames: Set<String>
    var skillSearchResultIDs: [String]?

    public init(
      connection: ServerConnection,
      profileName: String,
      hasActiveWorkflow: Bool = false,
      selectedSegment: Segment = .skills
    ) {
      self.connection = connection
      self.profileName = profileName
      self.hasActiveWorkflow = hasActiveWorkflow
      self.selectedSegment = selectedSegment
      searchQuery = ""
      skills = []
      toolsets = []
      mcpServers = []
      profileLoadState = .idle
      skillsLoadState = .idle
      toolsetsLoadState = .idle
      mcpLoadState = .idle
      skillBrowseState = .idle
      skillSearchState = .idle
      reloadState = .idle
      saveState = .idle
      errorBanner = nil
      selectedDetail = nil
      browsedSkillPage = 0
      browsedSkillTotalPages = 1
      confirmationDialog = nil
      originalSelection = nil
      selection = nil
      installedSkillNames = []
      skillSearchResultIDs = nil
    }

    public var loadState: LoadState {
      let sectionState: LoadState
      switch selectedSegment {
      case .skills: sectionState = skillsLoadState
      case .toolsets: sectionState = toolsetsLoadState
      case .mcpServers: sectionState = mcpLoadState
      }

      if case let .unsupported(message) = profileLoadState { return .unsupported(message) }
      if case let .unsupported(message) = sectionState { return .unsupported(message) }
      if case let .failed(message) = profileLoadState, totalCount == 0 { return .failed(message) }
      if case let .failed(message) = sectionState { return .failed(message) }
      if profileLoadState == .loading || sectionState == .loading { return .loading }
      if profileLoadState == .loaded, sectionState == .loaded { return .loaded }
      return .idle
    }

    public var totalCount: Int {
      switch selectedSegment {
      case .skills: skills.count
      case .toolsets: toolsets.count
      case .mcpServers: mcpServers.count
      }
    }

    public var filteredSkills: [SkillRow] {
      let trimmed = normalizedSearchQuery
      guard !trimmed.isEmpty else { return skills }
      if skillSearchState == .loaded, let ids = skillSearchResultIDs {
        let byID = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
      }
      return skills.filter { $0.searchText.localizedCaseInsensitiveContains(trimmed) }
    }

    public var filteredToolsets: [ToolsetRow] {
      guard !normalizedSearchQuery.isEmpty else { return toolsets }
      return toolsets.filter { $0.searchText.localizedCaseInsensitiveContains(normalizedSearchQuery) }
    }

    public var filteredMCPServers: [MCPServerRow] {
      guard !normalizedSearchQuery.isEmpty else { return mcpServers }
      return mcpServers.filter { $0.searchText.localizedCaseInsensitiveContains(normalizedSearchQuery) }
    }

    public var isDirty: Bool {
      guard let originalSelection, let selection else { return false }
      return originalSelection != selection
    }

    public var canSave: Bool {
      guard profileLoadState == .loaded, isDirty else { return false }
      if case .saving = saveState { return false }
      if case .unsupported = saveState { return false }
      return true
    }

    /// Conservative by design: Hermes does not currently report the exact toolsets captured by
    /// a running turn. If this profile has a live turn, warn for every enabled-to-disabled
    /// transition rather than claiming the active workflow is unaffected.
    public var activeWorkflowWarning: String? {
      guard hasActiveWorkflow else { return nil }
      let disabled = disabledToolsetNames
      guard !disabled.isEmpty else { return nil }
      let labels = disabled.compactMap { name in
        toolsets.first(where: { $0.name == name })?.title
      }
      let names = labels.isEmpty ? disabled : labels
      return "Disabling \(Self.joinedNames(names)) may affect work currently running with "
        + "\(profileName). Saving will not stop that work."
    }

    public var hasMoreBrowsedSkills: Bool {
      browsedSkillPage > 0 && browsedSkillPage < browsedSkillTotalPages
    }

    var normalizedSearchQuery: String {
      searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var disabledToolsetNames: [String] {
      guard let originalSelection, let selection else { return [] }
      return originalSelection.toolsets.compactMap { pair in
        pair.value && selection.toolsets[pair.key] == false ? pair.key : nil
      }.sorted()
    }

    private static func joinedNames(_ names: [String]) -> String {
      switch names.count {
      case 0: return "toolsets"
      case 1: return names[0]
      case 2: return "\(names[0]) and \(names[1])"
      default: return names.dropLast().joined(separator: ", ") + ", and \(names.last!)"
      }
    }
  }

  public enum Segment: String, CaseIterable, Equatable, Hashable, Sendable {
    case skills
    case toolsets
    case mcpServers
  }

  public enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
    case unsupported(String)
  }

  public enum SaveState: Equatable, Sendable {
    case idle
    case saving
    case saved(SaveReport)
    case partial(SaveReport)
    case failed(String)
    case unsupported(String)
  }

  public struct SaveReport: Equatable, Sendable {
    public var applied: [ProfileConfigureSection]
    public var failed: [ProfileConfigureSection]
    public var unreported: [ProfileConfigureSection]
    public var reloadErrors: [String]

    public init(
      applied: [ProfileConfigureSection] = [],
      failed: [ProfileConfigureSection] = [],
      unreported: [ProfileConfigureSection] = [],
      reloadErrors: [String] = []
    ) {
      self.applied = applied
      self.failed = failed
      self.unreported = unreported
      self.reloadErrors = reloadErrors
    }

    public var appliedNames: [String] { applied.map(\.displayName) }
    public var failedNames: [String] { (failed + unreported).map(\.displayName) }
  }

  public struct DetailID: Equatable, Hashable, Sendable {
    public var segment: Segment
    public var name: String

    public init(segment: Segment, name: String) {
      self.segment = segment
      self.name = name
    }
  }

  public struct SkillRow: Equatable, Sendable, Identifiable {
    public var name: String
    public var skillDescription: String
    public var documentation: String?
    public var source: String?
    public var category: String?
    public var identifier: String?
    public var tags: [String]
    public var enabled: Bool

    public var id: String { name }
    public var title: String { name }
    public var summary: String { skillDescription }
    public var detailID: DetailID { DetailID(segment: .skills, name: name) }
    var searchText: String { ([name, skillDescription] + tags).joined(separator: " ") }

    public init(
      name: String,
      skillDescription: String = "",
      documentation: String? = nil,
      source: String? = nil,
      category: String? = nil,
      identifier: String? = nil,
      tags: [String] = [],
      enabled: Bool
    ) {
      self.name = name
      self.skillDescription = skillDescription
      self.documentation = documentation
      self.source = source
      self.category = category
      self.identifier = identifier
      self.tags = tags
      self.enabled = enabled
    }
  }

  public struct ToolsetRow: Equatable, Sendable, Identifiable {
    public var name: String
    public var label: String
    public var toolsetDescription: String
    public var toolCount: Int
    public var enabled: Bool

    public var id: String { name }
    public var title: String { label.isEmpty ? name : label }
    public var summary: String { toolsetDescription }
    public var detailID: DetailID { DetailID(segment: .toolsets, name: name) }
    var searchText: String { [name, label, toolsetDescription].joined(separator: " ") }

    public init(
      name: String,
      label: String = "",
      toolsetDescription: String = "",
      toolCount: Int = 0,
      enabled: Bool
    ) {
      self.name = name
      self.label = label
      self.toolsetDescription = toolsetDescription
      self.toolCount = toolCount
      self.enabled = enabled
    }
  }

  public enum MCPHealth: Equatable, Sendable {
    case healthy(String)
    case warning(String)
    case unavailable(String)
    case unknown(String)
  }

  public struct MCPServerRow: Equatable, Sendable, Identifiable {
    public var name: String
    public var serverDescription: String
    public var transport: String
    public var tools: [String]
    public var toolCount: Int?
    public var health: MCPHealth?
    public var enabled: Bool

    public var id: String { name }
    public var title: String { name }
    public var summary: String { serverDescription }
    public var detailID: DetailID { DetailID(segment: .mcpServers, name: name) }
    var searchText: String {
      ([name, serverDescription, transport] + tools).joined(separator: " ")
    }

    public init(
      name: String,
      serverDescription: String = "",
      transport: String = "",
      tools: [String] = [],
      toolCount: Int? = nil,
      health: MCPHealth? = nil,
      enabled: Bool
    ) {
      self.name = name
      self.serverDescription = serverDescription
      self.transport = transport
      self.tools = tools
      self.toolCount = toolCount
      self.health = health
      self.enabled = enabled
    }
  }

  public enum CapabilityDetail: Equatable, Sendable, Identifiable {
    case skill(SkillRow)
    case toolset(ToolsetRow)
    case mcpServer(MCPServerRow)

    public var id: DetailID {
      switch self {
      case let .skill(row): row.detailID
      case let .toolset(row): row.detailID
      case let .mcpServer(row): row.detailID
      }
    }
  }

  public enum Action {
    case task
    case load
    case reloadTapped
    case reloadCatalog
    case reloadResponse(ReloadResponse)
    case profileResponse(ProfileResponse)
    case catalogResponse(CatalogResponse)
    case browseSkills(page: Int)
    case loadMoreSkills
    case skillBrowseResponse(page: Int, SkillBrowseResponse)
    case segmentSelected(Segment)
    case searchQueryChanged(String)
    case runSkillSearch(query: String)
    case skillSearchResponse(query: String, SkillSearchResponse)
    case detailTapped(DetailID)
    case detailDismissed
    case skillDetailResponse(DetailID, SkillDetailResponse)
    case setSkillEnabled(name: String, enabled: Bool)
    case setToolsetEnabled(name: String, enabled: Bool)
    case setMCPServerEnabled(name: String, enabled: Bool)
    case saveTapped
    case saveResponse(SaveResponse)
    case closeTapped
    case confirmationDialog(PresentationAction<Dialog>)
    case delegate(Delegate)

    @CasePathable
    public enum Dialog: Equatable, Sendable {
      case confirmSaveAfterToolsetWarning
      case discardAndClose
      case discardAndReload
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case closed
      case capabilitiesChanged(profileName: String)
    }
  }

  @CasePathable
  public enum ProfileResponse: Equatable, Sendable {
    case loaded(ProfileDescription)
    case unsupported(String)
    case failed(String)
  }

  @CasePathable
  public enum CatalogResponse: Equatable, Sendable {
    case loaded(CapabilityCatalog)
    case unsupported(String)
    case failed(String)
  }

  @CasePathable
  public enum ReloadResponse: Equatable, Sendable {
    case reloaded
    case unsupported(String)
    case failed(String)
  }

  @CasePathable
  public enum SkillBrowseResponse: Equatable, Sendable {
    case loaded(SkillCatalogPage)
    case unsupported(String)
    case failed(String)
  }

  @CasePathable
  public enum SkillSearchResponse: Equatable, Sendable {
    case loaded([SkillCatalogEntry])
    case unsupported(String)
    case failed(String)
  }

  @CasePathable
  public enum SkillDetailResponse: Equatable, Sendable {
    case loaded(SkillCatalogEntry)
    case unsupported(String)
    case failed(String)
  }

  @CasePathable
  public enum SaveResponse: Equatable, Sendable {
    case configured(
      result: ProfileConfigureResult,
      submission: Selection,
      authoritative: ProfileDescription?,
      catalog: CapabilityCatalog?,
      reloadErrors: [String]
    )
    case unsupported(String)
    case failed(String)
  }

  public struct Selection: Equatable, Sendable {
    public var skills: [String: Bool]
    public var toolsets: [String: Bool]
    public var toolsetsPinned: Bool
    public var mcpServers: [String: Bool]

    public init(
      skills: [String: Bool] = [:],
      toolsets: [String: Bool] = [:],
      toolsetsPinned: Bool = false,
      mcpServers: [String: Bool] = [:]
    ) {
      self.skills = skills
      self.toolsets = toolsets
      self.toolsetsPinned = toolsetsPinned
      self.mcpServers = mcpServers
    }

    init(_ description: ProfileDescription) {
      skills = Dictionary(uniqueKeysWithValues: description.skills.map { ($0.name, $0.enabled) })
      toolsets = Dictionary(
        uniqueKeysWithValues: description.toolsets.map { ($0.name, $0.enabled) }
      )
      toolsetsPinned = description.toolsetsPinned
      mcpServers = Dictionary(
        uniqueKeysWithValues: description.mcpServers.map { ($0.name, $0.enabled) }
      )
    }
  }

  @Dependency(\.hermesCapabilityCatalog) var catalog
  @Dependency(\.hermesProfileAdmin) var profileAdmin
  @Dependency(\.continuousClock) var clock

  private enum CancelID { case search }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        guard state.profileLoadState == .idle else { return .none }
        return .send(.load)

      case .load:
        state.profileLoadState = .loading
        state.skillsLoadState = .loading
        state.toolsetsLoadState = .loading
        state.mcpLoadState = .loading
        state.errorBanner = nil
        let connection = state.connection
        let profileName = state.profileName
        let scopedProfile = Self.scopedProfile(profileName)
        return .merge(
          .run { [profileAdmin] send in
            do {
              await send(.profileResponse(.loaded(
                try await profileAdmin.describe(connection, profileName)
              )))
            } catch let error as ProfileAdminError {
              await send(.profileResponse(
                error == .unsupported
                  ? .unsupported(error.message) : .failed(error.message)
              ))
            } catch {
              await send(.profileResponse(.failed("Couldn’t load the profile selection.")))
            }
          },
          .run { [catalog] send in
            do {
              let loaded = try await catalog.load(connection, scopedProfile)
              await send(.catalogResponse(.loaded(loaded)))
              await send(.browseSkills(page: 1))
            } catch let error as CapabilityCatalogError {
              await send(.catalogResponse(
                error == .unsupported
                  ? .unsupported(error.message) : .failed(error.message)
              ))
            } catch {
              await send(.catalogResponse(.failed("Couldn’t load the capability catalog.")))
            }
          }
        )

      case .reloadTapped:
        guard state.isDirty else { return .send(.reloadCatalog) }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Discard changes and reload?")
        } actions: {
          ButtonState(role: .destructive, action: .discardAndReload) {
            TextState("Discard and Reload")
          }
          ButtonState(role: .cancel) { TextState("Keep Editing") }
        } message: {
          TextState("Your unsaved capability choices will be replaced by the server state.")
        }
        return .none

      case .reloadCatalog:
        state.errorBanner = nil
        state.reloadState = .loading
        let connection = state.connection
        let scopedProfile = Self.scopedProfile(state.profileName)
        return .run { [catalog] send in
          do {
            _ = try await catalog.reload(connection, scopedProfile)
            await send(.reloadResponse(.reloaded))
          } catch let error as CapabilityCatalogError {
            if error == .unsupported {
              await send(.reloadResponse(.unsupported(error.message)))
            } else {
              await send(.reloadResponse(.failed(error.message)))
            }
          } catch {
            await send(.reloadResponse(.failed("Couldn’t reload the capability catalog.")))
          }
        }

      case .reloadResponse(.reloaded):
        state.reloadState = .loaded
        state.originalSelection = nil
        state.selection = nil
        state.installedSkillNames = []
        state.skills = []
        state.toolsets = []
        state.mcpServers = []
        state.profileLoadState = .idle
        state.skillsLoadState = .idle
        state.toolsetsLoadState = .idle
        state.mcpLoadState = .idle
        state.skillBrowseState = .idle
        state.skillSearchState = .idle
        state.skillSearchResultIDs = nil
        state.browsedSkillPage = 0
        state.browsedSkillTotalPages = 1
        state.saveState = .idle
        return .send(.load)

      case let .reloadResponse(.unsupported(message)):
        // `skills.reload` is an optional refresh operation. Its absence does not withdraw
        // catalog browsing or profile configure, and stale-but-valid rows remain visible.
        state.reloadState = .unsupported(message)
        state.errorBanner = message
        return .none

      case let .reloadResponse(.failed(message)):
        state.reloadState = .failed(message)
        state.errorBanner = message
        return .none

      case let .profileResponse(.loaded(description)):
        guard description.name == state.profileName else {
          let message = "Hermes returned a different profile than requested."
          state.profileLoadState = .failed(message)
          state.errorBanner = message
          return .none
        }
        let selection = Selection(description)
        state.originalSelection = selection
        state.selection = selection
        state.installedSkillNames.formUnion(description.skills.map(\.name))
        state.profileLoadState = .loaded
        state.saveState = .idle
        Self.mergeProfileMetadata(description, into: &state)
        Self.applySelection(to: &state)
        return .none

      case let .profileResponse(.unsupported(message)):
        state.profileLoadState = .unsupported(message)
        state.saveState = .unsupported(message)
        state.errorBanner = message
        return .none

      case let .profileResponse(.failed(message)):
        state.profileLoadState = .failed(message)
        state.errorBanner = message
        return .none

      case let .catalogResponse(.loaded(loaded)):
        state.skillsLoadState = .loaded
        state.toolsetsLoadState = .loaded
        state.mcpLoadState = .loaded
        state.installedSkillNames.formUnion(loaded.skills.map(\.name))
        Self.merge(loaded, into: &state, extendSelection: state.originalSelection != nil)
        if state.profileLoadState == .loaded { state.errorBanner = nil }
        return .none

      case let .catalogResponse(.unsupported(message)):
        state.skillsLoadState = .unsupported(message)
        state.toolsetsLoadState = .unsupported(message)
        state.mcpLoadState = .unsupported(message)
        state.errorBanner = message
        return .none

      case let .catalogResponse(.failed(message)):
        state.skillsLoadState = .failed(message)
        state.toolsetsLoadState = .failed(message)
        state.mcpLoadState = .failed(message)
        state.errorBanner = message
        return .none

      case let .browseSkills(page):
        guard page > 0, state.skillBrowseState != .loading else { return .none }
        state.skillBrowseState = .loading
        let connection = state.connection
        let request = SkillCatalogBrowseRequest(
          profile: Self.scopedProfile(state.profileName), page: page
        )
        return .run { [catalog] send in
          do {
            await send(.skillBrowseResponse(
              page: page, .loaded(try await catalog.browseSkills(connection, request))
            ))
          } catch let error as CapabilityCatalogError {
            await send(.skillBrowseResponse(
              page: page,
              error == .unsupported ? .unsupported(error.message) : .failed(error.message)
            ))
          } catch {
            await send(.skillBrowseResponse(
              page: page, .failed("Couldn’t browse installed skills.")
            ))
          }
        }

      case .loadMoreSkills:
        guard state.hasMoreBrowsedSkills else { return .none }
        return .send(.browseSkills(page: state.browsedSkillPage + 1))

      case let .skillBrowseResponse(page, .loaded(result)):
        guard page == result.page else { return .none }
        state.skillBrowseState = .loaded
        state.browsedSkillPage = result.page
        state.browsedSkillTotalPages = max(result.page, result.totalPages)
        Self.mergeSkills(
          result.entries.filter { state.installedSkillNames.contains($0.name) },
          into: &state,
          extendSelection: false
        )
        return .none

      case let .skillBrowseResponse(_, .unsupported(message)):
        state.skillBrowseState = .unsupported(message)
        return .none

      case let .skillBrowseResponse(_, .failed(message)):
        state.skillBrowseState = .failed(message)
        state.errorBanner = message
        return .none

      case let .segmentSelected(segment):
        state.selectedSegment = segment
        state.selectedDetail = nil
        if segment == .skills, !state.normalizedSearchQuery.isEmpty {
          return .send(.runSkillSearch(query: state.normalizedSearchQuery))
        }
        return .cancel(id: CancelID.search)

      case let .searchQueryChanged(query):
        state.searchQuery = query
        state.selectedDetail = nil
        state.skillSearchResultIDs = nil
        state.skillSearchState = .idle
        guard state.selectedSegment == .skills, !state.normalizedSearchQuery.isEmpty else {
          return .cancel(id: CancelID.search)
        }
        let normalized = state.normalizedSearchQuery
        return .run { [clock] send in
          try await clock.sleep(for: .milliseconds(250))
          await send(.runSkillSearch(query: normalized))
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)

      case let .runSkillSearch(query):
        guard state.selectedSegment == .skills, query == state.normalizedSearchQuery,
              !query.isEmpty else { return .none }
        state.skillSearchState = .loading
        let connection = state.connection
        let request = SkillCatalogSearchRequest(
          query: query, profile: Self.scopedProfile(state.profileName)
        )
        return .run { [catalog] send in
          do {
            await send(.skillSearchResponse(
              query: query, .loaded(try await catalog.searchSkills(connection, request))
            ))
          } catch let error as CapabilityCatalogError {
            await send(.skillSearchResponse(
              query: query,
              error == .unsupported ? .unsupported(error.message) : .failed(error.message)
            ))
          } catch {
            await send(.skillSearchResponse(query: query, .failed("Couldn’t search skills.")))
          }
        }

      case let .skillSearchResponse(query, .loaded(entries)):
        guard query == state.normalizedSearchQuery else { return .none }
        state.skillSearchState = .loaded
        let installed = entries.filter { state.installedSkillNames.contains($0.name) }
        Self.mergeSkills(installed, into: &state, extendSelection: false)
        let localMatches = state.skills.filter {
          $0.searchText.localizedCaseInsensitiveContains(query)
        }.map(\.name)
        state.skillSearchResultIDs = Self.orderedUnique(installed.map(\.name) + localMatches)
        return .none

      case let .skillSearchResponse(query, .unsupported(message)):
        guard query == state.normalizedSearchQuery else { return .none }
        state.skillSearchState = .unsupported(message)
        // Search is an enhancement over the already-loaded installed list. Keep the local
        // filter usable rather than capability-gating all skill management.
        state.skillSearchResultIDs = nil
        return .none

      case let .skillSearchResponse(query, .failed(message)):
        guard query == state.normalizedSearchQuery else { return .none }
        state.skillSearchState = .failed(message)
        state.skillSearchResultIDs = nil
        state.errorBanner = message
        return .none

      case let .detailTapped(id):
        guard let detail = Self.detail(id, in: state) else { return .none }
        state.selectedDetail = detail
        guard case let .skill(row) = detail else { return .none }
        let connection = state.connection
        let request = SkillCatalogInspectRequest(
          identifier: row.identifier ?? row.name,
          profile: Self.scopedProfile(state.profileName)
        )
        return .run { [catalog] send in
          do {
            await send(.skillDetailResponse(
              id, .loaded(try await catalog.inspectSkill(connection, request))
            ))
          } catch let error as CapabilityCatalogError {
            await send(.skillDetailResponse(
              id, error == .unsupported ? .unsupported(error.message) : .failed(error.message)
            ))
          } catch {
            await send(.skillDetailResponse(id, .failed("Couldn’t load skill details.")))
          }
        }

      case .detailDismissed:
        state.selectedDetail = nil
        return .none

      case let .skillDetailResponse(id, .loaded(entry)):
        guard state.installedSkillNames.contains(entry.name) else { return .none }
        Self.mergeSkills([entry], into: &state, extendSelection: false)
        if state.selectedDetail?.id == id {
          state.selectedDetail = Self.detail(id, in: state)
        }
        return .none

      case let .skillDetailResponse(id, .unsupported(message)),
           let .skillDetailResponse(id, .failed(message)):
        guard state.selectedDetail?.id == id else { return .none }
        state.errorBanner = message
        return .none

      case let .setSkillEnabled(name, enabled):
        guard state.profileLoadState == .loaded,
              let index = state.skills.firstIndex(where: { $0.name == name }),
              state.selection?.skills[name] != enabled else { return .none }
        state.skills[index].enabled = enabled
        state.selection?.skills[name] = enabled
        Self.refreshSelectedDetail(in: &state)
        state.saveState = .idle
        return .none

      case let .setToolsetEnabled(name, enabled):
        guard state.profileLoadState == .loaded,
              let index = state.toolsets.firstIndex(where: { $0.name == name }),
              state.selection?.toolsets[name] != enabled else { return .none }
        state.toolsets[index].enabled = enabled
        state.selection?.toolsets[name] = enabled
        if var selection = state.selection {
          selection.toolsetsPinned = selection.toolsets.values.contains(true)
          state.selection = selection
        }
        Self.refreshSelectedDetail(in: &state)
        state.saveState = .idle
        return .none

      case let .setMCPServerEnabled(name, enabled):
        guard state.profileLoadState == .loaded,
              let index = state.mcpServers.firstIndex(where: { $0.name == name }),
              state.selection?.mcpServers[name] != enabled else { return .none }
        state.mcpServers[index].enabled = enabled
        state.selection?.mcpServers[name] = enabled
        Self.refreshSelectedDetail(in: &state)
        state.saveState = .idle
        return .none

      case .saveTapped:
        guard state.canSave else { return .none }
        if let warning = state.activeWorkflowWarning {
          state.confirmationDialog = ConfirmationDialogState {
            TextState("Save toolset changes?")
          } actions: {
            ButtonState(action: .confirmSaveAfterToolsetWarning) { TextState("Save Changes") }
            ButtonState(role: .cancel) { TextState("Cancel") }
          } message: {
            TextState(warning)
          }
          return .none
        }
        return startSave(&state)

      case let .saveResponse(.configured(result, submission, authoritative, loadedCatalog, errors)):
        let report = SaveReport(
          applied: result.appliedSections.sorted(by: Self.sectionOrder),
          failed: result.failedSections.sorted(by: Self.sectionOrder),
          unreported: result.unreportedSections.sorted(by: Self.sectionOrder),
          reloadErrors: errors
        )
        Self.reconcile(
          state: &state,
          result: result,
          submission: submission,
          authoritative: authoritative.map(Selection.init)
        )
        if let authoritative {
          Self.mergeProfileMetadata(authoritative, into: &state)
          Self.applySelection(to: &state)
        }
        if let loadedCatalog {
          Self.merge(loadedCatalog, into: &state, extendSelection: false)
          state.skillsLoadState = .loaded
          state.toolsetsLoadState = .loaded
          state.mcpLoadState = .loaded
        }
        state.saveState = result.isCompleteSuccess ? .saved(report) : .partial(report)
        state.errorBanner = errors.first
        let changed = !result.appliedSections.isEmpty
        return changed
          ? .send(.delegate(.capabilitiesChanged(profileName: state.profileName))) : .none

      case let .saveResponse(.unsupported(message)):
        state.saveState = .unsupported(message)
        state.errorBanner = message
        return .none

      case let .saveResponse(.failed(message)):
        state.saveState = .failed(message)
        state.errorBanner = message
        return .none

      case .closeTapped:
        guard state.isDirty else { return .send(.delegate(.closed)) }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Discard unsaved changes?")
        } actions: {
          ButtonState(role: .destructive, action: .discardAndClose) {
            TextState("Discard Changes")
          }
          ButtonState(role: .cancel) { TextState("Keep Editing") }
        } message: {
          TextState("Capability changes are local until you save them.")
        }
        return .none

      case .confirmationDialog(.presented(.confirmSaveAfterToolsetWarning)):
        return startSave(&state)

      case .confirmationDialog(.presented(.discardAndClose)):
        return .send(.delegate(.closed))

      case .confirmationDialog(.presented(.discardAndReload)):
        return .send(.reloadCatalog)

      case .confirmationDialog(.dismiss):
        state.confirmationDialog = nil
        return .none

      case .confirmationDialog, .delegate:
        return .none
      }
    }
  }

  private func startSave(_ state: inout State) -> Effect<Action> {
    guard state.canSave, let original = state.originalSelection,
          let submission = state.selection else { return .none }
    let request = Self.configureRequest(
      name: state.profileName, original: original, edited: submission
    )
    guard !request.requestedSections.isEmpty else { return .none }
    state.saveState = .saving
    state.errorBanner = nil
    let connection = state.connection
    let profileName = state.profileName
    let scopedProfile = Self.scopedProfile(profileName)
    return .run { [profileAdmin, catalog] send in
      do {
        let result = try await profileAdmin.configure(connection, request)
        async let described = Self.reloadDescription(
          profileAdmin: profileAdmin, connection: connection, profileName: profileName
        )
        async let cataloged = Self.reloadCatalog(
          catalog: catalog, connection: connection, profileName: scopedProfile
        )
        let (descriptionResult, catalogResult) = await (described, cataloged)
        var errors: [String] = []
        let authoritative: ProfileDescription?
        switch descriptionResult {
        case let .success(description): authoritative = description
        case let .failure(message):
          authoritative = nil
          errors.append(message)
        }
        let loadedCatalog: CapabilityCatalog?
        switch catalogResult {
        case let .success(value): loadedCatalog = value
        case let .failure(message):
          loadedCatalog = nil
          errors.append(message)
        }
        await send(.saveResponse(.configured(
          result: result,
          submission: submission,
          authoritative: authoritative,
          catalog: loadedCatalog,
          reloadErrors: errors
        )))
      } catch let error as ProfileAdminError {
        await send(.saveResponse(
          error == .unsupported
            ? .unsupported(error.message) : .failed(error.message)
        ))
      } catch {
        await send(.saveResponse(.failed("Couldn’t save capabilities.")))
      }
    }
  }
}

private extension CapabilityManagementFeature {
  enum ReloadResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
  }

  static func reloadDescription(
    profileAdmin: HermesProfileAdminClient,
    connection: ServerConnection,
    profileName: String
  ) async -> ReloadResult<ProfileDescription> {
    do {
      let description = try await profileAdmin.describe(connection, profileName)
      guard description.name == profileName else {
        return .failure("Hermes returned a different profile while reloading.")
      }
      return .success(description)
    } catch let error as ProfileAdminError {
      return .failure(error.message)
    } catch {
      return .failure("The saved profile selection could not be reloaded.")
    }
  }

  static func reloadCatalog(
    catalog: HermesCapabilityCatalogClient,
    connection: ServerConnection,
    profileName: String?
  ) async -> ReloadResult<CapabilityCatalog> {
    do {
      return .success(try await catalog.load(connection, profileName))
    } catch let error as CapabilityCatalogError {
      return .failure(error.message)
    } catch {
      return .failure("The capability catalog could not be reloaded.")
    }
  }

  static func scopedProfile(_ profileName: String) -> String? {
    profileName == SessionListFeature.State.defaultProfileName ? nil : profileName
  }

  static func configureRequest(
    name: String,
    original: Selection,
    edited: Selection
  ) -> ProfileConfigureRequest {
    ProfileConfigureRequest(
      name: name,
      disabledSkills: original.skills == edited.skills
        ? nil : edited.skills.compactMap { $0.value ? nil : $0.key }.sorted(),
      enabledToolsets: original.toolsets == edited.toolsets
          && original.toolsetsPinned == edited.toolsetsPinned
        ? nil
        : (edited.toolsetsPinned
          ? edited.toolsets.compactMap { $0.value ? $0.key : nil }.sorted() : []),
      enabledMCPServers: original.mcpServers == edited.mcpServers
        ? nil : edited.mcpServers.compactMap { $0.value ? $0.key : nil }.sorted()
    )
  }

  static func applySelection(to state: inout State) {
    guard let selection = state.selection else { return }
    for index in state.skills.indices {
      if let enabled = selection.skills[state.skills[index].name] {
        state.skills[index].enabled = enabled
      }
    }
    for index in state.toolsets.indices {
      if let enabled = selection.toolsets[state.toolsets[index].name] {
        state.toolsets[index].enabled = enabled
      }
    }
    for index in state.mcpServers.indices {
      if let enabled = selection.mcpServers[state.mcpServers[index].name] {
        state.mcpServers[index].enabled = enabled
      }
    }

    for pair in selection.skills where !state.skills.contains(where: { $0.name == pair.key }) {
      state.skills.append(SkillRow(name: pair.key, enabled: pair.value))
    }
    for pair in selection.toolsets where !state.toolsets.contains(where: { $0.name == pair.key }) {
      state.toolsets.append(ToolsetRow(name: pair.key, label: pair.key, enabled: pair.value))
    }
    for pair in selection.mcpServers where !state.mcpServers.contains(where: { $0.name == pair.key }) {
      state.mcpServers.append(MCPServerRow(name: pair.key, enabled: pair.value))
    }
    sortRows(&state)
    refreshSelectedDetail(in: &state)
  }

  static func merge(
    _ catalog: CapabilityCatalog,
    into state: inout State,
    extendSelection: Bool
  ) {
    mergeSkills(catalog.skills, into: &state, extendSelection: extendSelection)
    for entry in catalog.toolsets {
      let enabled = state.selection?.toolsets[entry.name] ?? entry.enabled
      let existing = state.toolsets.first(where: { $0.name == entry.name })
      let row = ToolsetRow(
        name: entry.name,
        label: entry.label == entry.name && existing?.label.isEmpty == false
          ? existing?.label ?? entry.label : entry.label,
        toolsetDescription: entry.toolsetDescription.isEmpty
          ? existing?.toolsetDescription ?? "" : entry.toolsetDescription,
        toolCount: entry.toolCount > 0 ? entry.toolCount : existing?.toolCount ?? 0,
        enabled: enabled
      )
      upsert(row, in: &state.toolsets)
      if extendSelection { extendToolsetSelection(name: entry.name, enabled: enabled, state: &state) }
    }
    for entry in catalog.mcpServers {
      let enabled = state.selection?.mcpServers[entry.name] ?? entry.enabled
      let existing = state.mcpServers.first(where: { $0.name == entry.name })
      let tools = entry.tools.isEmpty ? existing?.tools ?? [] : entry.tools.map(\.name)
      let row = MCPServerRow(
        name: entry.name,
        serverDescription: entry.description.isEmpty
          ? existing?.serverDescription ?? "" : entry.description,
        transport: entry.transport.isEmpty ? existing?.transport ?? "" : entry.transport,
        tools: tools,
        toolCount: entry.reportedToolCount
          ?? (entry.tools.isEmpty ? existing?.toolCount : entry.tools.count),
        health: health(entry.health) ?? existing?.health,
        enabled: enabled
      )
      upsert(row, in: &state.mcpServers)
      if extendSelection { extendMCPSelection(name: entry.name, enabled: enabled, state: &state) }
    }
    applySelection(to: &state)
  }

  static func mergeSkills(
    _ entries: [SkillCatalogEntry],
    into state: inout State,
    extendSelection: Bool
  ) {
    for entry in entries {
      let enabled = state.selection?.skills[entry.name] ?? entry.enabled ?? false
      let existing = state.skills.first(where: { $0.name == entry.name })
      let row = SkillRow(
        name: entry.name,
        skillDescription: entry.description.isEmpty
          ? existing?.skillDescription ?? "" : entry.description,
        documentation: entry.documentation ?? existing?.documentation,
        source: entry.source ?? existing?.source,
        category: entry.category ?? existing?.category,
        identifier: entry.identifier ?? existing?.identifier,
        tags: entry.tags.isEmpty ? existing?.tags ?? [] : entry.tags,
        enabled: enabled
      )
      upsert(row, in: &state.skills)
      if extendSelection { extendSkillSelection(name: entry.name, enabled: enabled, state: &state) }
    }
    applySelection(to: &state)
  }

  static func mergeProfileMetadata(_ description: ProfileDescription, into state: inout State) {
    for entry in description.skills {
      guard !state.skills.contains(where: { $0.name == entry.name }) else { continue }
      state.skills.append(SkillRow(name: entry.name, enabled: entry.enabled))
    }
    for entry in description.toolsets {
      let existing = state.toolsets.first(where: { $0.name == entry.name })
      upsert(
        ToolsetRow(
          name: entry.name,
          label: entry.label,
          toolsetDescription: existing?.toolsetDescription.isEmpty == false
            ? existing?.toolsetDescription ?? entry.toolsetDescription
            : entry.toolsetDescription,
          toolCount: existing?.toolCount ?? entry.toolCount,
          enabled: entry.enabled
        ),
        in: &state.toolsets
      )
    }
    for entry in description.mcpServers {
      let existing = state.mcpServers.first(where: { $0.name == entry.name })
      upsert(
        MCPServerRow(
          name: entry.name,
          serverDescription: existing?.serverDescription ?? "",
          transport: entry.transport.isEmpty ? existing?.transport ?? "" : entry.transport,
          tools: existing?.tools ?? [],
          toolCount: existing?.toolCount,
          health: existing?.health,
          enabled: entry.enabled
        ),
        in: &state.mcpServers
      )
    }
    sortRows(&state)
  }

  static func extendSkillSelection(name: String, enabled: Bool, state: inout State) {
    guard state.selection?.skills[name] == nil else { return }
    state.selection?.skills[name] = enabled
    state.originalSelection?.skills[name] = enabled
  }

  static func extendToolsetSelection(name: String, enabled: Bool, state: inout State) {
    guard state.selection?.toolsets[name] == nil else { return }
    state.selection?.toolsets[name] = enabled
    state.originalSelection?.toolsets[name] = enabled
  }

  static func extendMCPSelection(name: String, enabled: Bool, state: inout State) {
    guard state.selection?.mcpServers[name] == nil else { return }
    state.selection?.mcpServers[name] = enabled
    state.originalSelection?.mcpServers[name] = enabled
  }

  static func upsert(_ row: SkillRow, in rows: inout [SkillRow]) {
    if let index = rows.firstIndex(where: { $0.name == row.name }) { rows[index] = row }
    else { rows.append(row) }
  }

  static func upsert(_ row: ToolsetRow, in rows: inout [ToolsetRow]) {
    if let index = rows.firstIndex(where: { $0.name == row.name }) { rows[index] = row }
    else { rows.append(row) }
  }

  static func upsert(_ row: MCPServerRow, in rows: inout [MCPServerRow]) {
    if let index = rows.firstIndex(where: { $0.name == row.name }) { rows[index] = row }
    else { rows.append(row) }
  }

  static func sortRows(_ state: inout State) {
    state.skills.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    state.toolsets.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    state.mcpServers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  static func orderedUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
  }

  static func health(_ value: MCPServerHealth) -> MCPHealth? {
    switch value {
    case .unknown: nil
    case .configured: .unknown("Configured")
    case .connecting: .warning("Connecting")
    case .connected: .healthy("Connected")
    case .disabled: .unavailable("Disabled")
    case .failed: .unavailable("Unavailable")
    }
  }

  static func detail(_ id: DetailID, in state: State) -> CapabilityDetail? {
    switch id.segment {
    case .skills: state.skills.first(where: { $0.name == id.name }).map(CapabilityDetail.skill)
    case .toolsets:
      state.toolsets.first(where: { $0.name == id.name }).map(CapabilityDetail.toolset)
    case .mcpServers:
      state.mcpServers.first(where: { $0.name == id.name }).map(CapabilityDetail.mcpServer)
    }
  }

  static func refreshSelectedDetail(in state: inout State) {
    guard let id = state.selectedDetail?.id else { return }
    state.selectedDetail = detail(id, in: state)
  }

  static func reconcile(
    state: inout State,
    result: ProfileConfigureResult,
    submission: Selection,
    authoritative: Selection?
  ) {
    var current = state.selection ?? submission
    var baseline = authoritative ?? state.originalSelection ?? submission
    for section in result.requestedSections {
      guard result.status(for: section) == .applied else { continue }
      if authoritative == nil { set(section, in: &baseline, from: submission) }
      if sectionEquals(section, current, submission) {
        set(section, in: &current, from: authoritative ?? submission)
      }
    }
    state.originalSelection = baseline
    state.selection = current
    applySelection(to: &state)
  }

  static func sectionEquals(_ section: ProfileConfigureSection, _ a: Selection, _ b: Selection) -> Bool {
    switch section {
    case .skills: a.skills == b.skills
    case .toolsets: a.toolsets == b.toolsets && a.toolsetsPinned == b.toolsetsPinned
    case .mcpServers: a.mcpServers == b.mcpServers
    case .description, .soul, .model, .reasoningEffort: true
    }
  }

  static func set(_ section: ProfileConfigureSection, in target: inout Selection, from source: Selection) {
    switch section {
    case .skills: target.skills = source.skills
    case .toolsets:
      target.toolsets = source.toolsets
      target.toolsetsPinned = source.toolsetsPinned
    case .mcpServers: target.mcpServers = source.mcpServers
    case .description, .soul, .model, .reasoningEffort: break
    }
  }

  static func sectionOrder(_ lhs: ProfileConfigureSection, _ rhs: ProfileConfigureSection) -> Bool {
    let order: [ProfileConfigureSection: Int] = [
      .skills: 0, .toolsets: 1, .mcpServers: 2,
    ]
    return order[lhs, default: 100] < order[rhs, default: 100]
  }
}
