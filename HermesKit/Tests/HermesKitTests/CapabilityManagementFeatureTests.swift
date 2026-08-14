import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct CapabilityManagementFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "https://agent.example")!, token: "tok"
  )

  private var described: ProfileDescription {
    ProfileDescription(
      name: "ios-release",
      skills: [
        .init(name: "docs", enabled: true),
        .init(name: "legacy-disabled", enabled: false),
      ],
      toolsets: [
        .init(name: "coding", label: "Coding", enabled: true),
        .init(name: "web", label: "Web", enabled: false),
        .init(name: "legacy-toolset", label: "Legacy", enabled: true),
      ],
      toolsetsPinned: true,
      mcpServers: [
        .init(name: "github", enabled: true, transport: "http"),
        .init(name: "sentry", enabled: false, transport: "stdio"),
        .init(name: "legacy-mcp", enabled: true),
      ]
    )
  }

  private var catalog: CapabilityCatalog {
    CapabilityCatalog(
      skills: [
        .init(
          name: "docs",
          description: "Official documentation",
          documentation: "https://example.invalid/docs",
          source: "bundled",
          category: "documentation",
          identifier: "bundled/docs",
          enabled: true,
          tags: ["reference"]
        ),
      ],
      toolsets: [
        .init(name: "coding", label: "Coding", toolsetDescription: "Code tools", toolCount: 8),
        .init(name: "web", label: "Web", toolsetDescription: "Web tools", toolCount: 4, enabled: false),
      ],
      mcpServers: [
        .init(
          name: "github",
          description: "Repository tools",
          enabled: true,
          transport: "http",
          tools: [.init(name: "list_pull_requests")],
          health: .connected
        ),
        .init(name: "sentry", description: "Issue tools", enabled: false, transport: "stdio"),
      ]
    )
  }

  @Test func profileSelectionAndSafeCatalogMergeWithoutDroppingUnknownEntries() async {
    let store = TestStore(initialState: initialState()) { CapabilityManagementFeature() }
    store.exhaustivity = .off

    await store.send(.profileResponse(.loaded(described))) {
      $0.originalSelection = .init(self.described)
      $0.selection = .init(self.described)
      $0.profileLoadState = .loaded
      $0.saveState = .idle
      $0.skills = [
        .init(name: "docs", enabled: true),
        .init(name: "legacy-disabled", enabled: false),
      ]
      $0.toolsets = [
        .init(name: "coding", label: "Coding", enabled: true),
        .init(name: "legacy-toolset", label: "Legacy", enabled: true),
        .init(name: "web", label: "Web", enabled: false),
      ]
      $0.mcpServers = [
        .init(name: "github", transport: "http", enabled: true),
        .init(name: "legacy-mcp", enabled: true),
        .init(name: "sentry", transport: "stdio", enabled: false),
      ]
    }

    await store.send(.catalogResponse(.loaded(catalog)))

    #expect(store.state.skills.first(where: { $0.name == "docs" })?.documentation == "https://example.invalid/docs")
    #expect(store.state.toolsets.first(where: { $0.name == "coding" })?.toolCount == 8)
    #expect(store.state.mcpServers.first(where: { $0.name == "github" })?.tools == ["list_pull_requests"])
    #expect(store.state.mcpServers.first(where: { $0.name == "github" })?.health == .healthy("Connected"))
    #expect(store.state.skills.contains { $0.name == "legacy-disabled" })
    #expect(store.state.toolsets.contains { $0.name == "legacy-toolset" })
    #expect(store.state.mcpServers.contains { $0.name == "legacy-mcp" })
    #expect(!store.state.isDirty)
  }

  @Test func localEditsWaitForSaveUseReplaceSemanticsAndReportPartialFailure() async {
    let configureCalls = LockIsolated<[ProfileConfigureRequest]>([])
    let authoritative: ProfileDescription = {
      var value = described
      value.skills[0].enabled = false
      value.mcpServers[1].enabled = true
      return value
    }()
    let loadedCatalog = catalog

    let store = TestStore(initialState: loadedState()) { CapabilityManagementFeature() } withDependencies: {
      $0.hermesProfileAdmin.configure = { @Sendable _, request in
        configureCalls.withValue { $0.append(request) }
        return ProfileConfigureResult(
          ok: false,
          requestedSections: request.requestedSections,
          sectionStatuses: [
            .skills: .applied,
            .toolsets: .failed,
            .mcpServers: .applied,
          ]
        )
      }
      $0.hermesProfileAdmin.describe = { @Sendable _, _ in authoritative }
      $0.hermesCapabilityCatalog.load = { @Sendable _, _ in loadedCatalog }
    }
    store.exhaustivity = .off

    await store.send(.setSkillEnabled(name: "docs", enabled: false))
    await store.send(.setToolsetEnabled(name: "web", enabled: true))
    await store.send(.setMCPServerEnabled(name: "sentry", enabled: true))
    #expect(configureCalls.value.isEmpty)

    await store.send(.saveTapped)
    await store.receive(\.saveResponse.configured)
    await store.receive(\.delegate.capabilitiesChanged)

    let request = try #require(configureCalls.value.first)
    #expect(request.disabledSkills == ["docs", "legacy-disabled"])
    #expect(request.enabledToolsets == ["coding", "legacy-toolset", "web"])
    #expect(request.enabledMCPServers == ["github", "legacy-mcp", "sentry"])
    guard case let .partial(report) = store.state.saveState else {
      Issue.record("Expected a section-accurate partial result")
      return
    }
    #expect(report.applied == [.skills, .mcpServers])
    #expect(report.failed == [.toolsets])
    #expect(store.state.selection?.toolsets["web"] == true)
    #expect(store.state.originalSelection?.toolsets["web"] == false)
    #expect(store.state.selection?.toolsets["legacy-toolset"] == true)
    #expect(store.state.selection?.mcpServers["legacy-mcp"] == true)
    #expect(store.state.isDirty)
  }

  @Test func activeWorkflowRequiresConfirmationBeforeDisablingToolset() async {
    let configureCalls = LockIsolated(0)
    var state = loadedState()
    state.hasActiveWorkflow = true
    let described = self.described
    let loadedCatalog = catalog
    let store = TestStore(initialState: state) { CapabilityManagementFeature() } withDependencies: {
      $0.hermesProfileAdmin.configure = { @Sendable _, request in
        configureCalls.withValue { $0 += 1 }
        return ProfileConfigureResult(
          ok: true,
          requestedSections: request.requestedSections,
          sectionStatuses: [.toolsets: .applied]
        )
      }
      $0.hermesProfileAdmin.describe = { @Sendable _, _ in
        var value = described
        value.toolsets[0].enabled = false
        return value
      }
      $0.hermesCapabilityCatalog.load = { @Sendable _, _ in loadedCatalog }
    }
    store.exhaustivity = .off

    await store.send(.setToolsetEnabled(name: "coding", enabled: false))
    #expect(store.state.activeWorkflowWarning?.contains("Coding") == true)
    await store.send(.saveTapped)
    #expect(configureCalls.value == 0)
    #expect(store.state.confirmationDialog != nil)

    await store.send(.confirmationDialog(.presented(.confirmSaveAfterToolsetWarning)))
    await store.receive(\.saveResponse.configured)
    #expect(configureCalls.value == 1)
  }

  @Test func onlyAuthoritativeUnsupportedErrorsGateCatalog() async {
    let unsupported = TestStore(initialState: initialState()) { CapabilityManagementFeature() }
    await unsupported.send(.catalogResponse(.unsupported(CapabilityCatalogError.unsupported.message))) {
      $0.skillsLoadState = .unsupported(CapabilityCatalogError.unsupported.message)
      $0.toolsetsLoadState = .unsupported(CapabilityCatalogError.unsupported.message)
      $0.mcpLoadState = .unsupported(CapabilityCatalogError.unsupported.message)
      $0.errorBanner = CapabilityCatalogError.unsupported.message
    }
    #expect(unsupported.state.loadState == .unsupported(CapabilityCatalogError.unsupported.message))

    let transient = TestStore(initialState: initialState()) { CapabilityManagementFeature() }
    await transient.send(.catalogResponse(.failed("request timed out: toolsets.list"))) {
      $0.skillsLoadState = .failed("request timed out: toolsets.list")
      $0.toolsetsLoadState = .failed("request timed out: toolsets.list")
      $0.mcpLoadState = .failed("request timed out: toolsets.list")
      $0.errorBanner = "request timed out: toolsets.list"
    }
    #expect(transient.state.loadState != .unsupported(CapabilityCatalogError.unsupported.message))
  }

  @Test func hubBrowseAndSearchEnrichInstalledSkillsButNeverAddUninstalledRows() async {
    var state = loadedState()
    state.searchQuery = "doc"
    let original = state.originalSelection!
    let store = TestStore(initialState: state) { CapabilityManagementFeature() }
    store.exhaustivity = .off

    await store.send(.skillBrowseResponse(
      page: 1,
      .loaded(.init(
        entries: [
          .init(name: "docs", source: "hub", identifier: "hub/docs"),
          .init(name: "not-installed", description: "Registry only"),
        ],
        page: 1,
        totalPages: 1,
        total: 2
      ))
    ))
    #expect(!store.state.skills.contains { $0.name == "not-installed" })
    #expect(store.state.skills.first(where: { $0.name == "docs" })?.documentation
      == "https://example.invalid/docs")
    #expect(store.state.skills.first(where: { $0.name == "docs" })?.source == "hub")

    await store.send(.skillSearchResponse(
      query: "doc",
      .loaded([
        .init(name: "docs", description: "Search description"),
        .init(name: "also-not-installed", description: "Registry only"),
      ])
    ))
    #expect(store.state.skillSearchResultIDs == ["docs"])
    #expect(!store.state.skills.contains { $0.name == "also-not-installed" })
    #expect(store.state.skills.first(where: { $0.name == "docs" })?.identifier == "hub/docs")
    #expect(store.state.skills.first(where: { $0.name == "docs" })?.documentation
      == "https://example.invalid/docs")
    #expect(store.state.originalSelection == original)
    #expect(store.state.selection == original)
    #expect(!store.state.isDirty)
  }

  @Test func hubSearchKeepsMatchingLocallyAuthoredInstalledSkill() async {
    var state = loadedState()
    state.searchQuery = "legacy"
    let store = TestStore(initialState: state) { CapabilityManagementFeature() }
    store.exhaustivity = .off

    await store.send(.skillSearchResponse(query: "legacy", .loaded([])))

    #expect(store.state.skillSearchResultIDs == ["legacy-disabled"])
    #expect(store.state.filteredSkills.map(\.name) == ["legacy-disabled"])
  }

  @Test func sparseMCPRefreshAndUnsupportedSkillReloadRetainUsableCatalogState() async {
    var state = loadedState()
    state.mcpServers[0].tools = ["list_pull_requests"]
    state.mcpServers[0].toolCount = 1
    state.mcpServers[0].health = .healthy("Connected")
    let store = TestStore(initialState: state) { CapabilityManagementFeature() }
    store.exhaustivity = .off

    await store.send(.catalogResponse(.loaded(.init(
      mcpServers: [.init(name: "github", enabled: true, health: .unknown)]
    ))))
    let github = try #require(store.state.mcpServers.first { $0.name == "github" })
    #expect(github.tools == ["list_pull_requests"])
    #expect(github.toolCount == 1)
    #expect(github.health == .healthy("Connected"))

    await store.send(.reloadResponse(.unsupported(CapabilityCatalogError.unsupported.message)))
    #expect(store.state.reloadState == .unsupported(CapabilityCatalogError.unsupported.message))
    #expect(store.state.skillsLoadState == .loaded)
    #expect(store.state.toolsetsLoadState == .loaded)
    #expect(store.state.mcpLoadState == .loaded)
    #expect(store.state.skills.contains { $0.name == "docs" })
    #expect(store.state.canSave == false)
  }

  @Test func skillSearchAndInspectUseServerMetadataAndIgnoreStaleSearch() async {
    let clock = TestClock()
    let searches = LockIsolated<[SkillCatalogSearchRequest]>([])
    let inspections = LockIsolated<[SkillCatalogInspectRequest]>([])
    let store = TestStore(initialState: loadedState()) { CapabilityManagementFeature() } withDependencies: {
      $0.continuousClock = clock
      $0.hermesCapabilityCatalog.searchSkills = { @Sendable _, request in
        searches.withValue { $0.append(request) }
        return [.init(name: "docs", description: "Search result")]
      }
      $0.hermesCapabilityCatalog.inspectSkill = { @Sendable _, request in
        inspections.withValue { $0.append(request) }
        return .init(
          name: "docs",
          description: "Inspected detail",
          documentation: "https://example.invalid/inspect",
          identifier: request.identifier,
          enabled: true
        )
      }
    }
    store.exhaustivity = .off

    await store.send(.searchQueryChanged("doc"))
    await clock.advance(by: .milliseconds(250))
    await store.receive(\.runSkillSearch)
    await store.receive(\.skillSearchResponse)
    #expect(searches.value == [.init(query: "doc", profile: "ios-release")])
    #expect(store.state.filteredSkills.map(\.name) == ["docs"])

    await store.send(.skillSearchResponse(
      query: "stale", .loaded([.init(name: "stale-result")])
    ))
    #expect(!store.state.skills.contains { $0.name == "stale-result" })

    let detailID = CapabilityManagementFeature.DetailID(segment: .skills, name: "docs")
    await store.send(.detailTapped(detailID))
    await store.receive(\.skillDetailResponse)
    #expect(inspections.value.first?.identifier == "bundled/docs")
    guard case let .skill(detail)? = store.state.selectedDetail else {
      Issue.record("Expected selected skill detail")
      return
    }
    #expect(detail.skillDescription == "Inspected detail")
    #expect(detail.documentation == "https://example.invalid/inspect")
  }

  @Test func closeAndReloadProtectUnsavedChoices() async {
    let store = TestStore(initialState: loadedState()) { CapabilityManagementFeature() }
    store.exhaustivity = .off

    await store.send(.setSkillEnabled(name: "docs", enabled: false))
    await store.send(.closeTapped)
    #expect(store.state.confirmationDialog != nil)
    await store.send(.confirmationDialog(.dismiss))

    await store.send(.reloadTapped)
    #expect(store.state.confirmationDialog != nil)
  }

  @Test func settingsOwnsProfileScopedCapabilityPresentationAndRefreshesAfterSave() async {
    let summary = ProfileAdminSummary(name: "ios-release")
    let listCalls = LockIsolated(0)
    let store = TestStore(
      initialState: SettingsFeature.State(
        connection: connection,
        profiles: [summary],
        profileLoadState: .loaded,
        activeWorkflowProfileName: "ios-release"
      )
    ) { SettingsFeature() } withDependencies: {
      $0.hermesProfileAdmin.list = { @Sendable _, _ in
        listCalls.withValue { $0 += 1 }
        return [summary]
      }
    }
    store.exhaustivity = .off

    await store.send(.manageCapabilitiesTapped(summary)) {
      $0.capabilityManagement = CapabilityManagementFeature.State(
        connection: self.connection,
        profileName: "ios-release",
        hasActiveWorkflow: true
      )
    }
    await store.send(
      .capabilityManagement(
        .presented(.delegate(.capabilitiesChanged(profileName: "ios-release")))
      )
    )
    await store.receive(\.loadProfiles)
    await store.receive(\.profileListResponse.loaded)
    #expect(listCalls.value == 1)

    await store.send(.capabilityManagement(.presented(.delegate(.closed)))) {
      $0.capabilityManagement = nil
    }
  }

  private func initialState() -> CapabilityManagementFeature.State {
    CapabilityManagementFeature.State(connection: connection, profileName: "ios-release")
  }

  private func loadedState() -> CapabilityManagementFeature.State {
    var state = initialState()
    let selection = CapabilityManagementFeature.Selection(described)
    state.originalSelection = selection
    state.selection = selection
    state.installedSkillNames = Set(selection.skills.keys)
    state.profileLoadState = .loaded
    state.skillsLoadState = .loaded
    state.toolsetsLoadState = .loaded
    state.mcpLoadState = .loaded
    state.skills = [
      .init(
        name: "docs",
        skillDescription: "Official documentation",
        documentation: "https://example.invalid/docs",
        source: "bundled",
        category: "documentation",
        identifier: "bundled/docs",
        tags: ["reference"],
        enabled: true
      ),
      .init(name: "legacy-disabled", enabled: false),
    ]
    state.toolsets = [
      .init(name: "coding", label: "Coding", toolsetDescription: "Code tools", toolCount: 8, enabled: true),
      .init(name: "legacy-toolset", label: "Legacy", enabled: true),
      .init(name: "web", label: "Web", toolsetDescription: "Web tools", toolCount: 4, enabled: false),
    ]
    state.mcpServers = [
      .init(name: "github", serverDescription: "Repository tools", enabled: true),
      .init(name: "legacy-mcp", enabled: true),
      .init(name: "sentry", serverDescription: "Issue tools", enabled: false),
    ]
    return state
  }
}
