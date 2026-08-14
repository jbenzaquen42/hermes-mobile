import ComposableArchitecture
import Foundation

@Reducer
public struct HomeFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    public var cards: HomeCards
    public var selectedProfileName: String
    public var isVisible: Bool
    public var isRefreshing: Bool
    public var lastSuccessfulRefreshAt: Date?
    public var testPingStatus: TestPingStatus
    var pendingRefreshes: Set<CardID>

    public init(
      connection: ServerConnection,
      cards: HomeCards = .init(),
      selectedProfileName: String = SessionListFeature.State.defaultProfileName,
      isVisible: Bool = false,
      isRefreshing: Bool = false,
      lastSuccessfulRefreshAt: Date? = nil,
      testPingStatus: TestPingStatus = .idle
    ) {
      self.connection = connection
      self.cards = cards
      self.selectedProfileName = selectedProfileName
      self.isVisible = isVisible
      self.isRefreshing = isRefreshing
      self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
      self.testPingStatus = testPingStatus
      self.pendingRefreshes = []
    }
  }

  public enum TestPingStatus: Equatable, Sendable {
    case idle
    case sending
    case sent
    case failed(String)
  }

  public enum Action {
    case task
    case onDisappear
    case foreground
    case pulledToRefresh
    case pollTick

    case gatewayHealthResponse(Result<HomeGatewayHealth, HomeClientError>)
    case profileModelResponse(Result<HomeProfileModel, HomeClientError>)
    case runningSessionsResponse(Result<HomeRunningSessions, HomeClientError>)
    case activeProcessesResponse(Result<HomeActiveProcesses, HomeClientError>)
    case pendingInteractionsResponse(Result<HomePendingInteractions, HomeClientError>)
    case recentActivityResponse(Result<HomeRecentActivity, HomeClientError>)
    case cronAttentionResponse(Result<HomeCronAttention, HomeClientError>)
    case kanbanStatusResponse(Result<HomeKanbanStatus, HomeClientError>)
    case pushHealthResponse(Result<HomePushHealth, HomeClientError>)

    /// Process-local interaction events can be supplied by AppFeature even though the
    /// server has no global pending-interaction read endpoint.
    case pendingInteractionsUpdated([HomePendingInteraction])

    case newChatTapped
    case returnToActiveChatTapped
    case createKanbanTaskTapped
    case createScheduledJobTapped
    case pendingInteractionTapped(id: HomePendingInteraction.ID)
    case sendTestPingTapped
    case testPingResponse(Result<Void, HomeClientError>)
    case delegate(Delegate)

    @CasePathable
    public enum Delegate {
      case newChat
      case openSession(id: Session.ID)
      case createKanbanTask
      case createScheduledJob
      case openPendingInteraction(HomePendingInteraction)
    }
  }

  enum CardID: Hashable, CaseIterable {
    case gatewayHealth
    case profileModel
    case runningSessions
    case activeProcesses
    case pendingInteractions
    case recentActivity
    case cronAttention
    case kanbanStatus
    case pushHealth
  }

  private enum CancelID: Hashable {
    case poll
    case card(CardID)
    case testPing
  }

  /// Home is operational context, not a live transcript; thirty seconds keeps it fresh
  /// without duplicating the Chats screen's ten-second working-state poll.
  public static let pollInterval: Duration = .seconds(30)

  @Dependency(\.hermesHome) var home
  @Dependency(\.preferences) var preferences
  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        guard !state.isVisible else { return .none }
        state.isVisible = true
        state.selectedProfileName =
          preferences.loadSelectedProfileID() ?? SessionListFeature.State.defaultProfileName
        return .merge(
          refresh(&state),
          .run { [clock, interval = Self.pollInterval] send in
            while true {
              try await clock.sleep(for: interval)
              await send(.pollTick)
            }
          }
          .cancellable(id: CancelID.poll, cancelInFlight: true)
        )

      case .onDisappear:
        state.isVisible = false
        state.isRefreshing = false
        state.pendingRefreshes = []
        return .merge(
          .cancel(id: CancelID.poll),
          .cancel(id: CancelID.card(.gatewayHealth)),
          .cancel(id: CancelID.card(.profileModel)),
          .cancel(id: CancelID.card(.runningSessions)),
          .cancel(id: CancelID.card(.activeProcesses)),
          .cancel(id: CancelID.card(.pendingInteractions)),
          .cancel(id: CancelID.card(.recentActivity)),
          .cancel(id: CancelID.card(.cronAttention)),
          .cancel(id: CancelID.card(.kanbanStatus)),
          .cancel(id: CancelID.card(.pushHealth)),
          .cancel(id: CancelID.testPing)
        )

      case .foreground:
        guard state.isVisible else { return .none }
        state.selectedProfileName =
          preferences.loadSelectedProfileID() ?? SessionListFeature.State.defaultProfileName
        return refresh(&state)

      case .pulledToRefresh:
        state.selectedProfileName =
          preferences.loadSelectedProfileID() ?? SessionListFeature.State.defaultProfileName
        return refresh(&state)

      case .pollTick:
        guard state.isVisible, !state.isRefreshing else { return .none }
        return refresh(&state)

      case let .gatewayHealthResponse(result):
        let successfulAt = apply(result, to: &state.cards.gatewayHealth)
        finish(.gatewayHealth, successfulAt: successfulAt, state: &state)
        return .none

      case let .profileModelResponse(result):
        let successfulAt = apply(result, to: &state.cards.profileModel)
        finish(.profileModel, successfulAt: successfulAt, state: &state)
        return .none

      case let .runningSessionsResponse(result):
        let successfulAt = apply(result, to: &state.cards.runningSessions)
        finish(.runningSessions, successfulAt: successfulAt, state: &state)
        return .none

      case let .activeProcessesResponse(result):
        let successfulAt = apply(result, to: &state.cards.activeProcesses)
        finish(.activeProcesses, successfulAt: successfulAt, state: &state)
        return .none

      case let .pendingInteractionsResponse(result):
        let successfulAt: Date?
        if case .failure(.unsupported) = result,
           state.cards.pendingInteractions.hasLoadedValue {
          // AppFeature may already have supplied process-local approval summaries. The lack
          // of a server-wide endpoint must not erase data the running app does know.
          state.cards.pendingInteractions.phase = .loaded
          successfulAt = nil
        } else {
          successfulAt = apply(result, to: &state.cards.pendingInteractions)
        }
        finish(.pendingInteractions, successfulAt: successfulAt, state: &state)
        return .none

      case let .recentActivityResponse(result):
        let successfulAt = apply(result, to: &state.cards.recentActivity)
        finish(.recentActivity, successfulAt: successfulAt, state: &state)
        return .none

      case let .cronAttentionResponse(result):
        let successfulAt = apply(result, to: &state.cards.cronAttention)
        finish(.cronAttention, successfulAt: successfulAt, state: &state)
        return .none

      case let .kanbanStatusResponse(result):
        let successfulAt = apply(result, to: &state.cards.kanbanStatus)
        finish(.kanbanStatus, successfulAt: successfulAt, state: &state)
        return .none

      case let .pushHealthResponse(result):
        let successfulAt = apply(result, to: &state.cards.pushHealth)
        finish(.pushHealth, successfulAt: successfulAt, state: &state)
        return .none

      case let .pendingInteractionsUpdated(interactions):
        state.cards.pendingInteractions.succeed(
          with: HomePendingInteractions(interactions: interactions),
          at: now
        )
        state.lastSuccessfulRefreshAt = maxDate(state.lastSuccessfulRefreshAt, now)
        state.pendingRefreshes.remove(.pendingInteractions)
        state.isRefreshing = !state.pendingRefreshes.isEmpty
        return .cancel(id: CancelID.card(.pendingInteractions))

      case .newChatTapped:
        return .send(.delegate(.newChat))

      case .returnToActiveChatTapped:
        guard let id = state.cards.runningSessions.value?.sessions.first?.id else { return .none }
        return .send(.delegate(.openSession(id: id)))

      case .createKanbanTaskTapped:
        guard
          state.cards.kanbanStatus.hasLoadedValue,
          !state.cards.kanbanStatus.isUnsupported
        else { return .none }
        return .send(.delegate(.createKanbanTask))

      case .createScheduledJobTapped:
        guard
          state.cards.cronAttention.hasLoadedValue,
          !state.cards.cronAttention.isUnsupported
        else { return .none }
        return .send(.delegate(.createScheduledJob))

      case let .pendingInteractionTapped(id):
        guard let interaction = state.cards.pendingInteractions.value?.interactions
          .first(where: { $0.id == id })
        else { return .none }
        return .send(.delegate(.openPendingInteraction(interaction)))

      case .sendTestPingTapped:
        guard
          state.cards.pushHealth.value?.canSendTestPing == true,
          state.testPingStatus != .sending
        else { return .none }
        state.testPingStatus = .sending
        return .run { [home, connection = state.connection] send in
          await send(.testPingResponse(await homeResult { try await home.sendTestPing(connection) }))
        }
        .cancellable(id: CancelID.testPing, cancelInFlight: true)

      case .testPingResponse(.success):
        state.testPingStatus = .sent
        return .none

      case let .testPingResponse(.failure(error)):
        state.testPingStatus = .failed(error.message)
        return .none

      case .delegate:
        return .none
      }
    }
  }

  private func refresh(_ state: inout State) -> Effect<Action> {
    state.isRefreshing = true
    state.pendingRefreshes = Set(CardID.allCases)
    state.cards.gatewayHealth.beginLoading()
    state.cards.profileModel.beginLoading()
    state.cards.runningSessions.beginLoading()
    state.cards.activeProcesses.beginLoading()
    state.cards.pendingInteractions.beginLoading()
    state.cards.recentActivity.beginLoading()
    state.cards.cronAttention.beginLoading()
    state.cards.kanbanStatus.beginLoading()
    state.cards.pushHealth.beginLoading()

    let connection = state.connection
    let profileName = state.selectedProfileName
    let refreshDate = now

    return .merge(
      .run { [home] send in
        await send(.gatewayHealthResponse(await homeResult {
          try await home.gatewayHealth(connection)
        }))
      }
      .cancellable(id: CancelID.card(.gatewayHealth), cancelInFlight: true),
      .run { [home] send in
        await send(.profileModelResponse(await homeResult {
          try await home.profileModel(connection, profileName)
        }))
      }
      .cancellable(id: CancelID.card(.profileModel), cancelInFlight: true),
      .run { [home] send in
        await send(.runningSessionsResponse(await homeResult {
          try await home.runningSessions(connection)
        }))
      }
      .cancellable(id: CancelID.card(.runningSessions), cancelInFlight: true),
      .run { [home] send in
        await send(.activeProcessesResponse(await homeResult {
          try await home.activeProcesses(connection, profileName)
        }))
      }
      .cancellable(id: CancelID.card(.activeProcesses), cancelInFlight: true),
      .run { [home] send in
        await send(.pendingInteractionsResponse(await homeResult {
          try await home.pendingInteractions(connection)
        }))
      }
      .cancellable(id: CancelID.card(.pendingInteractions), cancelInFlight: true),
      .run { [home] send in
        await send(.recentActivityResponse(await homeResult {
          try await home.recentActivity(connection)
        }))
      }
      .cancellable(id: CancelID.card(.recentActivity), cancelInFlight: true),
      .run { [home] send in
        await send(.cronAttentionResponse(await homeResult {
          try await home.cronAttention(connection, refreshDate)
        }))
      }
      .cancellable(id: CancelID.card(.cronAttention), cancelInFlight: true),
      .run { [home] send in
        await send(.kanbanStatusResponse(await homeResult {
          try await home.kanbanStatus(connection)
        }))
      }
      .cancellable(id: CancelID.card(.kanbanStatus), cancelInFlight: true),
      .run { [home] send in
        await send(.pushHealthResponse(await homeResult {
          try await home.pushHealth(connection)
        }))
      }
      .cancellable(id: CancelID.card(.pushHealth), cancelInFlight: true)
    )
  }

  private func apply<Value>(
    _ result: Result<Value, HomeClientError>,
    to cardState: inout HomeCardState<Value>
  ) -> Date? where Value: Equatable & Sendable {
    switch result {
    case let .success(value):
      let date = now
      cardState.succeed(with: value, at: date)
      return date
    case .failure(.unsupported):
      cardState.markUnsupported()
      return nil
    case let .failure(error):
      cardState.fail(with: error.message)
      return nil
    }
  }

  private func finish(_ card: CardID, successfulAt: Date?, state: inout State) {
    if let successfulAt {
      state.lastSuccessfulRefreshAt = maxDate(state.lastSuccessfulRefreshAt, successfulAt)
    }
    state.pendingRefreshes.remove(card)
    state.isRefreshing = !state.pendingRefreshes.isEmpty
  }
}

private func homeResult<Value: Sendable>(
  _ operation: @Sendable () async throws -> Value
) async -> Result<Value, HomeClientError> {
  do {
    return .success(try await operation())
  } catch {
    return .failure(HomeClientError(error))
  }
}

private func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
  guard let lhs else { return rhs }
  return max(lhs, rhs)
}
