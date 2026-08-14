import ComposableArchitecture
import DependenciesMacros
import Foundation

public enum LearningClientError: Error, Equatable, Sendable {
  /// Only an authoritative JSON-RPC unknown/unavailable response maps here.
  case unsupported
  case malformedResponse(method: String)
  case operationRejected(method: String)
  case request(String)

  public var message: String {
    switch self {
    case .unsupported:
      "Learning management is not supported by this Hermes server."
    case let .malformedResponse(method):
      "Hermes returned an unexpected \(method) response."
    case let .operationRejected(method):
      "Hermes could not complete \(method). Refresh the learning list and try again."
    case let .request(message):
      message
    }
  }

  init(_ error: any Error, method: String) {
    if let error = error as? LearningClientError {
      self = error
      return
    }
    guard let error = error as? GatewayError else {
      // Arbitrary localized descriptions can contain URLs, tickets, or server-local paths.
      self = .request("Couldn’t complete \(method).")
      return
    }
    if error.isUnsupportedOperation {
      self = .unsupported
      return
    }
    switch error {
    case .notConnected:
      self = .request("Not connected.")
    case .disconnected:
      self = .request("Connection lost.")
    case let .timedOut(timedOutMethod):
      self = .request("request timed out: \(timedOutMethod)")
    case .authExpired:
      self = .request("Your session expired. Sign in again.")
    case .ticketUnavailable:
      self = .request("Couldn’t obtain a connection ticket.")
    case .server(_), .rpc(_, _), .malformedResponse(_):
      // Server messages can interpolate a node id, path, or exception detail. Keep them out
      // of public diagnostics while preserving this as a retryable/non-capability failure.
      self = .request("Hermes rejected \(method).")
    }
  }
}

/// Typed access to Hermes' entry-level learning graph and mutation RPCs.
///
/// Each operation creates a fresh gateway, waits for `gateway.ready`, performs one native
/// request, and disconnects. The RPCs have no profile parameter and resolve the server's
/// default Hermes home, so this client intentionally accepts no profile selector.
@DependencyClient
public struct HermesLearningClient: Sendable {
  public var load: @Sendable (
    _ connection: ServerConnection
  ) async throws -> LearningSnapshot
  public var detail: @Sendable (
    _ connection: ServerConnection,
    _ id: String
  ) async throws -> LearningEntryDetail
  public var edit: @Sendable (
    _ connection: ServerConnection,
    _ request: LearningEditRequest
  ) async throws -> LearningMutationResult
  /// Calls native `learning.delete`: memories are removed, while learned skills are archived.
  public var delete: @Sendable (
    _ connection: ServerConnection,
    _ id: String
  ) async throws -> LearningMutationResult
}

public extension HermesLearningClient {
  static func live(
    session: URLSession = .shared,
    gatewayReadyTimeoutNanoseconds: UInt64 = 10_000_000_000
  ) -> HermesLearningClient {
    .make(gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds) {
      HermesGatewayClient.live(session: session)
    }
  }

