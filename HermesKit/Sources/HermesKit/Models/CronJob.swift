import Foundation

/// A cron job as returned by `GET /api/cron/jobs` and `GET /api/cron/jobs/{id}`
/// (present on hermes-agent v0.16+). Decoded leniently — only `id` is required;
/// unknown fields and unknown `state` strings pass through untouched so a newer
/// agent never crashes the list.
public struct CronJob: Equatable, Sendable, Identifiable, Decodable {
  public var id: String
  public var name: String?
  public var prompt: String?
  /// Human-readable schedule (`schedule_display`, e.g. "every day at 09:00").
  public var scheduleDisplay: String?
  /// Raw five-field/cron expression when the server returns `schedule.expr`.
  public var scheduleExpression: String?
  /// Schedule kind when the server returns `schedule.kind` (`cron`, `once`, …).
  public var scheduleKind: String?
  public var enabled: Bool?
  /// Server-computed lifecycle state (`scheduled` / `running` / `paused` / `error` /
  /// `completed` / `disabled`), kept as a raw string for leniency — see `effectiveState`.
  public var state: String?
  public var nextRunAt: Date?
  public var lastRunAt: Date?
  public var lastStatus: String?
  public var lastError: String?
  public var lastDeliveryError: String?
  /// Annotated by the server's cross-profile aggregation (`profile` on each job).
  public var profile: String?
  /// Same annotation under the server's newer `profile_name` key.
  public var profileName: String?
  public var isDefaultProfile: Bool?
  /// Delivery target id (`local`, `telegram`, `discord`, …).
  public var deliver: String?
  /// Optional per-job model/provider overrides. Empty strings are normalized to nil.
  public var model: String?
  public var provider: String?
  public var baseURL: String?
  public var skills: [String]
  public var repeatTimes: Int?
  public var repeatCompleted: Int?
  public var noAgent: Bool?
  public var script: String?
  public var contextFrom: [String]
  public var enabledToolsets: [String]
  public var workdir: String?
  public var createdAt: Date?
  public var latestExecution: CronJobExecution?

  public init(
    id: String,
    name: String? = nil,
    prompt: String? = nil,
    scheduleDisplay: String? = nil,
    scheduleExpression: String? = nil,
    scheduleKind: String? = nil,
    enabled: Bool? = nil,
    state: String? = nil,
    nextRunAt: Date? = nil,
    lastRunAt: Date? = nil,
    lastStatus: String? = nil,
    lastError: String? = nil,
    lastDeliveryError: String? = nil,
    profile: String? = nil,
    profileName: String? = nil,
    isDefaultProfile: Bool? = nil,
    deliver: String? = nil,
    model: String? = nil,
    provider: String? = nil,
    baseURL: String? = nil,
    skills: [String] = [],
    repeatTimes: Int? = nil,
    repeatCompleted: Int? = nil,
    noAgent: Bool? = nil,
    script: String? = nil,
    contextFrom: [String] = [],
    enabledToolsets: [String] = [],
    workdir: String? = nil,
    createdAt: Date? = nil,
    latestExecution: CronJobExecution? = nil
  ) {
    self.id = id
    self.name = name
    self.prompt = prompt
    self.scheduleDisplay = scheduleDisplay
    self.scheduleExpression = scheduleExpression
    self.scheduleKind = scheduleKind
    self.enabled = enabled
    self.state = state
    self.nextRunAt = nextRunAt
    self.lastRunAt = lastRunAt
    self.lastStatus = lastStatus
    self.lastError = lastError
    self.lastDeliveryError = lastDeliveryError
    self.profile = profile
    self.profileName = profileName
    self.isDefaultProfile = isDefaultProfile
    self.deliver = deliver
    self.model = model
    self.provider = provider
    self.baseURL = baseURL
    self.skills = skills
    self.repeatTimes = repeatTimes
    self.repeatCompleted = repeatCompleted
    self.noAgent = noAgent
    self.script = script
    self.contextFrom = contextFrom
    self.enabledToolsets = enabledToolsets
    self.workdir = workdir
    self.createdAt = createdAt
    self.latestExecution = latestExecution
  }

