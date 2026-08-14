import Foundation

/// The lifecycle of one independently-loaded Home card.
///
/// `HomeCardState` stores the value separately so a failed refresh can surface the error
/// without discarding the last usable summary.
public enum HomeCardPhase: Equatable, Sendable {
  case idle
  case loading
  case loaded
  case failed(String)
  case unsupported
}

public struct HomeCardState<Value: Equatable & Sendable>: Equatable, Sendable {
  public var value: Value?
  public var phase: HomeCardPhase
  public var lastSuccessfulRefreshAt: Date?

  public init(
    value: Value? = nil,
    phase: HomeCardPhase = .idle,
    lastSuccessfulRefreshAt: Date? = nil
  ) {
    self.value = value
    self.phase = phase
    self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
  }

  public var isLoading: Bool { phase == .loading }
  public var errorMessage: String? {
    guard case let .failed(message) = phase else { return nil }
    return message
  }
  public var isUnsupported: Bool { phase == .unsupported }
  public var hasLoadedValue: Bool { value != nil }

  public mutating func beginLoading() {
    phase = .loading
  }

  public mutating func succeed(with value: Value, at date: Date) {
    self.value = value
    phase = .loaded
    lastSuccessfulRefreshAt = date
  }

  public mutating func fail(with message: String) {
    phase = .failed(message)
  }

  public mutating func markUnsupported() {
    value = nil
    phase = .unsupported
  }
}

public struct HomeCards: Equatable, Sendable {
  public var gatewayHealth: HomeCardState<HomeGatewayHealth>
  public var profileModel: HomeCardState<HomeProfileModel>
  public var runningSessions: HomeCardState<HomeRunningSessions>
  public var activeProcesses: HomeCardState<HomeActiveProcesses>
  public var pendingInteractions: HomeCardState<HomePendingInteractions>
  public var recentActivity: HomeCardState<HomeRecentActivity>
  public var cronAttention: HomeCardState<HomeCronAttention>
  public var kanbanStatus: HomeCardState<HomeKanbanStatus>
  public var pushHealth: HomeCardState<HomePushHealth>

  public init(
    gatewayHealth: HomeCardState<HomeGatewayHealth> = .init(),
    profileModel: HomeCardState<HomeProfileModel> = .init(),
    runningSessions: HomeCardState<HomeRunningSessions> = .init(),
    activeProcesses: HomeCardState<HomeActiveProcesses> = .init(),
    pendingInteractions: HomeCardState<HomePendingInteractions> = .init(),
    recentActivity: HomeCardState<HomeRecentActivity> = .init(),
    cronAttention: HomeCardState<HomeCronAttention> = .init(),
    kanbanStatus: HomeCardState<HomeKanbanStatus> = .init(),
    pushHealth: HomeCardState<HomePushHealth> = .init()
  ) {
    self.gatewayHealth = gatewayHealth
    self.profileModel = profileModel
    self.runningSessions = runningSessions
    self.activeProcesses = activeProcesses
    self.pendingInteractions = pendingInteractions
    self.recentActivity = recentActivity
    self.cronAttention = cronAttention
    self.kanbanStatus = kanbanStatus
    self.pushHealth = pushHealth
  }
}

public struct HomeGatewayHealth: Equatable, Sendable {
  public var version: String?
  public var gatewayRunning: Bool
  public var gatewayState: String?
  public var activeSessionCount: Int?

  public init(
    version: String? = nil,
    gatewayRunning: Bool,
    gatewayState: String? = nil,
    activeSessionCount: Int? = nil
  ) {
    self.version = version
    self.gatewayRunning = gatewayRunning
    self.gatewayState = gatewayState
    self.activeSessionCount = activeSessionCount
  }
}

public struct HomeProfileModel: Equatable, Sendable {
  public var profileName: String
  public var model: String?
  public var provider: String?

  public init(profileName: String, model: String? = nil, provider: String? = nil) {
    self.profileName = profileName
    self.model = model
    self.provider = provider
  }
}

public struct HomeSessionSummary: Equatable, Sendable, Identifiable {
  public var id: Session.ID
  public var title: String
  public var updatedAt: Date?

  public init(id: Session.ID, title: String, updatedAt: Date? = nil) {
    self.id = id
    self.title = title
    self.updatedAt = updatedAt
  }

  public init(session: Session) {
    self.init(id: session.id, title: session.displayName, updatedAt: session.updatedAt)
  }
}

public struct HomeRunningSessions: Equatable, Sendable {
  public var sessions: [HomeSessionSummary]

  public init(sessions: [HomeSessionSummary]) {
    self.sessions = sessions
  }

