import ComposableArchitecture
import DependenciesMacros
import Foundation

public enum HomeClientError: Error, Equatable, Sendable {
  /// The connected Hermes version does not expose this optional module/surface.
  case unsupported
  case request(String)

  public var message: String {
    switch self {
    case .unsupported: "Not supported by this Hermes server."
    case let .request(message): message
    }
  }

  init(_ error: any Error) {
    if let error = error as? HomeClientError {
      self = error
    } else if let error = error as? RESTError {
      self = error == .notFound ? .unsupported : .request(error.message)
    } else if let error = error as? GatewayError {
      self = error.isUnsupportedOperation ? .unsupported : .request(error.message)
    } else {
      self = .request("Couldn’t refresh this card.")
    }
  }
}

/// Read-only, independently callable data sources for Home.
///
/// The client composes the existing status/session/cron/push surfaces where possible and
/// owns only Home-specific summary endpoints (model info and Kanban). Every closure is
/// separate so one optional module failing cannot suppress any other card.
@DependencyClient
public struct HermesHomeClient: Sendable {
  public var gatewayHealth: @Sendable (_ connection: ServerConnection) async throws -> HomeGatewayHealth
  public var profileModel: @Sendable (_ connection: ServerConnection, _ profileName: String) async throws -> HomeProfileModel
  public var runningSessions: @Sendable (_ connection: ServerConnection) async throws -> HomeRunningSessions
  public var activeProcesses: @Sendable (_ connection: ServerConnection, _ profileName: String) async throws -> HomeActiveProcesses
  public var pendingInteractions: @Sendable (_ connection: ServerConnection) async throws -> HomePendingInteractions
  public var recentActivity: @Sendable (_ connection: ServerConnection) async throws -> HomeRecentActivity
  public var cronAttention: @Sendable (_ connection: ServerConnection, _ now: Date) async throws -> HomeCronAttention
  public var kanbanStatus: @Sendable (_ connection: ServerConnection) async throws -> HomeKanbanStatus
  public var pushHealth: @Sendable (_ connection: ServerConnection) async throws -> HomePushHealth
  public var sendTestPing: @Sendable (_ connection: ServerConnection) async throws -> Void
}

