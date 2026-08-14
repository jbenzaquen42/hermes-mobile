import ComposableArchitecture
import DependenciesMacros
import Foundation

public enum ProfileAdminError: Error, Equatable, Sendable {
  /// The server authoritatively rejected the method as absent (`-32601`, or the legacy
  /// `unknown method` response) or unavailable in the current runtime (`4010`). Network
  /// failures and timeouts never map to this case.
  case unsupported
  case malformedResponse(method: String)
  case request(String)

  public var message: String {
    switch self {
    case .unsupported:
      "Profile administration is not supported by this Hermes server."
    case let .malformedResponse(method):
      "Hermes returned an unexpected \(method) response."
    case let .request(message):
      message
    }
  }

  init(_ error: any Error, method: String) {
    if let error = error as? ProfileAdminError {
      self = error
    } else if let error = error as? GatewayError {
      self = error.isUnsupportedOperation ? .unsupported : .request(error.message)
    } else {
      // Do not pass arbitrary localized descriptions through: transport implementations can
      // include URLs, query credentials, or server paths in those strings.
      self = .request("Couldn’t complete \(method).")
    }
  }
}

/// Native profile administration over Hermes' JSON-RPC gateway.
///
/// Each operation accepts a `ServerConnection` and owns a fresh, one-shot gateway connection.
/// It never borrows the app's long-lived chat `HermesGatewayClient`: doing so would share its
/// `ConnectionStore`, and a Settings request could replace the socket that routes live-chat
/// responses. The isolated connection also follows the normal cookie-ticket authentication
/// path, sends one request after `gateway.ready`, and always disconnects.
///
/// Rename/delete and profile-scoped session listing intentionally remain on
/// `HermesProfileClient`, matching the Hermes Agent surfaces that still expose those writes
/// through REST.
@DependencyClient
public struct HermesProfileAdminClient: Sendable {
  public var list: @Sendable (
    _ connection: ServerConnection,
    _ includeSessions: Bool
  ) async throws -> [ProfileAdminSummary]
  public var create: @Sendable (
    _ connection: ServerConnection,
    _ request: ProfileCreateRequest
  ) async throws -> ProfileCreateResult
  public var describe: @Sendable (
    _ connection: ServerConnection,
    _ name: String
  ) async throws -> ProfileDescription
  public var configure: @Sendable (
    _ connection: ServerConnection,
    _ request: ProfileConfigureRequest
  ) async throws -> ProfileConfigureResult
}

public extension HermesProfileAdminClient {
  static func live(
    session: URLSession = .shared,
    gatewayReadyTimeoutNanoseconds: UInt64 = 10_000_000_000
  ) -> HermesProfileAdminClient {
    .make(gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds) {
      HermesGatewayClient.live(session: session)
    }
  }