  public var count: Int { sessions.count }
}

/// Non-sensitive delegate/agent process information. Hermes currently reports the aggregate
/// `active_agents` count on `/api/status`; `processes` is ready for a future safe detail API
/// and intentionally never contains commands, arguments, environment values, or paths.
public struct HomeActiveProcess: Equatable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var profileName: String?
  public var status: String?

  public init(
    id: String,
    title: String,
    profileName: String? = nil,
    status: String? = nil
  ) {
    self.id = id
    self.title = title
    self.profileName = profileName
    self.status = status
  }
}

public struct HomeActiveProcesses: Equatable, Sendable {
  public var activeCount: Int
  public var processes: [HomeActiveProcess]

  public init(activeCount: Int, processes: [HomeActiveProcess] = []) {
    self.activeCount = activeCount
    self.processes = processes
  }
}

public struct HomePendingInteraction: Equatable, Sendable, Identifiable {
  public enum Kind: Equatable, Sendable {
    case approval
    case clarification
  }

  public var id: String
  public var sessionID: Session.ID
  public var kind: Kind
  public var title: String?

  public init(id: String, sessionID: Session.ID, kind: Kind, title: String? = nil) {
    self.id = id
    self.sessionID = sessionID
    self.kind = kind
    self.title = title
  }
}

public struct HomePendingInteractions: Equatable, Sendable {
  public var interactions: [HomePendingInteraction]

  public init(interactions: [HomePendingInteraction]) {
    self.interactions = interactions
  }

  public var count: Int { interactions.count }
}

public struct HomeRecentActivityItem: Equatable, Sendable, Identifiable {
  public enum Outcome: Equatable, Sendable {
    case completed
    case failed
  }

  public var id: String
  public var sessionID: Session.ID
  public var title: String
  public var outcome: Outcome
  public var occurredAt: Date?

  public init(
    id: String,
    sessionID: Session.ID,
    title: String,
    outcome: Outcome,
    occurredAt: Date? = nil
  ) {
    self.id = id
    self.sessionID = sessionID
    self.title = title
    self.outcome = outcome
    self.occurredAt = occurredAt
  }
}

public struct HomeRecentActivity: Equatable, Sendable {
  public var items: [HomeRecentActivityItem]

  public init(items: [HomeRecentActivityItem]) {
    self.items = items
  }

  public var completionCount: Int { items.count { $0.outcome == .completed } }
  public var failureCount: Int { items.count { $0.outcome == .failed } }
}

public struct HomeCronJobAttention: Equatable, Sendable, Identifiable {
  public enum Reason: Equatable, Sendable {
    case failed
    case paused
    case overdue
  }

  public var id: CronJob.ID
  public var title: String
  public var reason: Reason
  public var nextRunAt: Date?
  public var lastRunAt: Date?

  public init(
    id: CronJob.ID,
    title: String,
    reason: Reason,
    nextRunAt: Date? = nil,
    lastRunAt: Date? = nil
  ) {
    self.id = id
    self.title = title
    self.reason = reason
    self.nextRunAt = nextRunAt
    self.lastRunAt = lastRunAt
  }
}

public struct HomeCronAttention: Equatable, Sendable {
  public var jobs: [HomeCronJobAttention]

  public init(jobs: [HomeCronJobAttention]) {
    self.jobs = jobs
  }

  public var count: Int { jobs.count }
}

public struct HomeKanbanItem: Equatable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var status: String

  public init(id: String, title: String, status: String) {
    self.id = id
    self.title = title
    self.status = status
  }
}

public struct HomeKanbanStatus: Equatable, Sendable {
  public var running: [HomeKanbanItem]
  public var blocked: [HomeKanbanItem]
  public var review: [HomeKanbanItem]

  public init(
    running: [HomeKanbanItem] = [],
    blocked: [HomeKanbanItem] = [],
    review: [HomeKanbanItem] = []
  ) {
    self.running = running
    self.blocked = blocked
    self.review = review
  }

  public var runningCount: Int { running.count }
  public var blockedCount: Int { blocked.count }
  public var reviewCount: Int { review.count }
}

public struct HomePushHealth: Equatable, Sendable {
  public var pluginStatus: PushPluginStatus
  public var authorizationStatus: PushAuthorizationStatus
  public var canSendTestPing: Bool

  public init(
    pluginStatus: PushPluginStatus,
    authorizationStatus: PushAuthorizationStatus,
    canSendTestPing: Bool
  ) {
    self.pluginStatus = pluginStatus
    self.authorizationStatus = authorizationStatus
    self.canSendTestPing = canSendTestPing
  }
}
