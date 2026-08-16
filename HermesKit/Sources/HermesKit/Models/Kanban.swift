import Foundation

/// One Kanban card from the native plugin's board endpoint.
public struct KanbanTask: Equatable, Sendable, Identifiable, Decodable {
  public var id: String
  public var title: String
  public var body: String?
  public var status: String
  public var assignee: String?
  public var priority: Int?
  public var tenant: String?
  public var createdAt: Date?
  public var latestSummary: String?
  public var commentCount: Int?
  public var startedAt: Date?
  public var workerPID: Int?
  public var lastHeartbeatAt: Date?
  public var progress: KanbanTaskProgress?

  public init(
    id: String,
    title: String,
    body: String? = nil,
    status: String,
    assignee: String? = nil,
    priority: Int? = nil,
    tenant: String? = nil,
    createdAt: Date? = nil,
    latestSummary: String? = nil,
    commentCount: Int? = nil,
    startedAt: Date? = nil,
    workerPID: Int? = nil,
    lastHeartbeatAt: Date? = nil,
    progress: KanbanTaskProgress? = nil
  ) {
    self.id = id
    self.title = title
    self.body = body
    self.status = status
    self.assignee = assignee
    self.priority = priority
    self.tenant = tenant
    self.createdAt = createdAt
    self.latestSummary = latestSummary
    self.commentCount = commentCount
    self.startedAt = startedAt
    self.workerPID = workerPID
    self.lastHeartbeatAt = lastHeartbeatAt
    self.progress = progress
  }

  enum CodingKeys: String, CodingKey {
    case id, title, body, status, assignee, priority, tenant
    case createdAt = "created_at"
    case latestSummary = "latest_summary"
    case commentCount = "comment_count"
    case startedAt = "started_at"
    case workerPID = "worker_pid"
    case lastHeartbeatAt = "last_heartbeat_at"
    case progress
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(String.self, forKey: .id)) ?? ""
    title = (try? c.decode(String.self, forKey: .title)) ?? ""
    body = try? c.decodeIfPresent(String.self, forKey: .body)
    status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "todo"
    assignee = try? c.decodeIfPresent(String.self, forKey: .assignee)
    priority = try? c.decodeIfPresent(Int.self, forKey: .priority)
    tenant = try? c.decodeIfPresent(String.self, forKey: .tenant)
    createdAt = Self.parseTimestamp((try? c.decodeIfPresent(Double.self, forKey: .createdAt)) ?? nil)
    latestSummary = try? c.decodeIfPresent(String.self, forKey: .latestSummary)
    commentCount = try? c.decodeIfPresent(Int.self, forKey: .commentCount)
    startedAt = Self.parseTimestamp((try? c.decodeIfPresent(Double.self, forKey: .startedAt)) ?? nil)
    workerPID = try? c.decodeIfPresent(Int.self, forKey: .workerPID)
    lastHeartbeatAt = Self.parseTimestamp((try? c.decodeIfPresent(Double.self, forKey: .lastHeartbeatAt)) ?? nil)
    progress = try? c.decodeIfPresent(KanbanTaskProgress.self, forKey: .progress)
  }

  private static func parseTimestamp(_ value: Double?) -> Date? {
    guard let value, value > 0 else { return nil }
    return Date(timeIntervalSince1970: value)
  }
}

public struct KanbanTaskProgress: Equatable, Sendable, Decodable {
  public var done: Int
  public var total: Int

  public init(done: Int, total: Int) {
    self.done = done
    self.total = total
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    done = (try? c.decodeIfPresent(Int.self, forKey: .done)) ?? 0
    total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
  }

  enum CodingKeys: String, CodingKey {
    case done, total
  }
}

public struct KanbanColumn: Equatable, Sendable, Identifiable, Decodable {
  public var name: String
  public var tasks: [KanbanTask]

  public init(name: String, tasks: [KanbanTask]) {
    self.name = name
    self.tasks = tasks
  }

  public var id: String { name }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    tasks = (try? c.decodeIfPresent([KanbanTask].self, forKey: .tasks)) ?? []
  }

  enum CodingKeys: String, CodingKey {
    case name, tasks
  }
}

public struct KanbanBoard: Equatable, Sendable, Decodable {
  public var columns: [KanbanColumn]
  public var tenants: [String]
  public var assignees: [String]
  public var latestEventID: Int
  public var now: Date

  public init(
    columns: [KanbanColumn],
    tenants: [String] = [],
    assignees: [String] = [],
    latestEventID: Int = 0,
    now: Date = Date(timeIntervalSince1970: 0)
  ) {
    self.columns = columns
    self.tenants = tenants
    self.assignees = assignees
    self.latestEventID = latestEventID
    self.now = now
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    columns = (try? c.decodeIfPresent([KanbanColumn].self, forKey: .columns)) ?? []
    tenants = (try? c.decodeIfPresent([String].self, forKey: .tenants)) ?? []
    assignees = (try? c.decodeIfPresent([String].self, forKey: .assignees)) ?? []
    latestEventID = (try? c.decodeIfPresent(Int.self, forKey: .latestEventID)) ?? 0
    if let timestamp = try? c.decodeIfPresent(Double.self, forKey: .now) {
      now = Date(timeIntervalSince1970: timestamp)
    } else {
      now = Date(timeIntervalSince1970: 0)
    }
  }