  enum CodingKeys: String, CodingKey {
    case id, name, prompt, enabled, state, profile, deliver, model, provider, script
    case skills, workdir, no_agent
    case scheduleDisplay = "schedule_display"
    case nextRunAt = "next_run_at"
    case lastRunAt = "last_run_at"
    case lastStatus = "last_status"
    case lastError = "last_error"
    case lastDeliveryError = "last_delivery_error"
    case profileName = "profile_name"
    case isDefaultProfile = "is_default_profile"
    case schedule
    case baseURL = "base_url"
    case repeatTimes = "repeat"
    case contextFrom = "context_from"
    case enabledToolsets = "enabled_toolsets"
    case createdAt = "created_at"
    case latestExecution = "latest_execution"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decode(String.self, forKey: .id)) ?? ""
    name = try? c.decodeIfPresent(String.self, forKey: .name)
    prompt = try? c.decodeIfPresent(String.self, forKey: .prompt)
    scheduleDisplay = try? c.decodeIfPresent(String.self, forKey: .scheduleDisplay)
    // `schedule` is an object (`{display, expr, kind, …}`) on current agents.
    if let schedule = try? c.decodeIfPresent(CronSchedule.self, forKey: .schedule) {
      scheduleExpression = schedule.expr
      scheduleKind = schedule.kind
      if scheduleDisplay == nil, let display = schedule.display {
        scheduleDisplay = display
      }
    } else {
      scheduleExpression = nil
      scheduleKind = nil
    }
    enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
    state = try? c.decodeIfPresent(String.self, forKey: .state)
    nextRunAt = Self.parseISODate((try? c.decodeIfPresent(String.self, forKey: .nextRunAt)) ?? nil)
    lastRunAt = Self.parseISODate((try? c.decodeIfPresent(String.self, forKey: .lastRunAt)) ?? nil)
    lastStatus = try? c.decodeIfPresent(String.self, forKey: .lastStatus)
    lastError = try? c.decodeIfPresent(String.self, forKey: .lastError)
    lastDeliveryError = try? c.decodeIfPresent(String.self, forKey: .lastDeliveryError)
    profile = try? c.decodeIfPresent(String.self, forKey: .profile)
    profileName = try? c.decodeIfPresent(String.self, forKey: .profileName)
    isDefaultProfile = try? c.decodeIfPresent(Bool.self, forKey: .isDefaultProfile)
    deliver = try? c.decodeIfPresent(String.self, forKey: .deliver)
    model = try? c.decodeIfPresent(String.self, forKey: .model)
    provider = try? c.decodeIfPresent(String.self, forKey: .provider)
    baseURL = try? c.decodeIfPresent(String.self, forKey: .baseURL)
    skills = Self.decodeStringList(c, forKey: .skills)
    noAgent = try? c.decodeIfPresent(Bool.self, forKey: .no_agent)
    script = try? c.decodeIfPresent(String.self, forKey: .script)
    contextFrom = Self.decodeStringList(c, forKey: .contextFrom)
    enabledToolsets = Self.decodeStringList(c, forKey: .enabledToolsets)
    workdir = try? c.decodeIfPresent(String.self, forKey: .workdir)
    createdAt = Self.parseISODate((try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? nil)
    latestExecution = try? c.decodeIfPresent(CronJobExecution.self, forKey: .latestExecution)
    // `repeat` is an object `{times, completed}` on current agents; older agents may
    // send an integer. Decode either leniently.
    if let repeatObject = try? c.decodeIfPresent(CronRepeat.self, forKey: .repeatTimes) {
      repeatTimes = repeatObject.times
      repeatCompleted = repeatObject.completed
    } else {
      repeatTimes = try? c.decodeIfPresent(Int.self, forKey: .repeatTimes)
      repeatCompleted = nil
    }
  }

  /// Human label: name → 60-char prompt clip → id (mirrors the desktop's `jobTitle`
  /// fallback chain so the two clients never label a job differently).
  public var title: String {
    if let name = name?.trimmedNonEmpty { return name }
    if let prompt = prompt?.trimmedNonEmpty {
      return prompt.count > 60 ? String(prompt.prefix(60)) + "…" : prompt
    }
    return id
  }

