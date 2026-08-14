import Foundation

/// One row returned by the native `profiles.list` JSON-RPC method.
///
/// Hermes also returns its local filesystem path. The mobile client deliberately does not
/// retain that value: it is not needed for profile administration and can disclose server
/// topology in logs, diagnostics, or crash reports.
public struct ProfileAdminSummary: Equatable, Sendable, Identifiable {
  public var name: String
  public var isDefault: Bool
  public var model: String?
  public var provider: String?
  public var profileDescription: String
  public var skillCount: Int
  public var hasAvatar: Bool
  public var lastSession: ProfileLastSessionSummary?

  public var id: String { name }

  public init(
    name: String,
    isDefault: Bool = false,
    model: String? = nil,
    provider: String? = nil,
    profileDescription: String = "",
    skillCount: Int = 0,
    hasAvatar: Bool = false,
    lastSession: ProfileLastSessionSummary? = nil
  ) {
    self.name = name
    self.isDefault = isDefault
    self.model = model
    self.provider = provider
    self.profileDescription = profileDescription
    self.skillCount = skillCount
    self.hasAvatar = hasAvatar
    self.lastSession = lastSession
  }
}

/// The optional recent-conversation preview included by `profiles.list` when requested.
public struct ProfileLastSessionSummary: Equatable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var preview: String
  public var startedAt: Date?
  public var lastActive: Date?
  public var messageCount: Int

  public init(
    id: String,
    title: String = "",
    preview: String = "",
    startedAt: Date? = nil,
    lastActive: Date? = nil,
    messageCount: Int = 0
  ) {
    self.id = id
    self.title = title
    self.preview = preview
    self.startedAt = startedAt
    self.lastActive = lastActive
    self.messageCount = messageCount
  }
}

/// A provider/model pair. Hermes names the model member `default` in describe results and
/// accepts it as the top-level `model` member in configure/create requests.
public struct ProfileModelConfiguration: Equatable, Sendable {
  public var provider: String
  public var defaultModel: String

  public init(provider: String = "", defaultModel: String = "") {
    self.provider = provider
    self.defaultModel = defaultModel
  }

  public var isConfigured: Bool {
    !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

public struct ProfileSkill: Equatable, Sendable, Identifiable {
  public var name: String
  public var enabled: Bool

  public var id: String { name }

  public init(name: String, enabled: Bool = true) {
    self.name = name
    self.enabled = enabled
  }
}

public struct ProfileToolset: Equatable, Sendable, Identifiable {
  public var name: String
  public var label: String
  public var toolsetDescription: String
  public var toolCount: Int
  public var enabled: Bool

  public var id: String { name }

  public init(
    name: String,
    label: String = "",
    toolsetDescription: String = "",
    toolCount: Int = 0,
    enabled: Bool = true
  ) {
    self.name = name
    self.label = label
    self.toolsetDescription = toolsetDescription
    self.toolCount = toolCount
    self.enabled = enabled
  }
}

/// Safe MCP metadata returned by `profiles.describe`.
///
/// Raw server definitions, command arguments, URLs, environment variables, headers, and
/// credentials are intentionally not modeled. Unknown response fields therefore cannot
/// accidentally flow into UI state, logs, or local persistence.
public struct ProfileMCPServer: Equatable, Sendable, Identifiable {
  public var name: String
  public var enabled: Bool
  public var transport: String

  public var id: String { name }

  public init(name: String, enabled: Bool = true, transport: String = "") {
    self.name = name
    self.enabled = enabled
    self.transport = transport
  }
}

/// Server-authoritative editor snapshot from `profiles.describe`.
public struct ProfileDescription: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public var name: String
  /// Human-authored profile description. This also satisfies `CustomStringConvertible`, so
  /// ordinary interpolation never falls back to reflecting the full struct (and its SOUL).
  public var description: String
  public var soul: String
  public var model: ProfileModelConfiguration
  /// Optional for compatibility. Hermes Agent snapshot `a90d536` and current HEAD do not
  /// return this field yet; newer servers can add it without breaking decoding.
  public var reasoningEffort: String?
  public var skills: [ProfileSkill]
  public var toolsets: [ProfileToolset]
  public var toolsetsPinned: Bool
  public var mcpServers: [ProfileMCPServer]

  public init(
    name: String,
    description: String = "",
    soul: String = "",
    model: ProfileModelConfiguration = ProfileModelConfiguration(),
    reasoningEffort: String? = nil,
    skills: [ProfileSkill] = [],
    toolsets: [ProfileToolset] = [],
    toolsetsPinned: Bool = false,
    mcpServers: [ProfileMCPServer] = []
  ) {
    self.name = name
    self.description = description
    self.soul = soul
    self.model = model
    self.reasoningEffort = reasoningEffort
    self.skills = skills
    self.toolsets = toolsets
    self.toolsetsPinned = toolsetsPinned
    self.mcpServers = mcpServers
  }

  /// SOUL contents are intentionally never included in debug output.
  public var debugDescription: String {
    "ProfileDescription(name: \(String(reflecting: name)), soul: <redacted>, "
      + "skills: \(skills.count), toolsets: \(toolsets.count), mcpServers: \(mcpServers.count))"
  }
}

/// Typed request for native `profiles.create`.
public struct ProfileCreateRequest: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public var name: String
  public var descriptionText: String?
  public var cloneFrom: String?
  public var cloneAll: Bool
  public var noSkills: Bool
  public var soul: String?
  public var model: ProfileModelConfiguration?
  public var mirrorCredentials: Bool
  public var shareAuthentication: Bool

