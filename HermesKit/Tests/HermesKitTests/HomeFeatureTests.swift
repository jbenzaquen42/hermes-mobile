import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct HomeFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "http://mac.tailnet:9119")!,
    token: "tok"
  )
  private let now = Date(timeIntervalSince1970: 1_786_563_000)

  @Test func partialFailurePreservesThatCardsStaleValueAndEveryOtherCard() async {
    let gateway = HomeGatewayHealth(
      version: "0.18.0",
      gatewayRunning: true,
      gatewayState: "running",
      activeSessionCount: 2
    )
    let running = HomeRunningSessions(
      sessions: [HomeSessionSummary(id: "s1", title: "Still working")]
    )
    var cards = HomeCards()
    cards.gatewayHealth = HomeCardState(
      value: gateway,
      phase: .loaded,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-60)
    )
    cards.runningSessions = HomeCardState(
      value: running,
      phase: .loaded,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-60)
    )
    let store = TestStore(
      initialState: HomeFeature.State(connection: connection, cards: cards)
    ) {
      HomeFeature()
    } withDependencies: {
      $0.date = .constant(now)
    }

    await store.send(.gatewayHealthResponse(.failure(.request("Status timed out.")))) {
      $0.cards.gatewayHealth.phase = .failed("Status timed out.")
    }

    #expect(store.state.cards.gatewayHealth.value == gateway)
    #expect(store.state.cards.runningSessions.value == running)
    #expect(store.state.cards.runningSessions.phase == .loaded)
  }

  @Test func unsupportedOptionalModuleDoesNotAffectOtherCards() async {
    var cards = HomeCards()
    cards.runningSessions = HomeCardState(
      value: HomeRunningSessions(sessions: [HomeSessionSummary(id: "s1", title: "Run")]),
      phase: .loaded,
      lastSuccessfulRefreshAt: now
    )
    let store = TestStore(
      initialState: HomeFeature.State(connection: connection, cards: cards)
    ) {
      HomeFeature()
    }

    await store.send(.kanbanStatusResponse(.failure(.unsupported))) {
      $0.cards.kanbanStatus.phase = .unsupported
    }

    #expect(store.state.cards.runningSessions.phase == .loaded)
    #expect(store.state.cards.runningSessions.value?.count == 1)
  }

  @Test func pullRefreshMarksEveryCardLoadingAndDisappearCancelsWork() async {
    let clock = TestClock()
    let home = delayedClient(clock: clock)
    let store = TestStore(initialState: HomeFeature.State(connection: connection)) {
      HomeFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hermesHome = home
    }

    await store.send(.pulledToRefresh) {
      $0.isRefreshing = true
      $0.pendingRefreshes = Set(HomeFeature.CardID.allCases)
      $0.cards.gatewayHealth.phase = .loading
      $0.cards.profileModel.phase = .loading
      $0.cards.runningSessions.phase = .loading
      $0.cards.activeProcesses.phase = .loading
      $0.cards.pendingInteractions.phase = .loading
      $0.cards.recentActivity.phase = .loading
      $0.cards.cronAttention.phase = .loading
      $0.cards.kanbanStatus.phase = .loading
      $0.cards.pushHealth.phase = .loading
    }
    await store.send(.onDisappear) {
      $0.isRefreshing = false
      $0.pendingRefreshes = []
    }
  }

  @Test func pollIsVisibleOnly() async {
    let clock = TestClock()
    let hiddenStore = TestStore(initialState: HomeFeature.State(connection: connection)) {
      HomeFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hermesHome = delayedClient(clock: clock)
    }

    await hiddenStore.send(.pollTick)

    var visible = HomeFeature.State(connection: connection)
    visible.isVisible = true
    let visibleStore = TestStore(initialState: visible) {
      HomeFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hermesHome = delayedClient(clock: clock)
    }
    visibleStore.exhaustivity = .off(showSkippedAssertions: false)
    await visibleStore.send(.pollTick) {
      $0.isRefreshing = true
    }
    await visibleStore.send(.onDisappear) {
      $0.isVisible = false
      $0.isRefreshing = false
    }
  }

  @Test func foregroundRefreshesOnlyWhileVisible() async {
    let clock = TestClock()
    let store = TestStore(initialState: HomeFeature.State(connection: connection)) {
      HomeFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hermesHome = delayedClient(clock: clock)
    }

    await store.send(.foreground)

    store.exhaustivity = .off(showSkippedAssertions: false)
    await store.send(.task) {
      $0.isVisible = true
      $0.isRefreshing = true
    }
    await store.send(.foreground)
    #expect(store.state.isRefreshing)
    await store.send(.onDisappear) {
      $0.isVisible = false
      $0.isRefreshing = false
    }
  }

  @Test func localPendingInteractionsReplaceUnsupportedCapability() async {
    let interaction = HomePendingInteraction(
      id: "approval-s1",
      sessionID: "s1",
      kind: .approval,
      title: "Approve command"
    )
    var cards = HomeCards()
    cards.pendingInteractions.phase = .unsupported
    let store = TestStore(
      initialState: HomeFeature.State(connection: connection, cards: cards)
    ) {
      HomeFeature()
    } withDependencies: {
      $0.date = .constant(now)
    }

    await store.send(.pendingInteractionsUpdated([interaction])) {
      $0.cards.pendingInteractions = HomeCardState(
        value: HomePendingInteractions(interactions: [interaction]),
        phase: .loaded,
        lastSuccessfulRefreshAt: self.now
      )
      $0.lastSuccessfulRefreshAt = self.now
    }
  }

  @Test func unsupportedGlobalPendingProbeDoesNotEraseProcessLocalInteractions() async {
    let interaction = HomePendingInteraction(
      id: "approval-s1",
      sessionID: "s1",
      kind: .approval
    )
    var cards = HomeCards()
    cards.pendingInteractions = HomeCardState(
      value: HomePendingInteractions(interactions: [interaction]),
      phase: .loading,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-30)
    )
    let store = TestStore(
      initialState: HomeFeature.State(connection: connection, cards: cards)
    ) {
      HomeFeature()
    }

    await store.send(.pendingInteractionsResponse(.failure(.unsupported))) {
      $0.cards.pendingInteractions.phase = .loaded
    }
    #expect(store.state.cards.pendingInteractions.value?.interactions == [interaction])
  }

  @Test func quickActionsEmitTypedDelegates() async {
    let interaction = HomePendingInteraction(
      id: "clarify-s2",
      sessionID: "s2",
      kind: .clarification
    )
    var cards = HomeCards()
    cards.runningSessions = HomeCardState(
      value: HomeRunningSessions(sessions: [HomeSessionSummary(id: "s1", title: "Active")]),
      phase: .loaded
    )
    cards.pendingInteractions = HomeCardState(
      value: HomePendingInteractions(interactions: [interaction]),
      phase: .loaded
    )
    cards.cronAttention = HomeCardState(value: HomeCronAttention(jobs: []), phase: .loaded)
    cards.kanbanStatus = HomeCardState(value: HomeKanbanStatus(), phase: .loaded)
    let store = TestStore(
      initialState: HomeFeature.State(connection: connection, cards: cards)
    ) {
      HomeFeature()
    }

    await store.send(.newChatTapped)
    await store.receive(\.delegate.newChat)
    await store.send(.returnToActiveChatTapped)
    await store.receive(\.delegate.openSession)
    await store.send(.createKanbanTaskTapped)
    await store.receive(\.delegate.createKanbanTask)
    await store.send(.createScheduledJobTapped)
    await store.receive(\.delegate.createScheduledJob)
    await store.send(.pendingInteractionTapped(id: interaction.id))
    await store.receive(\.delegate.openPendingInteraction)
  }

  @Test func testPingIsGatedByPushHealth() async {
    let calls = LockIsolated(0)
    var cards = HomeCards()
    cards.pushHealth = HomeCardState(
      value: HomePushHealth(
        pluginStatus: .ready,
        authorizationStatus: .authorized,
        canSendTestPing: true
      ),
      phase: .loaded
    )
    let store = TestStore(
      initialState: HomeFeature.State(connection: connection, cards: cards)
    ) {
      HomeFeature()
    } withDependencies: {
      $0.hermesHome.sendTestPing = { @Sendable _ in calls.withValue { $0 += 1 } }
    }

    await store.send(.sendTestPingTapped) {
      $0.testPingStatus = .sending
    }
    await store.receive(\.testPingResponse.success) {
      $0.testPingStatus = .sent
    }
    #expect(calls.value == 1)
  }

  private func delayedClient(clock: TestClock<Duration>) -> HermesHomeClient {
    HermesHomeClient(
      gatewayHealth: { @Sendable _ in
        try await clock.sleep(for: .seconds(1_000))
        return HomeGatewayHealth(gatewayRunning: true)
      },
      profileModel: { @Sendable _, profile in
        try await clock.sleep(for: .seconds(1_000))
        return HomeProfileModel(profileName: profile)
      },
      runningSessions: { @Sendable _ in
        try await clock.sleep(for: .seconds(1_000))
        return HomeRunningSessions(sessions: [])
      },
      activeProcesses: { @Sendable _, _ in
        try await clock.sleep(for: .seconds(1_000))
        return HomeActiveProcesses(activeCount: 0)
      },
      pendingInteractions: { @Sendable _ in
        try await clock.sleep(for: .seconds(1_000))
        return HomePendingInteractions(interactions: [])
      },
      recentActivity: { @Sendable _ in
        try await clock.sleep(for: .seconds(1_000))
        return HomeRecentActivity(items: [])
      },
      cronAttention: { @Sendable _, _ in
        try await clock.sleep(for: .seconds(1_000))
        return HomeCronAttention(jobs: [])
      },
      kanbanStatus: { @Sendable _ in
        try await clock.sleep(for: .seconds(1_000))
        return HomeKanbanStatus()
      },
      pushHealth: { @Sendable _ in
        try await clock.sleep(for: .seconds(1_000))
        return HomePushHealth(
          pluginStatus: .unknown,
          authorizationStatus: .notDetermined,
          canSendTestPing: false
        )
      },
      sendTestPing: { @Sendable _ in }
    )
  }
}