  enum CodingKeys: String, CodingKey {
    case columns, tenants, assignees
    case latestEventID = "latest_event_id"
    case now
  }
}

public struct KanbanComment: Equatable, Sendable, Decodable, Identifiable {
  public var id: Int
  public var taskID: String
  public var author: String
  public var body: String
  public var createdAt: Date?

  public init(id: Int, taskID: String, author: String, body: String, createdAt: Date? = nil) {
    self.id = id
    self.taskID = taskID
    self.author = author
    self.body = body
    self.createdAt = createdAt
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
    taskID = (try? c.decodeIfPresent(String.self, forKey: .taskID)) ?? ""
    author = (try? c.decodeIfPresent(String.self, forKey: .author)) ?? ""
    body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
    createdAt = KanbanTask.parseTimestampPublic((try? c.decodeIfPresent(Double.self, forKey: .createdAt)) ?? nil)
  }

  enum CodingKeys: String, CodingKey {
    case id, author, body
    case taskID = "task_id"
    case createdAt = "created_at"
  }
}

public struct KanbanRun: Equatable, Sendable, Decodable, Identifiable {
  public var id: Int
  public var taskID: String
  public var profile: String?
  public var status: String
  public var outcome: String?
  public var summary: String?
  public var error: String?
  public var startedAt: Date?
  public var endedAt: Date?

  public init(
    id: Int,
    taskID: String,
    profile: String? = nil,
    status: String,
    outcome: String? = nil,
    summary: String? = nil,
    error: String? = nil,
    startedAt: Date? = nil,
    endedAt: Date? = nil
  ) {
    self.id = id
    self.taskID = taskID
    self.profile = profile
    self.status = status
    self.outcome = outcome
    self.summary = summary
    self.error = error
    self.startedAt = startedAt
    self.endedAt = endedAt
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? 0
    taskID = (try? c.decodeIfPresent(String.self, forKey: .taskID)) ?? ""
    profile = try? c.decodeIfPresent(String.self, forKey: .profile)
    status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "unknown"
    outcome = try? c.decodeIfPresent(String.self, forKey: .outcome)
    summary = try? c.decodeIfPresent(String.self, forKey: .summary)
    error = try? c.decodeIfPresent(String.self, forKey: .error)
    startedAt = KanbanTask.parseTimestampPublic((try? c.decodeIfPresent(Double.self, forKey: .startedAt)) ?? nil)
    endedAt = KanbanTask.parseTimestampPublic((try? c.decodeIfPresent(Double.self, forKey: .endedAt)) ?? nil)
  }

  enum CodingKeys: String, CodingKey {
    case id, profile, status, outcome, summary, error
    case taskID = "task_id"
    case startedAt = "started_at"
    case endedAt = "ended_at"
  }
}

public struct KanbanTaskDetail: Equatable, Sendable, Decodable {
  public var task: KanbanTask
  public var comments: [KanbanComment]
  public var runs: [KanbanRun]

  public init(task: KanbanTask, comments: [KanbanComment] = [], runs: [KanbanRun] = []) {
    self.task = task
    self.comments = comments
    self.runs = runs
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    task = (try? c.decodeIfPresent(KanbanTask.self, forKey: .task)) ?? KanbanTask(id: "", title: "", status: "todo")
    comments = (try? c.decodeIfPresent([KanbanComment].self, forKey: .comments)) ?? []
    runs = (try? c.decodeIfPresent([KanbanRun].self, forKey: .runs)) ?? []
  }

  enum CodingKeys: String, CodingKey {
    case task, comments, runs
  }
}

/// Writable fields exposed by the mobile Kanban editor. Only title/body/assignee/priority
/// are sent for create; update additionally sends `status` so a card can move lanes.
public struct KanbanTaskDraft: Equatable, Sendable {
  public var title: String
  public var body: String
  public var assignee: String?
  public var priority: Int
  public var status: String?

  public init(title: String, body: String = "", assignee: String? = nil, priority: Int = 0, status: String? = nil) {
    self.title = title
    self.body = body
    self.assignee = assignee
    self.priority = priority
    self.status = status
  }

  public var trimmedTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedBody: String {
    body.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var createPayload: [String: Any] {
    var payload: [String: Any] = ["title": trimmedTitle]
    if !trimmedBody.isEmpty { payload["body"] = trimmedBody }
    if let assignee { payload["assignee"] = assignee }
    payload["priority"] = priority
    return payload
  }

  var updatePayload: [String: Any] {
    var payload: [String: Any] = ["title": trimmedTitle]
    payload["body"] = trimmedBody
    if let assignee { payload["assignee"] = assignee }
    payload["priority"] = priority
    if let status { payload["status"] = status }
    return payload
  }
}

extension KanbanTask {
  static func parseTimestampPublic(_ value: Double?) -> Date? {
    guard let value, value > 0 else { return nil }
    return Date(timeIntervalSince1970: value)
  }
}