  public init(
    name: String,
    description: String? = nil,
    cloneFrom: String? = nil,
    cloneAll: Bool = false,
    noSkills: Bool = false,
    soul: String? = nil,
    model: ProfileModelConfiguration? = nil,
    mirrorCredentials: Bool = true,
    shareAuthentication: Bool = false
  ) {
    self.name = name
    self.descriptionText = description
    self.cloneFrom = cloneFrom
    self.cloneAll = cloneAll
    self.noSkills = noSkills
    self.soul = soul
    self.model = model
    self.mirrorCredentials = mirrorCredentials
    self.shareAuthentication = shareAuthentication
  }

  /// Safe for diagnostics: content and credential details are represented only as flags.
  public var description: String {
    "ProfileCreateRequest(name: \(String(reflecting: name)), hasDescription: "
      + "\(descriptionText != nil), hasSoul: \(soul != nil), hasModel: \(model != nil), "
      + "mirrorCredentials: \(mirrorCredentials), shareAuthentication: \(shareAuthentication))"
  }

  public var debugDescription: String { description }
}

public enum ProfileAuthenticationMirroring: Equatable, Sendable {
  case none
  case copied
  case shared
  /// A future Hermes value the client did not recognize. The raw value is not retained
  /// because authentication metadata belongs on the server, not in mobile diagnostics.
  case unknown
}

public struct ProfileCredentialMirroring: Equatable, Sendable {
  public var environmentCopied: Bool
  public var authentication: ProfileAuthenticationMirroring
  public var modelInherited: Bool
  public var voiceInherited: Bool

  public init(
    environmentCopied: Bool = false,
    authentication: ProfileAuthenticationMirroring = .none,
    modelInherited: Bool = false,
    voiceInherited: Bool = false
  ) {
    self.environmentCopied = environmentCopied
    self.authentication = authentication
    self.modelInherited = modelInherited
    self.voiceInherited = voiceInherited
  }
}

public struct ProfileCreateResult: Equatable, Sendable {
  public var ok: Bool
  public var name: String
  public var soulWritten: Bool?
  public var modelSet: Bool?
  public var mirrored: ProfileCredentialMirroring?

  public init(
    ok: Bool,
    name: String,
    soulWritten: Bool? = nil,
    modelSet: Bool? = nil,
    mirrored: ProfileCredentialMirroring? = nil
  ) {
    self.ok = ok
    self.name = name
    self.soulWritten = soulWritten
    self.modelSet = modelSet
    self.mirrored = mirrored
  }
}