  static func make(
    gatewayReadyTimeoutNanoseconds: UInt64 = 10_000_000_000,
    makeGateway: @escaping @Sendable () -> HermesGatewayClient
  ) -> HermesLearningClient {
    HermesLearningClient(
      load: { connection in
        let method = "learning.frames"
        let value = try await learningRPC(
          connection: connection,
          method: method,
          // Two frames is the native minimum and keeps the one-shot response bounded. The
          // complete typed node inventory lives in `buckets`, independent of animation frames.
          params: .object([
            "cols": .number(80),
            "rows": .number(24),
            "frames": .number(2),
          ]),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeLearningSnapshot(value, method: method)
      },
      detail: { connection, id in
        let method = "learning.detail"
        let value = try await learningRPC(
          connection: connection,
          method: method,
          params: .object(["id": .string(id)]),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeLearningDetail(value, requestedID: id, method: method)
      },
      edit: { connection, request in
        let method = "learning.edit"
        let value = try await learningRPC(
          connection: connection,
          method: method,
          params: .object([
            "id": .string(request.id),
            "content": .string(request.content),
          ]),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        return try decodeLearningMutation(
          value,
          id: request.id,
          action: .updated,
          method: method
        )
      },
      delete: { connection, id in
        let method = "learning.delete"
        let value = try await learningRPC(
          connection: connection,
          method: method,
          params: .object(["id": .string(id)]),
          gatewayReadyTimeoutNanoseconds: gatewayReadyTimeoutNanoseconds,
          makeGateway: makeGateway
        )
        let action: LearningMutationAction = learningKind(forID: id) == .learnedSkill
          ? .archived
          : .deleted
        return try decodeLearningMutation(value, id: id, action: action, method: method)
      }
    )
  }
}

extension HermesLearningClient: DependencyKey {
  public static var liveValue: HermesLearningClient { .live() }
  public static var testValue: HermesLearningClient { HermesLearningClient() }
}

public extension DependencyValues {
  var hermesLearning: HermesLearningClient {
    get { self[HermesLearningClient.self] }
    set { self[HermesLearningClient.self] = newValue }
  }
}

// MARK: - Isolated one-shot transport

private func learningRPC(
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
    try await waitForLearningGatewayReady(
      events,
      timeoutNanoseconds: gatewayReadyTimeoutNanoseconds
    )
    return try await gateway.send(method, params)
  } catch {
    throw LearningClientError(error, method: method)
  }
}

private func waitForLearningGatewayReady(
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

// MARK: - Response mapping

private func decodeLearningSnapshot(_ value: JSONValue, method: String) throws
  -> LearningSnapshot
{
  guard let root = learningObject(value), let buckets = learningArray(root["buckets"]) else {
    throw LearningClientError.malformedResponse(method: method)
  }

  var seen = Set<String>()
  var entries: [LearningEntrySummary] = []
  for bucketValue in buckets {
    guard let bucket = learningObject(bucketValue) else { continue }
    for nodeValue in learningArray(bucket["nodes"]) ?? [] {
      guard let node = learningObject(nodeValue),
            let id = learningNonEmptyString(node["id"]),
            let kind = learningKind(forID: id),
            !seen.contains(id) else { continue }
      let label = learningString(node["fullLabel"])
        ?? learningString(node["label"])
        ?? id
      seen.insert(id)
      entries.append(LearningEntrySummary(id: id, label: label, kind: kind))
    }
  }

  return LearningSnapshot(
    entries: entries,
    reportedCount: max(0, learningInt(root["count"]) ?? entries.count),
    // Current learning.frames responses expose neither usage nor configured limits. The
    // graph's truncated preview bodies cannot produce an authoritative character count.
    capacity: nil,
    metadata: LearningSnapshotMetadata()
  )
}

private func decodeLearningDetail(
  _ value: JSONValue,
  requestedID: String,
  method: String
) throws -> LearningEntryDetail {
  guard let root = learningObject(value), let ok = learningBool(root["ok"]) else {
    throw LearningClientError.malformedResponse(method: method)
  }
  guard ok else { throw LearningClientError.operationRejected(method: method) }
  guard let id = learningNonEmptyString(root["id"]) ?? nonEmptyLearningString(requestedID),
        let label = learningString(root["label"]),
        let content = learningString(root["content"]),
        let kind = learningKind(forID: id) else {
    throw LearningClientError.malformedResponse(method: method)
  }
  return LearningEntryDetail(id: id, label: label, kind: kind, content: content)
}

private func decodeLearningMutation(
  _ value: JSONValue,
  id: String,
  action: LearningMutationAction,
  method: String
) throws -> LearningMutationResult {
  guard let root = learningObject(value), let ok = learningBool(root["ok"]) else {
    throw LearningClientError.malformedResponse(method: method)
  }
  return LearningMutationResult(
    succeeded: ok,
    id: id,
    action: action,
    message: learningString(root["message"]) ?? ""
  )
}

private func learningKind(forID id: String) -> LearningEntryKind? {
  if id.hasPrefix("memory:memory:") { return .agentMemory }
  if id.hasPrefix("memory:profile:") { return .userProfile }
  if id.hasPrefix("memory:") { return nil }
  return nonEmptyLearningString(id) == nil ? nil : .learnedSkill
}

private func learningObject(_ value: JSONValue?) -> [String: JSONValue]? {
  guard case let .object(object)? = value else { return nil }
  return object
}

private func learningArray(_ value: JSONValue?) -> [JSONValue]? {
  guard case let .array(array)? = value else { return nil }
  return array
}

private func learningString(_ value: JSONValue?) -> String? {
  guard case let .string(string)? = value else { return nil }
  return string
}

private func learningNonEmptyString(_ value: JSONValue?) -> String? {
  nonEmptyLearningString(learningString(value))
}

private func nonEmptyLearningString(_ value: String?) -> String? {
  guard let string = value?.trimmingCharacters(in: .whitespacesAndNewlines),
        !string.isEmpty else { return nil }
  return string
}

private func learningBool(_ value: JSONValue?) -> Bool? {
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

private func learningInt(_ value: JSONValue?) -> Int? {
  switch value {
  case let .number(number): Int(number)
  case let .string(string): Double(string).map(Int.init)
  default: nil
  }
}