public extension HermesHomeClient {
  static func live(
    session: URLSession = .shared,
    push: PushClient = .liveValue
  ) -> HermesHomeClient {
    let rest = HermesRESTClient.live(session: session)

    return HermesHomeClient(
      gatewayHealth: { connection in
        do {
          let status = try await rest.status(connection.baseURL)
          return HomeGatewayHealth(
            version: status.version,
            gatewayRunning: status.gatewayRunning ?? false,
            gatewayState: status.gatewayState,
            activeSessionCount: status.activeSessions
          )
        } catch {
          throw HomeClientError(error)
        }
      },
      profileModel: { connection, profileName in
        do {
          let query = profileName == SessionListFeature.State.defaultProfileName
            ? []
            : [URLQueryItem(name: "profile", value: profileName)]
          let url = try makeURL(connection.baseURL, "/api/model/info", query: query)
          let info: HomeModelInfoDTO = try await get(
            url, token: connection.token, session: session
          )
          return HomeProfileModel(
            profileName: profileName,
            model: info.model?.trimmedNonEmpty,
            provider: info.provider?.trimmedNonEmpty
          )
        } catch {
          throw HomeClientError(error)
        }
      },
      runningSessions: { connection in
        do {
          let sessions = try await rest.sessions(connection, 100, 0, .recent)
          return HomeRunningSessions(
            sessions: sessions
              .filter { $0.isActive == true }
              .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
              .map(HomeSessionSummary.init(session:))
          )
        } catch {
          throw HomeClientError(error)
        }
      },
      activeProcesses: { connection, profileName in
        do {
          let query = profileName == SessionListFeature.State.defaultProfileName
            ? []
            : [URLQueryItem(name: "profile", value: profileName)]
          let url = try makeURL(connection.baseURL, "/api/status", query: query)
          let status: HomeActiveAgentsDTO = try await get(
            url, token: connection.token, session: session
          )
          // `/api/status` deliberately exposes only an aggregate. Do not infer or persist
          // process commands, arguments, workspaces, or environment data.
          return HomeActiveProcesses(activeCount: max(0, status.activeAgents ?? 0))
        } catch {
          throw HomeClientError(error)
        }
      },
      pendingInteractions: { _ in
        // Approval/clarification requests are currently ephemeral per-chat gateway events;
        // Hermes has no server-wide read endpoint that can reconstruct them safely.
        // AppFeature may inject the process-local summaries it already owns. Until then the
        // card is explicitly capability-gated instead of reporting a misleading empty list.
        throw HomeClientError.unsupported
      },
      recentActivity: { connection in
        do {
          let sessions = try await rest.sessions(connection, 100, 0, .recent)
          // Cron is an optional enrichment: it is the only existing REST summary that carries
          // a terminal failure signal. Its absence must not erase ordinary completions.
          let jobs = (try? await rest.cronJobs(connection, nil)) ?? []
          let jobsByID = Dictionary(jobs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
          let newestCronSessionByJob = sessions
            .filter(\.isCron)
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .reduce(into: [String: Session.ID]()) { newest, session in
              guard let jobID = CronJob.jobID(fromSessionID: session.id), newest[jobID] == nil
              else { return }
              newest[jobID] = session.id
            }
          let items = sessions
            .filter { $0.isActive != true }
            .map { session -> HomeRecentActivityItem in
              let jobID = CronJob.jobID(fromSessionID: session.id)
              let failed = jobID.flatMap { jobsByID[$0] }.map(homeCronJobFailed) == true
                && jobID.flatMap { newestCronSessionByJob[$0] } == session.id
              return HomeRecentActivityItem(
                id: session.id,
                sessionID: session.id,
                title: session.displayName,
                outcome: failed ? .failed : .completed,
                occurredAt: session.updatedAt
              )
            }
            .sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }
          return HomeRecentActivity(items: Array(items.prefix(6)))
        } catch {
          throw HomeClientError(error)
        }
      },
      cronAttention: { connection, now in
        do {
          let jobs = try await rest.cronJobs(connection, nil)
          return HomeCronAttention(
            jobs: jobs.compactMap { job in
              let reason: HomeCronJobAttention.Reason?
              if homeCronJobFailed(job) {
                reason = .failed
              } else if job.isPaused || job.enabled == false || job.effectiveState == "disabled" {
                reason = .paused
              } else if let next = job.nextRunAt, next < now {
                reason = .overdue
              } else {
                reason = nil
              }
              return reason.map {
                HomeCronJobAttention(
                  id: job.id,
                  title: job.title,
                  reason: $0,
                  nextRunAt: job.nextRunAt,
                  lastRunAt: job.lastRunAt
                )
              }
            }
          )
        } catch {
          throw HomeClientError(error)
        }
      },
      kanbanStatus: { connection in
        do {
          let url = try makeURL(connection.baseURL, "/api/plugins/kanban/board")
          let board: HomeKanbanBoardDTO = try await get(
            url, token: connection.token, session: session
          )
          func items(in status: String) -> [HomeKanbanItem] {
            guard let column = board.columns.first(where: { $0.name == status }) else { return [] }
            return column.tasks.map {
              HomeKanbanItem(id: $0.id, title: $0.title, status: $0.status ?? status)
            }
          }
          return HomeKanbanStatus(
            running: items(in: "running"),
            blocked: items(in: "blocked"),
            review: items(in: "review")
          )
        } catch {
          throw HomeClientError(error)
        }
      },
      pushHealth: { connection in
        do {
          async let plugin = rest.pushPluginStatus(connection)
          async let authorization = push.authorizationStatus()
          let (pluginStatus, authorizationStatus) = try await (plugin, authorization)
          let authorized = authorizationStatus == .authorized || authorizationStatus == .provisional
          return HomePushHealth(
            pluginStatus: pluginStatus,
            authorizationStatus: authorizationStatus,
            canSendTestPing: pluginStatus == .ready && authorized
          )
        } catch {
          throw HomeClientError(error)
        }
      },
      sendTestPing: { connection in
        do {
          try await rest.sendTestPush(connection)
        } catch {
          throw HomeClientError(error)
        }
      }
    )
  }
}

extension HermesHomeClient: DependencyKey {
  public static var liveValue: HermesHomeClient { .live() }
  public static var testValue: HermesHomeClient { HermesHomeClient() }
}

public extension DependencyValues {
  var hermesHome: HermesHomeClient {
    get { self[HermesHomeClient.self] }
    set { self[HermesHomeClient.self] = newValue }
  }
}

private struct HomeModelInfoDTO: Decodable {
  var model: String?
  var provider: String?
}

private struct HomeActiveAgentsDTO: Decodable {
  var activeAgents: Int?

  enum CodingKeys: String, CodingKey {
    case activeAgents = "active_agents"
  }
}

private struct HomeKanbanBoardDTO: Decodable {
  var columns: [Column]

  struct Column: Decodable {
    var name: String
    var tasks: [Task]
  }

  struct Task: Decodable {
    var id: String
    var title: String
    var status: String?

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = (try? container.decode(String.self, forKey: .id)) ?? ""
      title = (try? container.decode(String.self, forKey: .title))?.trimmedNonEmpty ?? id
      status = try? container.decodeIfPresent(String.self, forKey: .status)
    }

    private enum CodingKeys: String, CodingKey { case id, title, status }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    columns = (try? container.decode([Column].self, forKey: .columns)) ?? []
  }

  private enum CodingKeys: String, CodingKey { case columns }
}

private func homeCronJobFailed(_ job: CronJob) -> Bool {
  let state = job.effectiveState.lowercased()
  let status = job.lastStatus?.lowercased() ?? ""
  return state == "error" || state == "failed"
    || status.contains("error") || status.contains("fail")
}