/// Optional members mean "leave this section unchanged". Empty arrays are meaningful and
/// retain Hermes' replace semantics (for example, an empty enabled-toolsets array clears the
/// pin and returns the profile to the server's default toolset selection).
public struct ProfileConfigureRequest: Equatable, Sendable, CustomStringConvertible,
  CustomDebugStringConvertible
{
  public var name: String
  public var descriptionText: String?
  public var soul: String?
  public var model: ProfileModelConfiguration?
  /// Compatibility field. Servers that do not implement it omit the corresponding applied
  /// status; the client reports that section as `.notReported`, never as a false success.
  public var reasoningEffort: String?
  public var disabledSkills: [String]?
  public var enabledToolsets: [String]?
  public var enabledMCPServers: [String]?

  public init(
    name: String,
    description: String? = nil,
    soul: String? = nil,
    model: ProfileModelConfiguration? = nil,
    reasoningEffort: String? = nil,
    disabledSkills: [String]? = nil,
    enabledToolsets: [String]? = nil,
    enabledMCPServers: [String]? = nil
  ) {
    self.name = name
    self.descriptionText = description
    self.soul = soul
    self.model = model
    self.reasoningEffort = reasoningEffort
    self.disabledSkills = disabledSkills
    self.enabledToolsets = enabledToolsets
    self.enabledMCPServers = enabledMCPServers
  }

  public var requestedSections: Set<ProfileConfigureSection> {
    var sections: Set<ProfileConfigureSection> = []
    if descriptionText != nil { sections.insert(.description) }
    if soul != nil { sections.insert(.soul) }
    if model != nil { sections.insert(.model) }
    if reasoningEffort != nil { sections.insert(.reasoningEffort) }
    if disabledSkills != nil { sections.insert(.skills) }
    if enabledToolsets != nil { sections.insert(.toolsets) }
    if enabledMCPServers != nil { sections.insert(.mcpServers) }
    return sections
  }

  /// Contains section names only. SOUL, descriptions, model identifiers, and MCP names are
  /// excluded so generic request logging cannot disclose profile contents or infrastructure.
  public var description: String {
    let sections = requestedSections.map(\.rawValue).sorted().joined(separator: ",")
    return "ProfileConfigureRequest(name: \(String(reflecting: name)), sections: [\(sections)])"
  }

  public var debugDescription: String { description }
}

public enum ProfileConfigureSection: String, CaseIterable, Hashable, Sendable {
  case description
  case soul
  case model
  case reasoningEffort = "reasoning_effort"
  case skills
  case toolsets
  case mcpServers = "mcp_servers"
}

public enum ProfileConfigureStatus: Equatable, Sendable {
  case applied
  case failed
  /// The section was requested but the server did not include an authoritative result for
  /// it. This is how newer client fields remain honest against older Hermes versions.
  case notReported
}

/// Per-section result from `profiles.configure`. Hermes applies each section independently;
/// callers must inspect these statuses rather than treating receipt of a JSON-RPC success
/// frame as an all-or-nothing save.
public struct ProfileConfigureResult: Equatable, Sendable {
  public var ok: Bool
  public var requestedSections: Set<ProfileConfigureSection>
  public var sectionStatuses: [ProfileConfigureSection: ProfileConfigureStatus]
  /// Future server sections are retained as safe names + booleans so diagnostics can report
  /// protocol drift without retaining any configuration values.
  public var unknownAppliedSections: [String: Bool]

  public init(
    ok: Bool,
    requestedSections: Set<ProfileConfigureSection>,
    sectionStatuses: [ProfileConfigureSection: ProfileConfigureStatus],
    unknownAppliedSections: [String: Bool] = [:]
  ) {
    self.ok = ok
    self.requestedSections = requestedSections
    self.sectionStatuses = sectionStatuses
    self.unknownAppliedSections = unknownAppliedSections
  }

  public func status(for section: ProfileConfigureSection) -> ProfileConfigureStatus? {
    sectionStatuses[section]
  }

  public var appliedSections: Set<ProfileConfigureSection> {
    Set(sectionStatuses.compactMap { $0.value == .applied ? $0.key : nil })
  }

  public var failedSections: Set<ProfileConfigureSection> {
    Set(sectionStatuses.compactMap { $0.value == .failed ? $0.key : nil })
  }

  public var unreportedSections: Set<ProfileConfigureSection> {
    Set(sectionStatuses.compactMap { $0.value == .notReported ? $0.key : nil })
  }

  public var isCompleteSuccess: Bool {
    ok && failedSections.isEmpty && unreportedSections.isEmpty
  }
}
