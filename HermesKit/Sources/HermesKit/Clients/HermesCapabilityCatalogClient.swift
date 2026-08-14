import ComposableArchitecture
import DependenciesMacros
import Foundation

public enum CapabilityCatalogError: Error, Equatable, Sendable {
  /// Only an authoritative JSON-RPC unknown/unavailable response maps here. A timeout,
  /// disconnect, auth failure, or arbitrary server message remains a retryable request error.
  case unsupported
  case malformedResponse(method: String)
  case request(String)

  public var message: String {
    switch self {
    case .unsupported:
      "Capability catalogs are not supported by this Hermes server."
    case let .malformedResponse(method):
      "Hermes returned an unexpected \(method) response."
    case let .request(message):
      message
    }
  }

  init(_ error: any Error, method: String) {
    if let error = error as? CapabilityCatalogError {
      self = error
    } else if let error = error as? GatewayError {
      self = error.isUnsupportedOperation ? .unsupported : .request(error.message)
    } else {
      // Arbitrary transport errors can include a URL, ticket, or server-local path.
      self = .request("Couldn’t complete \(method).")
    }
  }
}

/// Typed read-only access to Hermes' native Skills, Toolsets, and MCP catalogs.
///
/// Every native call owns a fresh gateway connection, waits for `gateway.ready`, sends one
/// request, and disconnects. It never shares the chat socket or its response router.
@DependencyClient
public struct HermesCapabilityCatalogClient: Sendable {
  public var load: @Sendable (
    _ connection: ServerConnection,
    _ profile: String?
  ) async throws -> CapabilityCatalog
  public var browseSkills: @Sendable (
    _ connection: ServerConnection,
    _ request: SkillCatalogBrowseRequest
  ) async throws -> SkillCatalogPage
  public var searchSkills: @Sendable (
    _ connection: ServerConnection,
    _ request: SkillCatalogSearchRequest
  ) async throws -> [SkillCatalogEntry]
  public var inspectSkill: @Sendable (
    _ connection: ServerConnection,
    _ request: SkillCatalogInspectRequest
  ) async throws -> SkillCatalogEntry
  public var reload: @Sendable (
    _ connection: ServerConnection,
    _ profile: String?
  ) async throws -> CapabilityCatalogReloadResult
}

public extension HermesCapabilityCatalogClient {
  static func live(
    session: URLSession = .shared,
    gatewayReadyTimeoutNanoseconds: UInt64 = 10_000_000_000
  ) -> HermesCapabilityCatalogClient {
    .make(gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds) {
      HermesGatewayClient.live(session: session)
    }
  }

