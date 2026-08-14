import Foundation

/// The server-authoritative capability metadata used by the Skills, Toolsets, and MCP
/// surfaces. Selection state is still saved through `profiles.configure`; this snapshot is
/// intentionally read-only and contains no MCP configuration, credentials, or endpoint URLs.
public struct CapabilityCatalog: Equatable, Sendable {
  public var skills: [SkillCatalogEntry]
  public var toolsets: [ToolsetCatalogEntry]
  public var mcpServers: [MCPCatalogServer]

  public init(
    skills: [SkillCatalogEntry] = [],
    toolsets: [ToolsetCatalogEntry] = [],
    mcpServers: [MCPCatalogServer] = []
  ) {
    self.skills = skills
    self.toolsets = toolsets
    self.mcpServers = mcpServers
  }
}

/// A skill returned by one of Hermes' native `skills.manage` read actions.
///
/// Hermes' installed-skill list currently reports only name/category, search reports only
/// name/description, browse adds source/identifier, and inspect adds documentation/tags.
/// Optional fields preserve that distinction instead of inventing metadata the server did
/// not return.
public struct SkillCatalogEntry: Equatable, Sendable, Identifiable {
  public var name: String
  public var description: String
  public var documentation: String?
  public var source: String?
  public var category: String?
  public var identifier: String?
  public var enabled: Bool?
  public var tags: [String]

  public var id: String { identifier ?? name }

  public init(
    name: String,
    description: String = "",
    documentation: String? = nil,
    source: String? = nil,
    category: String? = nil,
    identifier: String? = nil,
    enabled: Bool? = nil,
    tags: [String] = []
  ) {
    self.name = name
    self.description = description
    self.documentation = documentation
    self.source = source
    self.category = category
    self.identifier = identifier
    self.enabled = enabled
    self.tags = tags
  }
}

public struct SkillCatalogBrowseRequest: Equatable, Sendable {
  public var profile: String?
  public var page: Int
  public var pageSize: Int

  public init(profile: String? = nil, page: Int = 1, pageSize: Int = 20) {
    self.profile = profile
    self.page = page
    self.pageSize = pageSize
  }
}

public struct SkillCatalogSearchRequest: Equatable, Sendable {
  public var query: String
  public var profile: String?

  public init(query: String, profile: String? = nil) {
    self.query = query
    self.profile = profile
  }
}

public struct SkillCatalogInspectRequest: Equatable, Sendable {
  public var identifier: String
  public var profile: String?

  public init(identifier: String, profile: String? = nil) {
    self.identifier = identifier
    self.profile = profile
  }
}

public struct SkillCatalogPage: Equatable, Sendable {
  public var entries: [SkillCatalogEntry]
  public var page: Int
  public var totalPages: Int
  public var total: Int

  public init(
    entries: [SkillCatalogEntry] = [],
    page: Int = 1,
    totalPages: Int = 1,
    total: Int = 0
  ) {
    self.entries = entries
    self.page = page
    self.totalPages = totalPages
    self.total = total
  }
}

/// A row returned by Hermes' native `toolsets.list` method.
public struct ToolsetCatalogEntry: Equatable, Sendable, Identifiable {
  public var name: String
  public var label: String
  public var toolsetDescription: String
  public var toolCount: Int
  public var enabled: Bool

  public var id: String { name }

  public init(
    name: String,
    label: String? = nil,
    toolsetDescription: String = "",
    toolCount: Int = 0,
    enabled: Bool = true
  ) {
    self.name = name
    self.label = label ?? name
    self.toolsetDescription = toolsetDescription
    self.toolCount = toolCount
    self.enabled = enabled
  }
}

/// Safe health states emitted by Hermes' live MCP status inventory. `mcp.catalog` does not
/// report health on every server version, so absence is represented as `.unknown` rather
/// than a false healthy/failed state.
public enum MCPServerHealth: String, Equatable, Sendable {
  case unknown
  case configured
  case connecting
  case connected
  case disabled
  case failed
}

public struct MCPToolCatalogEntry: Equatable, Sendable, Identifiable {
  public var name: String
  public var description: String

  public var id: String { name }

  public init(name: String, description: String = "") {
    self.name = name
    self.description = description
  }
}

/// Public-safe MCP metadata. The type deliberately has no URL, command, arguments, required
/// environment keys, headers, auth configuration, or server error text. Those fields may be
/// present on the wire and are discarded by the catalog decoder.
public struct MCPCatalogServer: Equatable, Sendable, Identifiable {
  public var name: String
  public var description: String
  public var installed: Bool
  public var enabled: Bool
  public var transport: String
  public var tools: [MCPToolCatalogEntry]
  public var reportedToolCount: Int?
  public var health: MCPServerHealth

  public var id: String { name }

  public init(
    name: String,
    description: String = "",
    installed: Bool = true,
    enabled: Bool = true,
    transport: String = "",
    tools: [MCPToolCatalogEntry] = [],
    reportedToolCount: Int? = nil,
    health: MCPServerHealth = .unknown
  ) {
    self.name = name
    self.description = description
    self.installed = installed
    self.enabled = enabled
    self.transport = transport
    self.tools = tools
    self.reportedToolCount = reportedToolCount
    self.health = health
  }
}

public struct CapabilityCatalogReloadResult: Equatable, Sendable {
  public var added: [String]
  public var removed: [String]
  public var total: Int

  public init(added: [String] = [], removed: [String] = [], total: Int = 0) {
    self.added = added
    self.removed = removed
    self.total = total
  }
}