  /// Testable core with an injectable gateway factory. The factory is invoked once per RPC,
  /// which pins the production isolation guarantee in contract tests.
  static func make(
    gatewayReadyTimeoutNanoseconds: UInt64 = 10_000_000_000,
    makeGateway: @escaping @Sendable () -> HermesGatewayClient
  ) -> HermesProfileAdminClient {
    HermesProfileAdminClient(
      list: { connection, includeSessions in
        let result = try await profileRPC(
          connection: connection,
          method: "profiles.list",
          params: .object(["include_sessions": .bool(includeSessions)]),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeProfileList(result)
      },
      create: { connection, request in
        let method = "profiles.create"
        let result = try await profileRPC(
          connection: connection,
          method: method,
          params: request.rpcParams,
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeProfileCreate(result, request: request, method: method)
      },
      describe: { connection, name in
        let method = "profiles.describe"
        let result = try await profileRPC(
          connection: connection,
          method: method,
          params: .object(["name": .string(name)]),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeProfileDescription(result, requestedName: name, method: method)
      },
      configure: { connection, request in
        let method = "profiles.configure"
        let result = try await profileRPC(
          connection: connection,
          method: method,
          params: request.rpcParams,
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeProfileConfigure(result, request: request, method: method)
      }
    )
  }
}

extension HermesProfileAdminClient: DependencyKey {
  public static var liveValue: HermesProfileAdminClient { .live() }
  public static var testValue: HermesProfileAdminClient { HermesProfileAdminClient() }
}

public extension DependencyValues {
  var hermesProfileAdmin: HermesProfileAdminClient {
    get { self[HermesProfileAdminClient.self] }
    set { self[HermesProfileAdminClient.self] = newValue }
  }
}

// MARK: - Isolated one-shot transport

private func profileRPC(
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
    try await waitForGatewayReady(
      events,
      timeoutNanoseconds: gatewayReadyTimeoutNanoseconds
    )
    return try await gateway.send(method, params)
  } catch {
    throw ProfileAdminError(error, method: method)
  }
}

private func waitForGatewayReady(
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

private extension ProfileCreateRequest {
  var rpcParams: JSONValue {
    var params: [String: JSONValue] = [
      "name": .string(name),
      "clone_all": .bool(cloneAll),
      "no_skills": .bool(noSkills),
      "mirror_credentials": .bool(mirrorCredentials),
      "share_auth": .bool(shareAuthentication),
    ]
    if let descriptionText { params["description"] = .string(descriptionText) }
    if let cloneFrom { params["clone_from"] = .string(cloneFrom) }
    if let soul { params["soul"] = .string(soul) }
    if let model {
      params["provider"] = .string(model.provider)
      params["model"] = .string(model.defaultModel)
    }
    return .object(params)
  }
}

private extension ProfileConfigureRequest {
  var rpcParams: JSONValue {
    var params: [String: JSONValue] = ["name": .string(name)]
    if let descriptionText { params["description"] = .string(descriptionText) }
    if let soul { params["soul"] = .string(soul) }
    if let model {
      params["provider"] = .string(model.provider)
      params["model"] = .string(model.defaultModel)
    }
    if let reasoningEffort { params["reasoning_effort"] = .string(reasoningEffort) }
    if let disabledSkills { params["disabled_skills"] = .array(disabledSkills.map(JSONValue.string)) }
    if let enabledToolsets { params["enabled_toolsets"] = .array(enabledToolsets.map(JSONValue.string)) }
    if let enabledMCPServers {
      params["enabled_mcp_servers"] = .array(enabledMCPServers.map(JSONValue.string))
    }
    return .object(params)
  }
}

// MARK: - Lenient response mapping

private func decodeProfileList(_ value: JSONValue) throws -> [ProfileAdminSummary] {
  guard let root = rpcObject(value), let rows = rpcArray(root["profiles"]) else {
    throw ProfileAdminError.malformedResponse(method: "profiles.list")
  }
  return rows.compactMap { rowValue in
    guard let row = rpcObject(rowValue), let name = rpcNonEmptyString(row["name"]) else {
      return nil
    }
    return ProfileAdminSummary(
      name: name,
      isDefault: rpcBool(row["is_default"]) ?? false,
      model: rpcNonEmptyString(row["model"]),
      provider: rpcNonEmptyString(row["provider"]),
      profileDescription: rpcString(row["description"]) ?? "",
      skillCount: max(0, rpcInt(row["skill_count"]) ?? 0),
      hasAvatar: rpcBool(row["has_avatar"]) ?? false,
      lastSession: decodeLastSession(row["last_session"])
    )
  }
}

private func decodeLastSession(_ value: JSONValue?) -> ProfileLastSessionSummary? {
  guard let row = rpcObject(value), let id = rpcNonEmptyString(row["id"]) else { return nil }
  return ProfileLastSessionSummary(
    id: id,
    title: rpcString(row["title"]) ?? "",
    preview: rpcString(row["preview"]) ?? "",
    startedAt: rpcDouble(row["started_at"]).map(Date.init(timeIntervalSince1970:)),
    lastActive: rpcDouble(row["last_active"]).map(Date.init(timeIntervalSince1970:)),
    messageCount: max(0, rpcInt(row["message_count"]) ?? 0)
  )
}

private func decodeProfileCreate(
  _ value: JSONValue,
  request: ProfileCreateRequest,
  method: String
) throws -> ProfileCreateResult {
  guard let root = rpcObject(value) else {
    throw ProfileAdminError.malformedResponse(method: method)
  }

  var mirrored: ProfileCredentialMirroring?
  if let raw = rpcObject(root["mirrored"]) {
    let authentication: ProfileAuthenticationMirroring
    if rpcBool(raw["auth"]) == true {
      authentication = .copied
    } else if rpcBool(raw["auth"]) == false {
      authentication = .none
    } else if rpcString(raw["auth"])?.lowercased() == "shared" {
      authentication = .shared
    } else if raw["auth"] != nil {
      authentication = .unknown
    } else {
      authentication = .none
    }
    mirrored = ProfileCredentialMirroring(
      environmentCopied: rpcBool(raw["env"]) ?? false,
      authentication: authentication,
      modelInherited: rpcBool(raw["model_inherited"]) ?? false,
      voiceInherited: rpcBool(raw["voice"]) ?? false
    )
  }

  return ProfileCreateResult(
    ok: rpcBool(root["ok"]) ?? true,
    name: rpcNonEmptyString(root["name"]) ?? request.name,
    soulWritten: rpcBool(root["soul_written"]),
    modelSet: rpcBool(root["model_set"]),
    mirrored: mirrored
  )
}

private func decodeProfileDescription(
  _ value: JSONValue,
  requestedName: String,
  method: String
) throws -> ProfileDescription {
  guard let root = rpcObject(value) else {
    throw ProfileAdminError.malformedResponse(method: method)
  }

  let model = rpcObject(root["model"]) ?? [:]
  let reasoning = rpcNonEmptyString(root["reasoning_effort"])
    ?? rpcNonEmptyString(model["reasoning_effort"])
    ?? rpcNonEmptyString(model["reasoning"])

  let skills = (rpcArray(root["skills"]) ?? []).compactMap { value -> ProfileSkill? in
    guard let row = rpcObject(value), let name = rpcNonEmptyString(row["name"]) else {
      return nil
    }
    return ProfileSkill(name: name, enabled: rpcBool(row["enabled"]) ?? true)
  }

  let toolsets = (rpcArray(root["toolsets"]) ?? []).compactMap { value -> ProfileToolset? in
    guard let row = rpcObject(value), let name = rpcNonEmptyString(row["name"]) else {
      return nil
    }
    return ProfileToolset(
      name: name,
      label: rpcString(row["label"]) ?? name,
      toolsetDescription: rpcString(row["description"]) ?? "",
      toolCount: max(0, rpcInt(row["tool_count"]) ?? 0),
      enabled: rpcBool(row["enabled"]) ?? true
    )
  }

  let mcpServers = (rpcArray(root["mcp_servers"]) ?? []).compactMap {
    value -> ProfileMCPServer? in
    guard let row = rpcObject(value), let name = rpcNonEmptyString(row["name"]) else {
      return nil
    }
    return ProfileMCPServer(
      name: name,
      enabled: rpcBool(row["enabled"]) ?? true,
      transport: safeMCPTransport(row["transport"])
    )
  }

  return ProfileDescription(
    name: rpcNonEmptyString(root["name"]) ?? requestedName,
    description: rpcString(root["description"]) ?? "",
    soul: rpcString(root["soul"]) ?? "",
    model: ProfileModelConfiguration(
      provider: rpcString(model["provider"]) ?? "",
      defaultModel: rpcString(model["default"]) ?? ""
    ),
    reasoningEffort: reasoning,
    skills: skills,
    toolsets: toolsets,
    toolsetsPinned: rpcBool(root["toolsets_pinned"]) ?? false,
    mcpServers: mcpServers
  )
}

private func decodeProfileConfigure(
  _ value: JSONValue,
  request: ProfileConfigureRequest,
  method: String
) throws -> ProfileConfigureResult {
  guard let root = rpcObject(value) else {
    throw ProfileAdminError.malformedResponse(method: method)
  }
  let rawApplied = rpcObject(root["applied"]) ?? [:]
  var statuses: [ProfileConfigureSection: ProfileConfigureStatus] = [:]

  for section in request.requestedSections {
    let raw: JSONValue?
    switch section {
    case .reasoningEffort:
      raw = rawApplied[section.rawValue] ?? rawApplied["reasoning"]
    default:
      raw = rawApplied[section.rawValue]
    }
    if let applied = rpcBool(raw) {
      statuses[section] = applied ? .applied : .failed
    } else {
      statuses[section] = .notReported
    }
  }

  let knownKeys = Set(ProfileConfigureSection.allCases.map(\.rawValue) + ["reasoning"])
  let unknown = rawApplied.reduce(into: [String: Bool]()) { output, pair in
    guard !knownKeys.contains(pair.key), let applied = rpcBool(pair.value) else { return }
    output[pair.key] = applied
  }
  let derivedOK = rawApplied.values.allSatisfy { rpcBool($0) != false }

  return ProfileConfigureResult(
    ok: rpcBool(root["ok"]) ?? derivedOK,
    requestedSections: request.requestedSections,
    sectionStatuses: statuses,
    unknownAppliedSections: unknown
  )
}

// MARK: - Loss-tolerant JSON access

private func rpcObject(_ value: JSONValue?) -> [String: JSONValue]? {
  guard case let .object(object)? = value else { return nil }
  return object
}

private func rpcArray(_ value: JSONValue?) -> [JSONValue]? {
  guard case let .array(array)? = value else { return nil }
  return array
}

private func rpcString(_ value: JSONValue?) -> String? {
  guard case let .string(string)? = value else { return nil }
  return string
}

private func rpcNonEmptyString(_ value: JSONValue?) -> String? {
  guard let string = rpcString(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !string.isEmpty else { return nil }
  return string
}

private func rpcBool(_ value: JSONValue?) -> Bool? {
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

private func rpcDouble(_ value: JSONValue?) -> Double? {
  switch value {
  case let .number(number): number
  case let .string(string): Double(string)
  default: nil
  }
}

private func rpcInt(_ value: JSONValue?) -> Int? {
  rpcDouble(value).map(Int.init)
}

/// Hermes currently emits short transport hints (`stdio`, `http`, `sse`). Clamp this field
/// before it reaches public state so a malformed or hostile server cannot smuggle a URL,
/// credential, command line, or arbitrary config value through a metadata-only model.
private func safeMCPTransport(_ value: JSONValue?) -> String {
  guard let raw = rpcString(value)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        !raw.isEmpty,
        raw.count <= 32,
        raw.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            .contains($0)
        }) else { return "" }
  return raw
}
