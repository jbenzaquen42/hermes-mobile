import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct ProfileEditorFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "https://agent.example")!, token: "tok"
  )

  private var summary: ProfileAdminSummary {
    ProfileAdminSummary(name: "work", profileDescription: "Summary")
  }

  private var described: ProfileDescription {
    ProfileDescription(
      name: "work",
      description: "Server description",
      soul: "# Server soul",
      model: .init(provider: "anthropic", defaultModel: "claude-sonnet"),
      reasoningEffort: nil,
      skills: [
        .init(name: "github", enabled: true),
        .init(name: "calendar", enabled: false),
      ],
      toolsets: [
        .init(name: "coding", label: "Coding", enabled: true),
        .init(name: "web", label: "Web", enabled: false),
      ],
      toolsetsPinned: true,
      mcpServers: [
        .init(name: "github", enabled: true, transport: "stdio"),
        .init(name: "sentry", enabled: false, transport: "http"),
      ]
    )
  }

  @Test func loadIsScopedToRequestedProfileAndAppliesEverySection() async {
    let requested = LockIsolated<[String]>([])
    let described = self.described
    let store = TestStore(
      initialState: ProfileEditorFeature.State(connection: connection, summary: summary)
    ) {
      ProfileEditorFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.describe = { @Sendable _, name in
        requested.withValue { $0.append(name) }
        return described
      }
    }

    await store.send(.task)
    await store.receive(\.load) {
      $0.loadState = .loading
      $0.errorBanner = nil
    }
    await store.receive(\.loadResponse.loaded) {
      $0.description = "Server description"
      $0.soul = "# Server soul"
      $0.provider = "anthropic"
      $0.model = "claude-sonnet"
      $0.reasoningEffort = ""
      $0.skills = described.skills
      $0.toolsets = described.toolsets
      $0.toolsetsPinned = true
      $0.mcpServers = described.mcpServers
      $0.renameDraft = "work"
      $0.loadState = .loaded
      $0.describeSupported = true
      $0.errorBanner = nil
      $0.saveState = .idle
      $0.original = ProfileEditorFeature.Values(described)
    }

    #expect(requested.value == ["work"])
    #expect(store.state.isDirty == false)
    #expect(store.state.characterCount == 13)
    #expect(store.state.estimatedTokenCount == 4)
  }

  @Test func mismatchedDescribeResponseIsRejectedRatherThanCrossScoping() async {
    let store = TestStore(
      initialState: ProfileEditorFeature.State(connection: connection, summary: summary)
    ) {
      ProfileEditorFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.describe = { @Sendable _, _ in
        ProfileDescription(name: "other", soul: "wrong profile")
      }
    }

    await store.send(.load) {
      $0.loadState = .loading
      $0.errorBanner = nil
    }
    await store.receive(\.loadResponse.loaded) {
      $0.loadState = .failed("Hermes returned a different profile than requested.")
      $0.errorBanner = "The profile response was not scoped to work."
    }

    #expect(store.state.soul.isEmpty)
  }

  @Test func unsupportedDescribeGatesFeatureButTransportFailureDoesNot() async {
    let unsupported = TestStore(
      initialState: ProfileEditorFeature.State(connection: connection, summary: summary)
    ) {
      ProfileEditorFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.describe = { @Sendable _, _ in throw ProfileAdminError.unsupported }
    }

    await unsupported.send(.load) {
      $0.loadState = .loading
      $0.errorBanner = nil
    }
    await unsupported.receive(\.loadResponse.unsupported) {
      $0.loadState = .unsupported
      $0.describeSupported = false
      $0.configureSupported = false
      $0.errorBanner = ProfileAdminError.unsupported.message
    }

    let transient = TestStore(
      initialState: ProfileEditorFeature.State(connection: connection, summary: summary)
    ) {
      ProfileEditorFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.describe = { @Sendable _, _ in
        throw ProfileAdminError.request("request timed out: profiles.describe")
      }
    }

    await transient.send(.load) {
      $0.loadState = .loading
      $0.errorBanner = nil
    }
    await transient.receive(\.loadResponse.failed) {
      $0.loadState = .failed("request timed out: profiles.describe")
      $0.errorBanner = "request timed out: profiles.describe"
    }
    #expect(transient.state.describeSupported == nil)
  }

  @Test func explicitSaveUsesReplaceSemanticsAndReportsPartialResult() async {
    let captured = LockIsolated<ProfileConfigureRequest?>(nil)
    let draftStore = ProfileDraftClient.inMemory()
    let authoritative: ProfileDescription = {
      var value = described
      value.description = "Edited description"
      return value
    }()
    // SOUL failed and reasoning is unreported, so authoritative values remain unchanged.

    let store = loadedStore(draftStore: draftStore) {
      $0.hermesProfileAdmin.configure = { @Sendable _, request in
        captured.setValue(request)
        return ProfileConfigureResult(
          ok: false,
          requestedSections: request.requestedSections,
          sectionStatuses: [
            .description: .applied,
            .soul: .failed,
            .reasoningEffort: .notReported,
            .skills: .applied,
            .toolsets: .applied,
            .mcpServers: .failed,
          ]
        )
      }
      $0.hermesProfileAdmin.describe = { @Sendable _, _ in authoritative }
    }
    await load(store)

    await store.send(\.binding.description, "Edited description") {
      $0.description = "Edited description"
    }
    await store.send(\.binding.soul, "# Local soul") {
      $0.soul = "# Local soul"
    }
    await store.send(\.binding.reasoningEffort, "high") {
      $0.reasoningEffort = "high"
    }
    await store.send(.setSkillEnabled(name: "calendar", enabled: true)) {
      $0.skills[1].enabled = true
      $0.saveState = .idle
    }
    await store.send(.setToolsetEnabled(name: "web", enabled: true)) {
      $0.toolsets[1].enabled = true
      $0.toolsetsPinned = true
      $0.saveState = .idle
    }
    await store.send(.setMCPServerEnabled(name: "sentry", enabled: true)) {
      $0.mcpServers[1].enabled = true
      $0.saveState = .idle
    }

    await store.send(.saveTapped) {
      $0.saveState = .saving
      $0.errorBanner = nil
    }
    await store.receive(\.saveResponse.configured) {
      $0.configureSupported = true
      // Server-confirmed description/skills/toolsets become the baseline. Failed SOUL/MCP
      // and unreported reasoning remain dirty and visible for retry.
      $0.original = ProfileEditorFeature.Values(authoritative)
      $0.description = authoritative.description
      $0.skills = authoritative.skills
      $0.toolsets = authoritative.toolsets
      $0.toolsetsPinned = authoritative.toolsetsPinned
      $0.saveState = .partial(.init(
        applied: [.description, .skills, .toolsets],
        failed: [.soul, .mcpServers],
        unreported: [.reasoningEffort]
      ))
      $0.errorBanner = nil
    }

    let request = try #require(captured.value)
    #expect(request.name == "work")
    #expect(request.descriptionText == "Edited description")
    #expect(request.soul == "# Local soul")
    #expect(request.reasoningEffort == "high")
    #expect(request.disabledSkills == [])
    #expect(request.enabledToolsets == ["coding", "web"])
    #expect(request.enabledMCPServers == ["github", "sentry"])
    #expect(store.state.soul == "# Local soul")
    #expect(store.state.reasoningEffort == "high")
    #expect(store.state.mcpServers[1].enabled)
    #expect(store.state.isDirty)
    #expect(draftStore.load(connection.baseURL, "work") != nil)
  }

  @Test func completeSaveReloadsAuthoritativeStateAndClearsDraft() async {
    let draftStore = ProfileDraftClient.inMemory()
    let reloaded: ProfileDescription = {
      var value = described
      value.soul = "# Normalized by server\n"
      return value
    }()
    let store = loadedStore(draftStore: draftStore) {
      $0.hermesProfileAdmin.configure = { @Sendable _, request in
        ProfileConfigureResult(
          ok: true,
          requestedSections: request.requestedSections,
          sectionStatuses: [.soul: .applied]
        )
      }
      $0.hermesProfileAdmin.describe = { @Sendable _, _ in reloaded }
    }
    await load(store)

    await store.send(\.binding.soul, "# Edited") {
      $0.soul = "# Edited"
    }
    #expect(draftStore.load(connection.baseURL, "work") != nil)

    await store.send(.saveTapped) {
      $0.saveState = .saving
      $0.errorBanner = nil
    }
    await store.receive(\.saveResponse.configured) {
      $0.configureSupported = true
      $0.original = ProfileEditorFeature.Values(reloaded)
      $0.soul = "# Normalized by server\n"
      $0.saveState = .saved(.init(applied: [.soul]))
      $0.errorBanner = nil
    }

    #expect(!store.state.isDirty)
    #expect(draftStore.load(connection.baseURL, "work") == nil)
  }

  @Test func configureRejectionPreservesAllEditsAndDraft() async {
    let draftStore = ProfileDraftClient.inMemory()
    let store = loadedStore(draftStore: draftStore) {
      $0.hermesProfileAdmin.configure = { @Sendable _, _ in
        throw ProfileAdminError.request("SOUL is too large")
      }
    }
    await load(store)
    await store.send(\.binding.soul, String(repeating: "x", count: 20)) {
      $0.soul = String(repeating: "x", count: 20)
    }

    await store.send(.saveTapped) {
      $0.saveState = .saving
      $0.errorBanner = nil
    }
    await store.receive(\.saveResponse.failed) {
      $0.saveState = .failed("SOUL is too large")
      $0.errorBanner = "SOUL is too large"
    }

    #expect(store.state.soul == String(repeating: "x", count: 20))
    #expect(store.state.isDirty)
    #expect(draftStore.load(connection.baseURL, "work") != nil)
  }

  @Test func recoveredDraftIsOfferedAndRestoresWithoutDroppingNewServerEntries() async throws {
    let draftStore = ProfileDraftClient.inMemory()
    var old = described
    old.soul = "old baseline"
    var edited = ProfileEditorFeature.Values(old)
    edited.soul = "locally recovered"
    edited.skills[0].enabled = false
    let draft = ProfileEditorFeature.ProfileEditorDraft(
      baseline: .init(values: .init(old)),
      edited: .init(values: edited),
      renameDraft: "work-renamed",
      savedAt: Date(timeIntervalSince1970: 100)
    )
    draftStore.save(
      connection.baseURL,
      "work",
      try JSONEncoder().encode(draft)
    )
    let current: ProfileDescription = {
      var value = described
      value.soul = "new server soul"
      value.skills.append(.init(name: "new-server-skill", enabled: true))
      return value
    }()

    let store = TestStore(
      initialState: ProfileEditorFeature.State(connection: connection, summary: summary)
    ) {
      ProfileEditorFeature()
    } withDependencies: {
      $0.profileDraft = draftStore
      $0.hermesProfileAdmin.describe = { @Sendable _, _ in current }
    }

    await store.send(.load) {
      $0.loadState = .loading
      $0.errorBanner = nil
    }
    await store.receive(\.loadResponse.loaded) {
      $0.currentValues = .init(current)
      $0.original = .init(current)
      $0.renameDraft = "work"
      $0.loadState = .loaded
      $0.describeSupported = true
      $0.errorBanner = nil
      $0.saveState = .idle
      $0.recoveredDraft = draft
    }
    #expect(store.state.recoveredDraftConflictsWithServer)

    await store.send(.restoreDraftTapped) {
      var restored = ProfileEditorFeature.Values(current)
      restored.soul = "locally recovered"
      restored.skills[0].enabled = false
      $0.currentValues = restored
      $0.renameDraft = "work-renamed"
      $0.recoveredDraft = nil
      $0.saveState = .idle
    }

    #expect(store.state.skills.last?.name == "new-server-skill")
    #expect(store.state.skills.last?.enabled == true)
    #expect(store.state.isDirty)
  }

  @Test func dirtyCloseAndReloadRequireConfirmation() async {
    let draftStore = ProfileDraftClient.inMemory()
    let store = loadedStore(draftStore: draftStore)
    store.exhaustivity = .off(showSkippedAssertions: false)
    await load(store)
    await store.send(\.binding.soul, "dirty")

    await store.send(.closeTapped)
    #expect(store.state.confirmationDialog != nil)
    await store.send(.confirmationDialog(.presented(.discardAndClose)))
    await store.receive(\.delegate.closed)
    #expect(draftStore.load(connection.baseURL, "work") == nil)
  }

  @Test func renameAndDeleteAreConfirmedAndUseProfileScopedRESTPaths() async {
    let renames = LockIsolated<[(String, String)]>([])
    let deletes = LockIsolated<[String]>([])
    let store = loadedStore {
      $0.hermesProfiles.rename = { @Sendable _, old, new in
        renames.withValue { $0.append((old, new)) }
      }
      $0.hermesProfiles.delete = { @Sendable _, name in
        deletes.withValue { $0.append(name) }
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await load(store)

    await store.send(\.binding.renameDraft, "work-2")
    #expect(store.state.canRename)
    await store.send(.renameTapped)
    #expect(store.state.confirmationDialog != nil)
    await store.send(.confirmationDialog(.presented(
      .confirmRename(oldName: "work", newName: "work-2")
    )))
    await store.receive(\.renameResponse.success)
    await store.receive(\.delegate.renamed)
    #expect(renames.value.count == 1)
    #expect(renames.value.first?.0 == "work")
    #expect(renames.value.first?.1 == "work-2")

    await store.send(.deleteTapped)
    #expect(store.state.confirmationDialog != nil)
    await store.send(.confirmationDialog(.presented(.confirmDelete(name: "work-2"))))
    await store.receive(\.deleteResponse.success)
    await store.receive(\.delegate.deleted)
    #expect(deletes.value == ["work-2"])
  }

  @Test func defaultProfileCannotRenameOrDelete() async {
    let defaultSummary = ProfileAdminSummary(name: "default", isDefault: true)
    var state = ProfileEditorFeature.State(connection: connection, summary: defaultSummary)
    state.loadState = .loaded
    state.original = .init(ProfileDescription(name: "default"))
    let store = TestStore(initialState: state) { ProfileEditorFeature() }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(\.binding.renameDraft, "renamed")
    await store.send(.renameTapped)
    await store.send(.deleteTapped)
    #expect(store.state.confirmationDialog == nil)
    #expect(!store.state.canRename)
  }

  private func loadedStore(
    draftStore: ProfileDraftClient = .inMemory(),
    configure: (inout DependencyValues) -> Void = { _ in }
  ) -> TestStoreOf<ProfileEditorFeature> {
    let described = self.described
    TestStore(
      initialState: ProfileEditorFeature.State(connection: connection, summary: summary)
    ) {
      ProfileEditorFeature()
    } withDependencies: {
      $0.profileDraft = draftStore
      $0.date.now = Date(timeIntervalSince1970: 1_000)
      $0.hermesProfileAdmin.describe = { @Sendable _, _ in described }
      configure(&$0)
    }
  }

  private func load(_ store: TestStoreOf<ProfileEditorFeature>) async {
    let described = self.described
    await store.send(.load) {
      $0.loadState = .loading
      $0.errorBanner = nil
    }
    await store.receive(\.loadResponse.loaded) {
      $0.currentValues = ProfileEditorFeature.Values(described)
      $0.original = ProfileEditorFeature.Values(described)
      $0.renameDraft = "work"
      $0.loadState = .loaded
      $0.describeSupported = true
      $0.errorBanner = nil
      $0.saveState = .idle
    }
  }
}