  /// Effective lifecycle state: the explicit `state` wins; otherwise inferred from the
  /// `enabled` flag (mirrors the desktop's `jobState`).
  public var effectiveState: String {
    state?.trimmedNonEmpty ?? (enabled == false ? "disabled" : "scheduled")
  }

  public var isPaused: Bool { effectiveState == "paused" }

  /// The profile annotation, preferring the newer `profile_name` key.
  public var effectiveProfile: String? { profileName ?? profile }

  public var scheduleText: String {
    scheduleExpression?.trimmedNonEmpty
      ?? scheduleDisplay?.trimmedNonEmpty
      ?? ""
  }

  public var repeatLabel: String? {
    guard let times = repeatTimes else { return nil }
    if let completed = repeatCompleted {
      return "\(completed)/\(times)"
    }
    return "\(times)"
  }

  public var isScriptOnly: Bool {
    (noAgent ?? false) && (script?.trimmedNonEmpty != nil)
  }

  /// Extracts the owning job id from a cron run-session id. The scheduler names run
  /// sessions `cron_{job_id}_{YYYYMMDD}_{HHMMSS}` (see hermes-agent `cron/scheduler.py`);
  /// the job id itself may contain underscores (legacy/imported jobs), so we anchor on the
  /// `cron_` prefix and strip the trailing datetime stamp rather than splitting on `_`.
  /// Returns nil for anything that doesn't match (interactive sessions, odd ids).
  public static func jobID(fromSessionID sessionID: String) -> String? {
    guard sessionID.hasPrefix("cron_") else { return nil }
    let rest = String(sessionID.dropFirst("cron_".count))
    guard
      let range = rest.range(of: #"_\d{8}_\d{6}$"#, options: .regularExpression),
      range.lowerBound > rest.startIndex
    else { return nil }
    return String(rest[..<range.lowerBound])
  }

  /// Coarse relative label for a run instant: "in 7 hr." / "5 min. ago" / "in 2 days".
  /// Hand-rolled (no `RelativeDateTimeFormatter`) so tests and snapshots are
  /// locale-deterministic; picks the coarsest sensible unit like the desktop sidebar.
  public static func relativeRunLabel(for target: Date, now: Date) -> String {
    let diff = target.timeIntervalSince(now)
    let abs = Swift.abs(diff)
    let amount: String
    switch abs {
    case ..<60: amount = "\(max(1, Int(abs.rounded()))) sec."
    case ..<3600: amount = "\(Int((abs / 60).rounded())) min."
    case ..<86400: amount = "\(Int((abs / 3600).rounded())) hr."
    default:
      let days = Int((abs / 86400).rounded())
      amount = days == 1 ? "1 day" : "\(days) days"
    }
    return diff < 0 ? "\(amount) ago" : "in \(amount)"
  }

  private static func decodeStringList(
    _ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
  ) -> [String] {
    if let list = try? container.decodeIfPresent([String].self, forKey: key) {
      return list
    }
    if let text = try? container.decodeIfPresent(String.self, forKey: key) {
      return text
        .split(whereSeparator: { $0 == "," || $0 == "\n" })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
    return []
  }

  static func parseISODate(_ raw: String?) -> Date? {
    guard let raw = raw?.trimmedNonEmpty else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: raw) { return date }
    let plain = ISO8601DateFormatter()
    return plain.date(from: raw)
  }
}

/// The server's `schedule` object on current cron jobs.
public struct CronSchedule: Equatable, Sendable, Decodable {
  public var display: String?
  public var expr: String?
  public var kind: String?

  enum CodingKeys: String, CodingKey {
    case display, expr, kind
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    display = try? c.decodeIfPresent(String.self, forKey: .display)
    expr = try? c.decodeIfPresent(String.self, forKey: .expr)
    kind = try? c.decodeIfPresent(String.self, forKey: .kind)
  }
}

/// The server's `repeat` object (`times` + `completed`).
public struct CronRepeat: Equatable, Sendable, Decodable {
  public var times: Int?
  public var completed: Int?

  enum CodingKeys: String, CodingKey {
    case times, completed
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    times = try? c.decodeIfPresent(Int.self, forKey: .times)
    completed = try? c.decodeIfPresent(Int.self, forKey: .completed)
  }
}

/// A compact summary of a cron job's most recent execution, when the server attaches it.
public struct CronJobExecution: Equatable, Sendable, Decodable {
  public var startedAt: Date?
  public var finishedAt: Date?
  public var status: String?
  public var error: String?

