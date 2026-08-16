import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct AutomationsFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "https://agent.example")!, token: "tok"
  )

  private var jobs: [CronJob] {
    [
      CronJob(
        id: "job1",
        name: "Digest",
        prompt: "Summarize",
        scheduleDisplay: "every day at 09:00",
        scheduleExpression: "0 9 * * *",
        enabled: true,
        state: "scheduled",
        deliver: "local",
        model: "m",
        provider: "p",
        skills: ["research"]
      ),
      CronJob(id: "job2", name: "Backup", enabled: false, state: "paused"),
    ]
  }

  @Test func loadStoresJobsAndDeliveryTargetsWithScopedProfile() async {
    let requestedProfiles = LockIsolated<[String?]>([])
    let jobs = self.jobs
    let store = TestStore(
      initialState: AutomationsFeature.State(connection: connection, profileName: "work")
    ) {
      AutomationsFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.hermesREST.cronJobs = { @Sendable _, profile in
        requestedProfiles.withValue { $0.append(profile) }
        return jobs
      }
      $0.hermesREST.cronDeliveryTargets = { @Sendable _ in
        [CronDeliveryTarget(id: "local", name: "Local", homeTargetSet: true)]
      }
    }
    store.exhaustivity = .off

    await store.send(.task) {
      $0.isVisible = true
      $0.listLoadState = .loading
    }
    await store.receive(\.loadResponse) {
      $0.listSupported = true
      $0.writeSupported = true
      $0.jobs = IdentifiedArray(uniqueElements: jobs)
      $0.listLoadState = .loaded
      $0.isRefreshing = false
    }
    await store.receive(\.deliveryTargetsResponse) {
      $0.deliveryTargets = [CronDeliveryTarget(id: "local", name: "Local", homeTargetSet: true)]
    }

    #expect(requestedProfiles.value == ["work"])
    await store.send(.onDisappear)
  }

  @Test func notFoundMarksReadAndWriteUnsupportedWithoutLosingOtherTabs() async {
    let store = TestStore(
      initialState: AutomationsFeature.State(connection: connection, profileName: nil)
    ) {
      AutomationsFeature()
    } withDependencies: {
      $0.hermesREST.cronJobs = { @Sendable _, _ in throw RESTError.notFound }
      $0.hermesREST.cronDeliveryTargets = { @Sendable _ in
        [CronDeliveryTarget(id: "local", name: "Local", homeTargetSet: true)]
      }
    }
    store.exhaustivity = .off

    await store.send(.loadResponse(.failure(.notFound))) {
      $0.listSupported = false
      $0.writeSupported = false
      $0.listLoadState = .unsupported("Automations are not available on this server.")
      $0.isRefreshing = false
    }
  }

  @Test func transientListFailureKeepsPreviousJobsAndSurfacesBanner() async {
    let initial = AutomationsFeature.State(
      connection: connection,
      profileName: nil,
      jobs: IdentifiedArray(uniqueElements: jobs),
      listLoadState: .loaded,
      listSupported: true
    )
    let store = TestStore(initialState: initial) { AutomationsFeature() }
    store.exhaustivity = .off

    await store.send(.loadResponse(.failure(.unreachable))) {
      $0.isRefreshing = false
      $0.errorBanner = "Couldn’t reach the server."
    }
    #expect(store.state.jobs.map(\.id) == ["job1", "job2"])
    #expect(store.state.listSupported == true)
  }

  @Test func selectingJobLoadsDetailAndRuns() async {
    let store = TestStore(
      initialState: AutomationsFeature.State(
        connection: connection,
        profileName: nil,
        jobs: IdentifiedArray(uniqueElements: jobs),
        listLoadState: .loaded
      )
    ) {
      AutomationsFeature()
    } withDependencies: {
      $0.hermesREST.cronJobDetail = { @Sendable _, id, profile in
        #expect(id == "job1")
        #expect(profile == nil)
        return CronJob(id: "job1", name: "Digest", state: "running")
      }
      $0.hermesREST.cronJobRuns = { @Sendable _, id, profile, limit in
        #expect(id == "job1")
        #expect(limit == 20)
        return [Session(id: "cron_job1_20260702_090000", source: "cron")]
      }
    }
    store.exhaustivity = .off

    await store.send(.jobTapped("job1")) {
      $0.selectedJobID = "job1"
      $0.detailLoadState = .loading
      $0.runsLoadState = .loading
    }
    await store.receive(\.detailResponse) {
      $0.detail = CronJob(id: "job1", name: "Digest", state: "running")
      $0.detailLoadState = .loaded
      $0.jobs[id: "job1"] = CronJob(id: "job1", name: "Digest", state: "running")
    }
    await store.receive(\.runsResponse) {
      $0.runs = [Session(id: "cron_job1_20260702_090000", source: "cron")]
      $0.runsLoadState = .loaded
    }
  }

  @Test func createSaveUsesVerifiedFieldsAndReloads() async {
    let created = LockIsolated<[CronJobDraft]>([])
    let store = TestStore(
      initialState: AutomationsFeature.State(
        connection: connection,
        profileName: "work",
        jobs: [],
        listLoadState: .loaded,
        writeSupported: true
      )
    ) {
      AutomationsFeature()
    } withDependencies: {
      $0.hermesREST.createCronJob = { @Sendable _, draft, profile in
        created.withValue { $0.append(draft) }
        #expect(profile == "work")
      }
      $0.hermesREST.cronJobs = { @Sendable _, _ in
        [CronJob(id: "new", name: "Digest", prompt: "Summarize", scheduleExpression: "0 9 * * *")]
      }
      $0.hermesREST.cronDeliveryTargets = { @Sendable _ in [] }
    }
    store.exhaustivity = .off

    await store.send(.createTapped) {
      $0.editor = AutomationsFeature.EditorState(mode: .create)
    }
    await store.send(.editorNameChanged("Digest"))
    await store.send(.editorPromptChanged("Summarize"))
    await store.send(.editorScheduleChanged("0 9 * * *"))
    await store.send(.saveEditorTapped) {
      $0.editor?.isSaving = true
    }
    await store.receive(\.saveEditorResponse) {
      $0.editor = nil
    }
    await store.receive(\.loadResponse) {
      $0.jobs = IdentifiedArray(uniqueElements: [
        CronJob(id: "new", name: "Digest", prompt: "Summarize", scheduleExpression: "0 9 * * *")
      ])
      $0.listLoadState = .loaded
      $0.isRefreshing = false
    }

    #expect(created.value.count == 1)
    #expect(created.value.first?.trimmedSchedule == "0 9 * * *")
    #expect(created.value.first?.trimmedPrompt == "Summarize")
  }

  @Test func editorRejectsMissingScheduleBeforeCallingServer() async {
    let called = LockIsolated(false)
    let store = TestStore(
      initialState: AutomationsFeature.State(
        connection: connection,
        profileName: nil,
        listLoadState: .loaded,
        writeSupported: true
      )
    ) {
      AutomationsFeature()
    } withDependencies: {
      $0.hermesREST.createCronJob = { @Sendable _, _, _ in
        called.withValue { $0 = true }
      }
    }
    store.exhaustivity = .off

    await store.send(.createTapped)
    await store.send(.editorPromptChanged("No schedule"))
    await store.send(.saveEditorTapped) {
      $0.editor?.validationMessage = "Schedule is required."
    }
    #expect(called.value == false)
  }

  @Test func deleteConfirmsThenReloadsAuthoritativeList() async {
    let deleted = LockIsolated<[String]>([])
    let jobs = self.jobs
    let store = TestStore(
      initialState: AutomationsFeature.State(
        connection: connection,
        profileName: nil,
        jobs: IdentifiedArray(uniqueElements: jobs),
        listLoadState: .loaded,
        selectedJobID: "job2"
      )
    ) {
      AutomationsFeature()
    } withDependencies: {
      $0.hermesREST.deleteCronJob = { @Sendable _, id, _ in
        deleted.withValue { $0.append(id) }
      }
      $0.hermesREST.cronJobs = { @Sendable _, _ in [jobs[0]] }
      $0.hermesREST.cronDeliveryTargets = { @Sendable _ in [] }
    }
    store.exhaustivity = .off

    await store.send(.deleteTapped("job2"))
    #expect(store.state.confirmationDialog != nil)
    await store.send(.confirmationDialog(.presented(.confirmDelete("job2")))) {
      $0.confirmationDialog = nil
      $0.actionInFlightIDs = ["job2"]
    }
    await store.receive(\.deleteResponse) {
      $0.actionInFlightIDs = []
      $0.selectedJobID = nil
      $0.detail = nil
      $0.runs = []
    }
    await store.receive(\.loadResponse) {
      $0.jobs = IdentifiedArray(uniqueElements: [jobs[0]])
      $0.listLoadState = .loaded
      $0.isRefreshing = false
    }
    #expect(deleted.value == ["job2"])
  }

  @Test func runNowRefreshesAfterSuccess() async {
    let jobs = self.jobs
    let store = TestStore(
      initialState: AutomationsFeature.State(
        connection: connection,
        profileName: nil,
        jobs: IdentifiedArray(uniqueElements: jobs),
        listLoadState: .loaded
      )
    ) {
      AutomationsFeature()
    } withDependencies: {
      $0.hermesREST.triggerCronJob = { @Sendable _, id, _ in
        #expect(id == "job1")
      }
      $0.hermesREST.cronJobs = { @Sendable _, _ in jobs }
      $0.hermesREST.cronDeliveryTargets = { @Sendable _ in [] }
    }
    store.exhaustivity = .off

    await store.send(.triggerTapped("job1")) {
      $0.actionInFlightIDs = ["job1"]
    }
    await store.receive(\.jobActionFinished) {
      $0.actionInFlightIDs = []
    }
    await store.receive(\.loadResponse) {
      $0.isRefreshing = false
    }
    #expect(store.state.actionInFlightIDs.isEmpty)
  }
}
