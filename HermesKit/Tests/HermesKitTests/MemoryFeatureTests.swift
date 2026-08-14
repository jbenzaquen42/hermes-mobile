import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct MemoryFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "https://agent.example")!, token: "tok"
  )

  private var entries: [LearningEntrySummary] {
    [
      .init(id: "memory:memory:0", label: "Prefers concise updates", kind: .agentMemory),
      .init(id: "memory:profile:1", label: "Uses an iPhone", kind: .userProfile),
      .init(id: "learned-debugging", label: "Learned debugging", kind: .learnedSkill),
    ]
  }

  private var snapshot: LearningSnapshot {
    LearningSnapshot(
      entries: entries,
      reportedCount: 3,
      capacity: LearningCapacityInfo(
        agentMemory: .init(usedCharacters: 20, limitCharacters: 100),
        userProfile: .init(usedCharacters: 10, limitCharacters: 80)
      ),
      metadata: LearningSnapshotMetadata(
        profileScope: .serverDefaultProfile,
        memoryRefreshPolicy: .freshSessionSnapshot,
        rawDocumentReplacement: .unsupported,
        capacityReporting: .notReportedByServer
      )
    )
  }

  @Test func customProfileIsGatedWithoutCallingTheUnscopedClient() async {
    let calls = LockIsolated(0)
    let store = TestStore(
      initialState: MemoryFeature.State(
        connection: connection,
        profileName: "custom",
        isServerDefaultProfile: false
      )
    ) { MemoryFeature() } withDependencies: {
      $0.hermesLearning.load = { @Sendable _ in
        calls.withValue { $0 += 1 }
        return LearningSnapshot()
      }
    }

    await store.send(.load) {
      $0.loadState = .unsupported(MemoryFeature.customProfileMessage)
    }
    #expect(calls.value == 0)
  }

  @Test func loadSearchFilterCapacityAndSnapshotExplanationAreTypedAndLocal() async {
    let snapshot = self.snapshot
    let store = TestStore(initialState: initialState()) { MemoryFeature() } withDependencies: {
      $0.hermesLearning.load = { @Sendable _ in snapshot }
    }
    store.exhaustivity = .off

    await store.send(.task)
    await store.receive(\.loadResponse)

    #expect(store.state.loadState == .loaded)
    #expect(store.state.reportedCount == 3)
    #expect(store.state.capacity?.agentMemory.remainingCharacters == 80)
    #expect(store.state.capacityReporting == .notReportedByServer)
    #expect(store.state.sessionSnapshotExplanation.contains("fresh session"))
    #expect(store.state.metadata.rawDocumentReplacement == .unsupported)

    await store.send(.storeFilterChanged(.userProfile))
    #expect(store.state.filteredEntries.map(\.id) == ["memory:profile:1"])
    await store.send(.searchQueryChanged("iphone"))
    #expect(store.state.filteredEntries.map(\.id) == ["memory:profile:1"])
    await store.send(.searchQueryChanged("missing"))
    #expect(store.state.filteredEntries.isEmpty)
  }

  @Test func unsupportedAndTransientLoadFailuresRemainDistinct() async {
    let unsupported = TestStore(initialState: initialState()) { MemoryFeature() } withDependencies: {
      $0.hermesLearning.load = { @Sendable _ in throw LearningClientError.unsupported }
    }
    unsupported.exhaustivity = .off
    await unsupported.send(.load)
    await unsupported.receive(\.loadResponse)
    #expect(unsupported.state.loadState == .unsupported(LearningClientError.unsupported.message))
    #expect(unsupported.state.errorBanner == nil)

    let transient = TestStore(initialState: initialState()) { MemoryFeature() } withDependencies: {
      $0.hermesLearning.load = { @Sendable _ in
        throw LearningClientError.request("request timed out: learning.frames")
      }
    }
    transient.exhaustivity = .off
    await transient.send(.load)
    await transient.receive(\.loadResponse)
    #expect(transient.state.loadState == .failed("request timed out: learning.frames"))
    #expect(transient.state.errorBanner == "request timed out: learning.frames")
  }

  @Test func emptySnapshotDoesNotInventCapacityOrEntries() async {
    let store = TestStore(initialState: initialState()) { MemoryFeature() }
    await store.send(.loadResponse(store.state.scope, .loaded(LearningSnapshot()))) {
      $0.entries = []
      $0.reportedCount = 0
      $0.capacity = nil
      $0.metadata = LearningSnapshotMetadata()
      $0.loadState = .loaded
      $0.errorBanner = nil
    }
    #expect(store.state.filteredEntries.isEmpty)
    #expect(store.state.capacity == nil)
    #expect(store.state.capacityReporting == .notReportedByServer)
  }

  @Test func detailEditStaysLocalUntilSaveThenReloadsAuthoritatively() async throws {
    let editCalls = LockIsolated<[LearningEditRequest]>([])
    let detailCalls = LockIsolated(0)
    let original = LearningEntryDetail(
      id: "memory:memory:0",
      label: "Prefers concise updates",
      kind: .agentMemory,
      content: "Prefers concise updates"
    )
    let authoritative = LearningEntryDetail(
      id: original.id,
      label: "Prefers exact updates",
      kind: original.kind,
      content: "Prefers exact updates"
    )
    let refreshed: LearningSnapshot = {
      var value = snapshot
      value.entries[0].label = authoritative.label
      return value
    }()

    let store = TestStore(initialState: loadedState()) { MemoryFeature() } withDependencies: {
      $0.hermesLearning.detail = { @Sendable _, _ in
        let call = detailCalls.withValue { value in
          defer { value += 1 }
          return value
        }
        return call == 0 ? original : authoritative
      }
      $0.hermesLearning.edit = { @Sendable _, request in
        editCalls.withValue { $0.append(request) }
        return LearningMutationResult(
          succeeded: true, id: request.id, action: .updated, message: "updated"
        )
      }
      $0.hermesLearning.load = { @Sendable _ in refreshed }
    }
    store.exhaustivity = .off

    await store.send(.entryTapped(original.id))
    await store.receive(\.detailResponse)
    await store.send(.editContentChanged(authoritative.content))
    #expect(store.state.isEditDirty)
    #expect(editCalls.value.isEmpty)

    await store.send(.saveEditTapped)
    await store.receive(\.editResponse)

    #expect(editCalls.value == [LearningEditRequest(id: original.id, content: authoritative.content)])
    #expect(store.state.selectedDetail == authoritative)
    #expect(store.state.editDraft?.content == authoritative.content)
    #expect(!store.state.isEditDirty)
    #expect(store.state.entries.first?.label == authoritative.label)
    guard case let .succeeded(report) = store.state.mutationState else {
      Issue.record("Expected an acknowledged edit with authoritative reloads")
      return
    }
    #expect(report.action == .updated)
    #expect(report.reloadErrors.isEmpty)
  }

  @Test func dirtyDetailAndCloseRequireReducerOwnedConfirmation() async {
    let detail = LearningEntryDetail(
      id: "memory:memory:0", label: "Entry", kind: .agentMemory, content: "old"
    )
    var state = loadedState()
    state.selectedEntryID = detail.id
    state.selectedDetail = detail
    state.detailLoadState = .loaded
    state.editDraft = .init(
      id: detail.id,
      profileName: "default",
      label: detail.label,
      kind: detail.kind,
      originalContent: detail.content,
      content: "new"
    )
    let store = TestStore(initialState: state) { MemoryFeature() }
    store.exhaustivity = .off

    await store.send(.detailDismissed)
    #expect(store.state.confirmationDialog != nil)
    #expect(store.state.selectedDetail != nil)
    await store.send(.confirmationDialog(.presented(.discardDetail)))
    #expect(store.state.selectedDetail == nil)

    var closeState = state
    closeState.confirmationDialog = nil
    let closeStore = TestStore(initialState: closeState) { MemoryFeature() }
    closeStore.exhaustivity = .off
    await closeStore.send(.closeTapped)
    #expect(closeStore.state.confirmationDialog != nil)
  }

  @Test func deleteMemoryAndArchiveSkillUseDifferentAcknowledgedActions() async {
    for (entry, expectedAction) in [
      (entries[0], LearningMutationAction.deleted),
      (entries[2], LearningMutationAction.archived),
    ] {
      let deletedIDs = LockIsolated<[String]>([])
      var state = loadedState()
      select(entry, in: &state)
      let refreshed: LearningSnapshot = {
        var value = snapshot
        value.entries.removeAll { $0.id == entry.id }
        value.reportedCount = value.entries.count
        return value
      }()
      let store = TestStore(initialState: state) { MemoryFeature() } withDependencies: {
        $0.hermesLearning.delete = { @Sendable _, id in
          deletedIDs.withValue { $0.append(id) }
          return LearningMutationResult(
            succeeded: true, id: id, action: expectedAction, message: "done"
          )
        }
        $0.hermesLearning.load = { @Sendable _ in refreshed }
      }
      store.exhaustivity = .off

      await store.send(.deleteOrArchiveTapped)
      #expect(store.state.confirmationDialog != nil)
      let identity = MemoryFeature.EntryIdentity(
        profileName: "default", id: entry.id, kind: entry.kind
      )
      await store.send(
        .confirmationDialog(.presented(.confirmDeleteOrArchive(identity)))
      )
      await store.receive(\.deleteResponse)

      #expect(deletedIDs.value == [entry.id])
      #expect(!store.state.entries.contains { $0.id == entry.id })
      #expect(store.state.selectedDetail == nil)
      guard case let .succeeded(report) = store.state.mutationState else {
        Issue.record("Expected a successful delete/archive")
        continue
      }
      #expect(report.action == expectedAction)
    }
  }

  @Test func successfulMutationWithFailedReloadIsAccuratelyPartial() async {
    let entry = entries[0]
    var state = loadedState()
    select(entry, in: &state)
    let store = TestStore(initialState: state) { MemoryFeature() } withDependencies: {
      $0.hermesLearning.delete = { @Sendable _, id in
        LearningMutationResult(succeeded: true, id: id, action: .deleted, message: "deleted")
      }
      $0.hermesLearning.load = { @Sendable _ in
        throw LearningClientError.request("request timed out: learning.frames")
      }
    }
    store.exhaustivity = .off
    let identity = MemoryFeature.EntryIdentity(
      profileName: "default", id: entry.id, kind: entry.kind
    )

    await store.send(.deleteOrArchiveTapped)
    await store.send(.confirmationDialog(.presented(.confirmDeleteOrArchive(identity))))
    await store.receive(\.deleteResponse)

    #expect(store.state.entries.contains { $0.id == entry.id })
    #expect(store.state.selectedDetail == nil)
    guard case let .partial(report) = store.state.mutationState else {
      Issue.record("Expected a partial mutation result")
      return
    }
    #expect(report.action == .deleted)
    #expect(report.reloadErrors == ["request timed out: learning.frames"])
    #expect(store.state.errorBanner == report.reloadErrors.first)
  }

  @Test func staleSelectionCannotDeleteAfterAuthoritativeListChanges() async {
    let deleteCalls = LockIsolated(0)
    let entry = entries[0]
    var state = loadedState()
    select(entry, in: &state)
    let store = TestStore(initialState: state) { MemoryFeature() } withDependencies: {
      $0.hermesLearning.delete = { @Sendable _, id in
        deleteCalls.withValue { $0 += 1 }
        return LearningMutationResult(succeeded: true, id: id, action: .deleted)
      }
    }
    store.exhaustivity = .off
    let identity = MemoryFeature.EntryIdentity(
      profileName: "default", id: entry.id, kind: entry.kind
    )

    await store.send(.deleteOrArchiveTapped)
    var withoutSelection = snapshot
    withoutSelection.entries.removeAll { $0.id == entry.id }
    await store.send(.loadResponse(store.state.scope, .loaded(withoutSelection)))
    await store.send(.confirmationDialog(.presented(.confirmDeleteOrArchive(identity))))

    #expect(deleteCalls.value == 0)
    #expect(store.state.selectedDetail == nil)
  }

  @Test func settingsAndAppOwnMemoryPresentationWithAuthoritativeDefaultFlag() async {
    let defaultProfile = ProfileAdminSummary(name: "default", isDefault: true)
    let customProfile = ProfileAdminSummary(name: "custom", isDefault: false)
    let profiles: IdentifiedArrayOf<ProfileAdminSummary> = [defaultProfile, customProfile]
    let settingsStore = TestStore(
      initialState: SettingsFeature.State(connection: connection, profiles: profiles)
    ) { SettingsFeature() }

    await settingsStore.send(.manageMemoryTapped(defaultProfile)) {
      $0.memory = MemoryFeature.State(
        connection: self.connection,
        profileName: "default",
        isServerDefaultProfile: true
      )
    }
    await settingsStore.send(.memory(.presented(.delegate(.closed)))) {
      $0.memory = nil
    }
    await settingsStore.send(.manageMemoryTapped(customProfile)) {
      $0.memory = MemoryFeature.State(
        connection: self.connection,
        profileName: "custom",
        isServerDefaultProfile: false
      )
    }

    let appStore = TestStore(
      initialState: AppFeature.State(
        settings: SettingsFeature.State(connection: connection, profiles: profiles)
      )
    ) { AppFeature() }
    appStore.exhaustivity = .off
    await appStore.send(.settings(.manageMemoryTapped(defaultProfile)))
    #expect(appStore.state.settings?.memory?.profileName == "default")
    #expect(appStore.state.settings?.memory?.isServerDefaultProfile == true)
  }

  private func initialState() -> MemoryFeature.State {
    MemoryFeature.State(
      connection: connection,
      profileName: "default",
      isServerDefaultProfile: true
    )
  }

  private func loadedState() -> MemoryFeature.State {
    var state = initialState()
    state.entries = entries
    state.reportedCount = snapshot.reportedCount
    state.capacity = snapshot.capacity
    state.metadata = snapshot.metadata
    state.loadState = .loaded
    return state
  }

  private func select(_ entry: LearningEntrySummary, in state: inout MemoryFeature.State) {
    let detail = LearningEntryDetail(
      id: entry.id, label: entry.label, kind: entry.kind, content: entry.label
    )
    state.selectedEntryID = entry.id
    state.selectedDetail = detail
    state.editDraft = .init(
      id: entry.id,
      profileName: state.profileName,
      label: entry.label,
      kind: entry.kind,
      originalContent: detail.content,
      content: detail.content
    )
    state.detailLoadState = .loaded
  }
}