  enum CodingKeys: String, CodingKey {
    case startedAt = "started_at"
    case finishedAt = "finished_at"
    case status
    case error
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let startedRaw = try? c.decodeIfPresent(String.self, forKey: .startedAt)
    startedAt = CronJob.parseISODate(startedRaw)
    let finishedRaw = try? c.decodeIfPresent(String.self, forKey: .finishedAt)
    finishedAt = CronJob.parseISODate(finishedRaw)
    status = try? c.decodeIfPresent(String.self, forKey: .status)
    error = try? c.decodeIfPresent(String.self, forKey: .error)
  }
}

/// A verified writable cron job shape for create/edit. Only fields the current Hermes
/// REST contract accepts are represented. `repeat` is intentionally not writable through
/// the dashboard REST API (it is a readable job field only); profile scoping is passed
/// separately by the client.
public struct CronJobDraft: Equatable, Sendable {
  public var name: String
  public var prompt: String
  public var schedule: String
  public var deliver: String
  public var model: String?
  public var provider: String?
  public var skills: [String]

  public init(
    name: String = "",
    prompt: String = "",
    schedule: String = "",
    deliver: String = "local",
    model: String? = nil,
    provider: String? = nil,
    skills: [String] = []
  ) {
    self.name = name
    self.prompt = prompt
    self.schedule = schedule
    self.deliver = deliver
    self.model = model
    self.provider = provider
    self.skills = skills
  }

  public var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedPrompt: String {
    prompt.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedSchedule: String {
    schedule.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public var trimmedDeliver: String {
    let value = deliver.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "local" : value
  }

  public var trimmedModel: String? {
    let value = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }

  public var trimmedProvider: String? {
    let value = provider?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : value
  }

  public var trimmedSkills: [String] {
    skills.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  /// JSON body for `POST /api/cron/jobs`.
  var createPayload: [String: Any] {
    var payload: [String: Any] = [
      "prompt": trimmedPrompt,
      "schedule": trimmedSchedule,
      "name": trimmedName,
      "deliver": trimmedDeliver,
    ]
    if let trimmedModel { payload["model"] = trimmedModel }
    if let trimmedProvider { payload["provider"] = trimmedProvider }
    let trimmedSkills = trimmedSkills
    if !trimmedSkills.isEmpty { payload["skills"] = trimmedSkills }
    return payload
  }

  /// JSON body for `PUT /api/cron/jobs/{id}`. The dashboard accepts a generic `updates`
  /// dict; we only send fields this client exposes.
  var updatePayload: [String: Any] {
    var updates: [String: Any] = [
      "name": trimmedName,
      "prompt": trimmedPrompt,
      "schedule": trimmedSchedule,
      "deliver": trimmedDeliver,
    ]
    if let trimmedModel { updates["model"] = trimmedModel } else { updates["model"] = NSNull() }
    if let trimmedProvider { updates["provider"] = trimmedProvider } else { updates["provider"] = NSNull() }
    let trimmedSkills = trimmedSkills
    if !trimmedSkills.isEmpty { updates["skills"] = trimmedSkills } else { updates["skills"] = [] }
    return ["updates": updates]
  }
}

/// A delivery target from `GET /api/cron/delivery-targets`.
public struct CronDeliveryTarget: Equatable, Sendable, Decodable, Identifiable {
  public var id: String
  public var name: String
  public var homeTargetSet: Bool
  public var homeEnvVar: String?

  enum CodingKeys: String, CodingKey {
    case id, name
    case homeTargetSet = "home_target_set"
    case homeEnvVar = "home_env_var"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
    name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? id
    homeTargetSet = (try? c.decodeIfPresent(Bool.self, forKey: .homeTargetSet)) ?? false
    homeEnvVar = try? c.decodeIfPresent(String.self, forKey: .homeEnvVar)
  }

  public init(id: String, name: String, homeTargetSet: Bool, homeEnvVar: String? = nil) {
    self.id = id
    self.name = name
    self.homeTargetSet = homeTargetSet
    self.homeEnvVar = homeEnvVar
  }
}