  static func make(
    gatewayReadyTimeoutNanoseconds: UInt64 = 10_000_000_000,
    makeGateway: @escaping @Sendable () -> HermesGatewayClient
  ) -> HermesCapabilityCatalogClient {
    HermesCapabilityCatalogClient(
      load: { connection, profile in
        async let skillsValue = capabilityRPC(
          connection: connection,
          method: "skills.manage",
          params: .object(skillsParams(action: "list", profile: profile)),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        async let toolsetsValue = capabilityRPC(
          connection: connection,
          method: "toolsets.list",
          params: .object([:]),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        async let mcpValue = capabilityRPC(
          connection: connection,
          method: "mcp.catalog",
          params: optionalProfileParams(profile),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        let (skills, toolsets, mcpServers) = try await (
          skillsValue, toolsetsValue, mcpValue
        )
        return try CapabilityCatalog(
          skills: decodeInstalledSkills(skills),
          toolsets: decodeToolsets(toolsets),
          mcpServers: decodeMCPServers(mcpServers)
        )
      },
      browseSkills: { connection, request in
        let method = "skills.manage"
        var params = skillsParams(action: "browse", profile: request.profile)
        params["page"] = .number(Double(max(1, request.page)))
        params["page_size"] = .number(Double(min(100, max(1, request.pageSize))))
        let result = try await capabilityRPC(
          connection: connection,
          method: method,
          params: .object(params),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeSkillPage(result, method: method)
      },
      searchSkills: { connection, request in
        let method = "skills.manage"
        var params = skillsParams(action: "search", profile: request.profile)
        params["query"] = .string(request.query)
        let result = try await capabilityRPC(
          connection: connection,
          method: method,
          params: .object(params),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeSkillSearch(result, method: method)
      },
      inspectSkill: { connection, request in
        let method = "skills.manage"
        var params = skillsParams(action: "inspect", profile: request.profile)
        params["query"] = .string(request.identifier)
        let result = try await capabilityRPC(
          connection: connection,
          method: method,
          params: .object(params),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeInspectedSkill(result, method: method)
      },
      reload: { connection, profile in
        let method = "skills.reload"
        let result = try await capabilityRPC(
          connection: connection,
          method: method,
          params: optionalProfileParams(profile),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeReloadResult(result, method: method)
      }
    )
  }
}

extension HermesCapabilityCatalogClient: DependencyKey {
  public static var liveValue: HermesCapabilityCatalogClient { .live() }
  public static var testValue: HermesCapabilityCatalogClient { HermesCapabilityCatalogClient() }
}

public extension DependencyValues {
  var hermesCapabilityCatalog: HermesCapabilityCatalogClient {
    get { self[HermesCapabilityCatalogClient.self] }
    set { self[HermesCapabilityCatalogClient.self] = newValue }
  }
}

// MARK: - Isolated one-shot transport

private func capabilityRPC(
  connection: ServerConnection,
  method: String,
  params: JSONValue,
  gatewayReadyTimeoutNanoseconds: UInt64,
  makeGateway: @escaping @Sendable () -> HermesGatewayClient
) async throws -> JSONValue {
  let gateway = makeGateway()
  let events = gateway.connect(connection.baseURL, connection.auth)
  defer { gateway.disconnect() }

  do {
    try await waitForCapabilityGatewayReady(
      events,
      timeoutNanoseconds: gatewayReadyTimeoutNanoseconds
    )
    return try await gateway.send(method, params)
  } catch {
    throw CapabilityCatalogError(error, method: method)
  }
}

private func waitForCapabilityGatewayReady(
  _ events: AsyncStream<GatewayEvent>,
  timeoutNanoseconds: UInt64
) async throws {
  try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
      for await event in events {
        switch event {
        case .ready:
          return
        case .authExpired:
          throw GatewayError.authExpired
        case let .error(message):
          throw GatewayError.server(message)
        default:
          continue
        }
      }
      throw GatewayError.disconnected
    }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      throw GatewayError.timedOut(method: "gateway.connect")
    }

    do {
      _ = try await group.next()
      group.cancelAll()
    } catch {
      group.cancelAll()
      throw error
    }
  }
}

// MARK: - Outbound params

private func skillsParams(action: String, profile: String?) -> [String: JSONValue] {
  var params: [String: JSONValue] = ["action": .string(action)]
  if let profile = nonEmptyString(profile) { params["profile"] = .string(profile) }
  return params
}

private func optionalProfileParams(_ profile: String?) -> JSONValue {
  guard let profile = nonEmptyString(profile) else { return .object([:]) }
  return .object(["profile": .string(profile)])
}

// MARK: - Lenient response mapping

private func decodeInstalledSkills(_ value: JSONValue) throws -> [SkillCatalogEntry] {
  guard let root = catalogObject(value), let rawSkills = root["skills"] else {
    throw CapabilityCatalogError.malformedResponse(method: "skills.manage")
  }

  if let categories = catalogObject(rawSkills) {
    return categories.keys.sorted().flatMap { category in
      (catalogArray(categories[category]) ?? []).compactMap { value in
        guard let name = catalogNonEmptyString(value) else { return nil }
        return SkillCatalogEntry(name: name, category: category, enabled: true)
      }
    }
  }

  guard let rows = catalogArray(rawSkills) else {
    throw CapabilityCatalogError.malformedResponse(method: "skills.manage")
  }
  return rows.compactMap { decodeSkillEntry($0) }
}

private func decodeSkillPage(_ value: JSONValue, method: String) throws -> SkillCatalogPage {
  guard let root = catalogObject(value), let rows = catalogArray(root["items"]) else {
    throw CapabilityCatalogError.malformedResponse(method: method)
  }
  return SkillCatalogPage(
    entries: rows.compactMap(decodeSkillEntry),
    page: max(1, catalogInt(root["page"]) ?? 1),
    totalPages: max(1, catalogInt(root["total_pages"]) ?? 1),
    total: max(0, catalogInt(root["total"]) ?? 0)
  )
}

private func decodeSkillSearch(_ value: JSONValue, method: String) throws
  -> [SkillCatalogEntry] {
  guard let root = catalogObject(value), let rows = catalogArray(root["results"]) else {
    throw CapabilityCatalogError.malformedResponse(method: method)
  }
  return rows.compactMap(decodeSkillEntry)
}

private func decodeInspectedSkill(_ value: JSONValue, method: String) throws
  -> SkillCatalogEntry {
  guard let root = catalogObject(value),
        let info = root["info"],
        let skill = decodeSkillEntry(info) else {
    throw CapabilityCatalogError.malformedResponse(method: method)
  }
  return skill
}

private func decodeSkillEntry(_ value: JSONValue) -> SkillCatalogEntry? {
  guard let row = catalogObject(value), let name = catalogNonEmptyString(row["name"]) else {
    return nil
  }
  let documentation = nonEmptyString(
    catalogString(row["skill_md_preview"])
      ?? catalogString(row["documentation"])
      ?? catalogString(row["docs"])
  )
  let tags = (catalogArray(row["tags"]) ?? []).compactMap(catalogNonEmptyString)
  return SkillCatalogEntry(
    name: name,
    description: catalogString(row["description"]) ?? "",
    documentation: documentation,
    source: catalogNonEmptyString(row["source"]),
    category: catalogNonEmptyString(row["category"]),
    identifier: catalogNonEmptyString(row["identifier"]),
    enabled: catalogBool(row["enabled"]),
    tags: tags
  )
}

private func decodeToolsets(_ value: JSONValue) throws -> [ToolsetCatalogEntry] {
  guard let root = catalogObject(value), let rows = catalogArray(root["toolsets"]) else {
    throw CapabilityCatalogError.malformedResponse(method: "toolsets.list")
  }
  return rows.compactMap { value in
    guard let row = catalogObject(value), let name = catalogNonEmptyString(row["name"]) else {
      return nil
    }
    return ToolsetCatalogEntry(
      name: name,
      label: catalogNonEmptyString(row["label"]),
      toolsetDescription: catalogString(row["description"]) ?? "",
      toolCount: max(0, catalogInt(row["tool_count"]) ?? 0),
      enabled: catalogBool(row["enabled"]) ?? true
    )
  }
}

private func decodeMCPServers(_ value: JSONValue) throws -> [MCPCatalogServer] {
  guard let root = catalogObject(value),
        let rows = catalogArray(root["servers"] ?? root["mcp_servers"]) else {
    throw CapabilityCatalogError.malformedResponse(method: "mcp.catalog")
  }
  return rows.compactMap { value in
    guard let row = catalogObject(value), let name = catalogNonEmptyString(row["name"]) else {
      return nil
    }
    let tools = decodeMCPTools(row["tools"])
    let reportedCount = catalogInt(row["tool_count"])
      ?? (catalogInt(row["tools"]) ?? (tools.isEmpty ? nil : tools.count))
    return MCPCatalogServer(
      name: name,
      description: catalogString(row["description"]) ?? "",
      installed: catalogBool(row["installed"]) ?? true,
      enabled: catalogBool(row["enabled"]) ?? !(catalogBool(row["disabled"]) ?? false),
      transport: safeCatalogTransport(row["transport"]),
      tools: tools,
      reportedToolCount: reportedCount.map { max(0, $0) },
      health: decodeMCPHealth(row)
    )
  }
}

private func decodeMCPTools(_ value: JSONValue?) -> [MCPToolCatalogEntry] {
  guard let rows = catalogArray(value) else { return [] }
  return rows.compactMap { value in
    if let name = catalogNonEmptyString(value) {
      return MCPToolCatalogEntry(name: name)
    }
    guard let row = catalogObject(value), let name = catalogNonEmptyString(row["name"]) else {
      return nil
    }
    return MCPToolCatalogEntry(
      name: name,
      description: catalogString(row["description"]) ?? ""
    )
  }
}

private func decodeMCPHealth(_ row: [String: JSONValue]) -> MCPServerHealth {
  if catalogBool(row["disabled"]) == true { return .disabled }
  if catalogBool(row["connected"]) == true { return .connected }
  guard let raw = catalogNonEmptyString(row["health"] ?? row["status"])?.lowercased()
  else { return .unknown }
  return MCPServerHealth(rawValue: raw) ?? .unknown
}

private func decodeReloadResult(_ value: JSONValue, method: String) throws
  -> CapabilityCatalogReloadResult {
  guard let root = catalogObject(value), let result = catalogObject(root["result"]) else {
    throw CapabilityCatalogError.malformedResponse(method: method)
  }
  return CapabilityCatalogReloadResult(
    added: decodeReloadNames(result["added"]),
    removed: decodeReloadNames(result["removed"]),
    total: max(0, catalogInt(result["total"]) ?? 0)
  )
}

private func decodeReloadNames(_ value: JSONValue?) -> [String] {
  (catalogArray(value) ?? []).compactMap { item in
    catalogNonEmptyString(item) ?? catalogObject(item).flatMap { catalogNonEmptyString($0["name"]) }
  }
}

// MARK: - Loss-tolerant JSON access

private func catalogObject(_ value: JSONValue?) -> [String: JSONValue]? {
  guard case let .object(object)? = value else { return nil }
  return object
}

private func catalogArray(_ value: JSONValue?) -> [JSONValue]? {
  guard case let .array(array)? = value else { return nil }
  return array
}

private func catalogString(_ value: JSONValue?) -> String? {
  guard case let .string(string)? = value else { return nil }
  return string
}

private func catalogNonEmptyString(_ value: JSONValue?) -> String? {
  nonEmptyString(catalogString(value))
}

private func nonEmptyString(_ value: String?) -> String? {
  guard let string = value?.trimmingCharacters(in: .whitespacesAndNewlines),
        !string.isEmpty else { return nil }
  return string
}

private func catalogBool(_ value: JSONValue?) -> Bool? {
  switch value {
  case let .bool(bool):
    bool
  case let .number(number):
    number == 1 ? true : number == 0 ? false : nil
  case let .string(string):
    switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "true", "yes", "1": true
    case "false", "no", "0": false
    default: nil
    }
  default:
    nil
  }
}

private func catalogInt(_ value: JSONValue?) -> Int? {
  switch value {
  case let .number(number): Int(number)
  case let .string(string): Double(string).map(Int.init)
  default: nil
  }
}

/// Clamp MCP transport metadata to a short identifier. A URL, command line, env value, or
/// arbitrary config blob on the wire cannot cross into the public model through this field.
private func safeCatalogTransport(_ value: JSONValue?) -> String {
  guard let raw = catalogString(value)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        !raw.isEmpty,
        raw.count <= 32,
        raw.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
        }) else { return "" }
  return raw
}