extension RESTTransportSuite {
  struct HermesHomeClientTests {
    private let baseURL = URL(string: "http://test.local:9119")!
    private var connection: ServerConnection {
      ServerConnection(baseURL: baseURL, token: "tok")
    }

    private func makeClient(push: PushClient = .testValue) -> HermesHomeClient {
      let config = URLSessionConfiguration.ephemeral
      config.protocolClasses = [MockURLProtocol.self]
      return .live(session: URLSession(configuration: config), push: push)
    }

    @Test func activeProcessesUsesNonSensitiveStatusAggregate() async throws {
      MockURLProtocol.set(json: #"{"active_agents":3}"#)

      let value = try await makeClient().activeProcesses(connection, "default")

      #expect(value.activeCount == 3)
      #expect(value.processes.isEmpty)
      #expect(MockURLProtocol.lastRequest?.url?.path == "/api/status")
    }

    @Test func profileModelScopesCustomProfile() async throws {
      MockURLProtocol.set(json: #"{"model":"claude-sonnet","provider":"anthropic"}"#)

      let value = try await makeClient().profileModel(connection, "research")

      #expect(value == HomeProfileModel(
        profileName: "research",
        model: "claude-sonnet",
        provider: "anthropic"
      ))
      #expect(MockURLProtocol.lastRequest?.url?.path == "/api/model/info")
      #expect(MockURLProtocol.lastRequest?.url?.query == "profile=research")
    }

    @Test func kanbanDecodesOnlyAttentionColumns() async throws {
      MockURLProtocol.set(json: #"""
      {"columns":[
        {"name":"todo","tasks":[{"id":"t0","title":"Later","status":"todo"}]},
        {"name":"running","tasks":[{"id":"t1","title":"Build","status":"running"}]},
        {"name":"blocked","tasks":[{"id":"t2","title":"Decision","status":"blocked"}]},
        {"name":"review","tasks":[{"id":"t3","title":"Check","status":"review"}]}
      ]}
      """#)

      let value = try await makeClient().kanbanStatus(connection)

      #expect(value.running.map(\.id) == ["t1"])
      #expect(value.blocked.map(\.id) == ["t2"])
      #expect(value.review.map(\.id) == ["t3"])
      #expect(MockURLProtocol.lastRequest?.url?.path == "/api/plugins/kanban/board")
    }

    @Test func missingKanbanIsCapabilityGated() async {
      MockURLProtocol.set(status: 404)

      await #expect(throws: HomeClientError.unsupported) {
        _ = try await makeClient().kanbanStatus(connection)
      }
    }
  }
}
