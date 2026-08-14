import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@Suite struct HermesLearningClientTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "https://hermes.test:9119")!,
    token: "secret-token"
  )

  private func client(
    disconnectCount: LockIsolated<Int> = LockIsolated(0),
    factoryCount: LockIsolated<Int> = LockIsolated(0),
    connectAuth: LockIsolated<AuthSession?> = LockIsolated(nil),
    send: @escaping @Sendable (String, JSONValue) async throws -> JSONValue
  ) -> HermesLearningClient {
    .make {
      factoryCount.withValue { $0 += 1 }
      var gateway = HermesGatewayClient()
      gateway.connect = { _, auth in
        connectAuth.setValue(auth)
        return AsyncStream { continuation in
          continuation.yield(.ready)
        }
      }
      gateway.send = send
      gateway.disconnect = {
        disconnectCount.withValue { $0 += 1 }
      }
      return gateway
    }
  }

  @Test func loadUsesBoundedNativeFramesAndMapsThreeKindsWithoutPreviewContent() async throws {
    let call = LockIsolated<(String, JSONValue)?>(nil)
    let learning = client { method, params in
      call.setValue((method, params))
      return .object([
        "frames": .array([
          .object([
            "grid": .array([.string("terminal art")]),
            "labels": .array([]),
          ]),
        ]),
        "buckets": .array([
          .object([
            "date": .string("2026-08-01"),
            "nodes": .array([
              .object([
                "id": .string("memory:memory:0"),
                "label": .string("Agent secret pre…"),
                "fullLabel": .string("Agent secret preference"),
                "body": .string("Bearer private-memory-body"),
                "style": .object(["color": .string("#fff")]),
              ]),
              .object([
                "id": .string("memory:profile:1"),
                "label": .string("User prefers concise replies"),
                "body": .string("User private profile body"),
              ]),
              .object([
                "id": .string("swift-review"),
                "label": .string("Swift review"),
                "body": .string(""),
              ]),
              .object([
                "id": .string("memory:future:2"),
                "label": .string("Unknown future source"),
              ]),
              .object(["label": .string("missing id")]),
            ]),
          ]),
          // Duplicate node ids are ignored so Identifiable collections stay safe.
          .object([
            "nodes": .array([
              .object([
                "id": .string("swift-review"),
                "label": .string("duplicate"),
              ]),
            ]),
          ]),
        ]),
        "count": .string("4"),
        "cols": .number(80),
        "rows": .number(24),
        "private_path": .string("/srv/private/.hermes/memories/MEMORY.md"),
      ])
    }

    let snapshot = try await learning.load(connection)

    #expect(call.value?.0 == "learning.frames")
    #expect(call.value?.1 == .object([
      "cols": .number(80),
      "rows": .number(24),
      "frames": .number(2),
    ]))
    #expect(snapshot.entries == [
      LearningEntrySummary(
        id: "memory:memory:0", label: "Agent secret preference", kind: .agentMemory
      ),
      LearningEntrySummary(
        id: "memory:profile:1", label: "User prefers concise replies", kind: .userProfile
      ),
      LearningEntrySummary(id: "swift-review", label: "Swift review", kind: .learnedSkill),
    ])
    #expect(snapshot.reportedCount == 4)
    // Current learning.frames has no authoritative capacity/config payload. Preview bodies
    // are truncated, so the client must not fabricate usage or assume default limits.
    #expect(snapshot.capacity == nil)
    #expect(snapshot.metadata.profileScope == .serverDefaultProfile)
    #expect(snapshot.metadata.memoryRefreshPolicy == .freshSessionSnapshot)
    #expect(snapshot.metadata.rawDocumentReplacement == .unsupported)
    #expect(snapshot.metadata.capacityReporting == .notReportedByServer)
    #expect(snapshot.metadata.memoryRefreshPolicy.explanation.contains("fresh session"))

    let diagnostic = String(reflecting: snapshot)
    #expect(!diagnostic.contains("private-memory-body"))
    #expect(!diagnostic.contains("Agent secret preference"))
    #expect(!diagnostic.contains("User private profile body"))
    #expect(!diagnostic.contains("/srv/private"))
  }

  @Test func detailUsesStableIDSourceAndRedactsFullContentFromDiagnostics() async throws {
    let call = LockIsolated<(String, JSONValue)?>(nil)
    let learning = client { method, params in
      call.setValue((method, params))
      return .object([
        "ok": .string("true"),
        "kind": .string("memory"),
        "id": .string("memory:profile:3"),
        "label": .string("User API preference"),
        "content": .string("User API key is top-secret"),
        "path": .string("/private/USER.md"),
      ])
    }

    let detail = try await learning.detail(connection, "memory:profile:3")

    #expect(call.value?.0 == "learning.detail")
    #expect(call.value?.1 == .object(["id": .string("memory:profile:3")]))
    #expect(detail == LearningEntryDetail(
      id: "memory:profile:3",
      label: "User API preference",
      kind: .userProfile,
      content: "User API key is top-secret"
    ))
    let diagnostic = String(reflecting: detail)
    #expect(!diagnostic.contains("top-secret"))
    #expect(!diagnostic.contains("User API preference"))
    #expect(!diagnostic.contains("/private"))
  }

  @Test func editPinsContentAndReturnsNativeLogicalFailureWithoutThrowing() async throws {
    let call = LockIsolated<(String, JSONValue)?>(nil)
    let request = LearningEditRequest(
      id: "memory:memory:0",
      content: "Replacement contains private-token"
    )
    let learning = client { method, params in
      call.setValue((method, params))
      return .object([
        "ok": .bool(false),
        "message": .string("empty memory — use delete to remove it"),
      ])
    }

    let result = try await learning.edit(connection, request)

    #expect(call.value?.0 == "learning.edit")
    #expect(call.value?.1 == .object([
      "id": .string("memory:memory:0"),
      "content": .string("Replacement contains private-token"),
    ]))
    #expect(result == LearningMutationResult(
      succeeded: false,
      id: "memory:memory:0",
      action: .updated,
      message: "empty memory — use delete to remove it"
    ))
    #expect(!String(reflecting: request).contains("private-token"))
    #expect(!String(reflecting: result).contains("empty memory"))
  }

  @Test func deleteRemovesMemoriesButReportsSkillArchiveSemantics() async throws {
    let calls = LockIsolated<[(String, JSONValue)]>([])
    let learning = client { method, params in
      calls.withValue { $0.append((method, params)) }
      return .object(["ok": .bool(true), "message": .string("done")])
    }

    let agentMemory = try await learning.delete(connection, "memory:memory:0")
    let userProfile = try await learning.delete(connection, "memory:profile:4")
    let skill = try await learning.delete(connection, "swift-review")

    let captured = calls.value
    #expect(captured.count == 3)
    #expect(captured[0].0 == "learning.delete")
    #expect(captured[0].1 == .object(["id": .string("memory:memory:0")]))
    #expect(captured[1].0 == "learning.delete")
    #expect(captured[1].1 == .object(["id": .string("memory:profile:4")]))
    #expect(captured[2].0 == "learning.delete")
    #expect(captured[2].1 == .object(["id": .string("swift-review")]))
    #expect(agentMemory.action == .deleted)
    #expect(userProfile.action == .deleted)
    #expect(skill.action == .archived)
    #expect(agentMemory.succeeded && userProfile.succeeded && skill.succeeded)
  }

  @Test func everyOperationUsesAndDisconnectsAFreshAuthenticatedGateway() async throws {
    let factories = LockIsolated(0)
    let disconnects = LockIsolated(0)
    let auth = LockIsolated<AuthSession?>(nil)
    let learning = client(
      disconnectCount: disconnects,
      factoryCount: factories,
      connectAuth: auth
    ) { method, params in
      switch method {
      case "learning.frames":
        return .object(["buckets": .array([]), "count": .number(0)])
      case "learning.detail":
        guard case let .object(object) = params,
              case let .string(id)? = object["id"] else { return .object([:]) }
        return .object([
          "ok": .bool(true), "id": .string(id), "label": .string("label"),
          "content": .string("content"),
        ])
      case "learning.edit", "learning.delete":
        return .object(["ok": .bool(true), "message": .string("done")])
      default:
        return .object([:])
      }
    }

    _ = try await learning.load(connection)
    _ = try await learning.detail(connection, "memory:memory:0")
    _ = try await learning.edit(
      connection,
      LearningEditRequest(id: "memory:memory:0", content: "changed")
    )
    _ = try await learning.delete(connection, "memory:memory:0")

    #expect(factories.value == 4)
    #expect(disconnects.value == 4)
    #expect(auth.value == .token("secret-token"))
  }

  @Test func unsupportedMappingUsesOnlyAuthoritativeGatewayErrors() async throws {
    for gatewayError in [
      GatewayError.rpc(code: -32601, message: "unknown method: learning.frames"),
      GatewayError.rpc(code: 4010, message: "unsupported operation"),
      GatewayError.server("unknown method: learning.frames"),
    ] {
      let learning = client { _, _ in throw gatewayError }
      await #expect(throws: LearningClientError.unsupported) {
        _ = try await learning.load(connection)
      }
    }

    let vagueServerError = client { _, _ in
      throw GatewayError.server("learning is not supported at /srv/private")
    }
    let requestError = await #expect(throws: LearningClientError.self) {
      _ = try await vagueServerError.load(connection)
    }
    #expect(requestError == .request("Hermes rejected learning.frames."))

    let codedFailure = client { _, _ in
      throw GatewayError.rpc(code: 5000, message: "failed at /srv/private with token=secret")
    }
    let codedError = await #expect(throws: LearningClientError.self) {
      _ = try await codedFailure.load(connection)
    }
    #expect(codedError == .request("Hermes rejected learning.frames."))

    let arbitraryTransport = client { _, _ in
      throw NSError(
        domain: "https://secret.internal?ticket=abc",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Bearer top-secret"]
      )
    }
    let redacted = await #expect(throws: LearningClientError.self) {
      _ = try await arbitraryTransport.load(connection)
    }
    #expect(redacted == .request("Couldn’t complete learning.frames."))

    let timeout = client { _, _ in throw GatewayError.timedOut(method: "learning.frames") }
    let timeoutError = await #expect(throws: LearningClientError.self) {
      _ = try await timeout.load(connection)
    }
    #expect(timeoutError == .request("request timed out: learning.frames"))
  }

  @Test func malformedResponsesAndRejectedDetailAreNotEmptySuccess() async throws {
    let malformedFrames = client { _, _ in .object(["frames": .array([])]) }
    await #expect(throws: LearningClientError.malformedResponse(method: "learning.frames")) {
      _ = try await malformedFrames.load(connection)
    }

    let malformedMutation = client { _, _ in .object(["message": .string("missing ok")]) }
    await #expect(throws: LearningClientError.malformedResponse(method: "learning.delete")) {
      _ = try await malformedMutation.delete(connection, "memory:memory:0")
    }

    let rejectedDetail = client { _, _ in
      .object(["ok": .bool(false), "message": .string("stale id at /private/path")])
    }
    let error = await #expect(throws: LearningClientError.self) {
      _ = try await rejectedDetail.detail(connection, "memory:profile:99")
    }
    #expect(error == .operationRejected(method: "learning.detail"))
    if let error {
      #expect(!error.message.contains("/private"))
    }
  }
}
