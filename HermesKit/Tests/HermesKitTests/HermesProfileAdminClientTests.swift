import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@Suite struct HermesProfileAdminClientTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "https://hermes.test:9119")!,
    token: "secret-token"
  )

  private func client(
    disconnectCount: LockIsolated<Int> = LockIsolated(0),
    factoryCount: LockIsolated<Int> = LockIsolated(0),
    connectAuth: LockIsolated<AuthSession?> = LockIsolated(nil),
    send: @escaping @Sendable (String, JSONValue) async throws -> JSONValue
  ) -> HermesProfileAdminClient {
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

  @Test func listUsesNativeMethodAndLenientlyMapsSafeFields() async throws {
    let call = LockIsolated<(String, JSONValue)?>(nil)
    let admin = client { method, params in
      call.setValue((method, params))
      return .object([
        "profiles": .array([
          .object([
            "name": .string("default"),
            "path": .string("/srv/private/.hermes"),
            "is_default": .string("yes"),
            "model": .string("gpt-5.5"),
            "provider": .string("openai"),
            "description": .string("Primary"),
            "skill_count": .string("4"),
            "has_avatar": .number(1),
            "last_session": .object([
              "id": .string("s1"),
              "title": .string("Latest"),
              "preview": .string("Safe preview"),
              "last_active": .string("1776200000"),
              "message_count": .number(8),
            ]),
            "future_field": .object(["ignored": .bool(true)]),
          ]),
          // A malformed future row must not discard otherwise valid profiles.
          .object(["description": .string("missing name")]),
        ]),
      ])
    }

    let rows = try await admin.list(connection, true)

    #expect(call.value?.0 == "profiles.list")
    #expect(call.value?.1 == .object(["include_sessions": .bool(true)]))
    #expect(rows.count == 1)
    let row = try #require(rows.first)
    #expect(row.name == "default")
    #expect(row.isDefault)
    #expect(row.model == "gpt-5.5")
    #expect(row.provider == "openai")
    #expect(row.profileDescription == "Primary")
    #expect(row.skillCount == 4)
    #expect(row.hasAvatar)
    #expect(row.lastSession?.id == "s1")
    #expect(row.lastSession?.messageCount == 8)
    // ProfileAdminSummary has no server-path member: the sensitive wire field is discarded.
  }

  @Test func createPinsExactWireShapeAndDecodesMirroringWithoutPaths() async throws {
    let call = LockIsolated<(String, JSONValue)?>(nil)
    let request = ProfileCreateRequest(
      name: "research",
      description: "Private profile description",
      cloneFrom: "default",
      cloneAll: true,
      noSkills: false,
      soul: "Never print this SOUL",
      model: ProfileModelConfiguration(provider: "openai", defaultModel: "gpt-secret-name"),
      mirrorCredentials: true,
      shareAuthentication: true
    )
    let admin = client { method, params in
      call.setValue((method, params))
      return .object([
        "ok": .bool(true),
        "name": .string("research"),
        "path": .string("/srv/private/research"),
        "soul_written": .bool(true),
        "model_set": .bool(true),
        "mirrored": .object([
          "env": .bool(true),
          "auth": .string("shared"),
          "model_inherited": .bool(false),
          "voice": .bool(true),
        ]),
      ])
    }

    let result = try await admin.create(connection, request)

    #expect(call.value?.0 == "profiles.create")
    #expect(call.value?.1 == .object([
      "name": .string("research"),
      "description": .string("Private profile description"),
      "clone_from": .string("default"),
      "clone_all": .bool(true),
      "no_skills": .bool(false),
      "soul": .string("Never print this SOUL"),
      "provider": .string("openai"),
      "model": .string("gpt-secret-name"),
      "mirror_credentials": .bool(true),
      "share_auth": .bool(true),
    ]))
    #expect(result.ok)
    #expect(result.name == "research")
    #expect(result.soulWritten == true)
    #expect(result.modelSet == true)
    #expect(result.mirrored?.environmentCopied == true)
    #expect(result.mirrored?.authentication == .shared)
    #expect(result.mirrored?.voiceInherited == true)

    let diagnostic = String(describing: request)
    #expect(!diagnostic.contains("Never print this SOUL"))
    #expect(!diagnostic.contains("Private profile description"))
    #expect(!diagnostic.contains("gpt-secret-name"))
  }

  @Test func describeMapsCompleteContractAndIgnoresMCPSecrets() async throws {
    let call = LockIsolated<(String, JSONValue)?>(nil)
    let admin = client { method, params in
      call.setValue((method, params))
      return .object([
        "name": .string("work"),
        "description": .string("Work profile"),
        "soul": .string("Sensitive persona text"),
        "model": .object([
          "provider": .string("nous"),
          "default": .string("hermes-4"),
          // Accepted as a compatibility location on newer servers.
          "reasoning_effort": .string("high"),
        ]),
        "skills": .array([
          .object(["name": .string("swift"), "enabled": .number(1)]),
          .object(["name": .string("disabled"), "enabled": .string("false")]),
          .object(["enabled": .bool(true)]),
        ]),
        "toolsets": .array([
          .object([
            "name": .string("web"),
            "label": .string("Web"),
            "description": .string("Browse"),
            "tool_count": .string("3"),
            "enabled": .bool(true),
          ]),
        ]),
        "toolsets_pinned": .string("true"),
        "mcp_servers": .array([
          .object([
            "name": .string("github"),
            "enabled": .bool(false),
            "transport": .string("http"),
            "url": .string("https://secret.internal/mcp"),
            "headers": .object(["Authorization": .string("Bearer secret")]),
            "env": .object(["TOKEN": .string("secret")]),
          ]),
        ]),
        "unknown": .array([.string("ignored")]),
      ])
    }

    let detail = try await admin.describe(connection, "work")

    #expect(call.value?.0 == "profiles.describe")
    #expect(call.value?.1 == .object(["name": .string("work")]))
    #expect(detail.name == "work")
    #expect(detail.description == "Work profile")
    #expect(detail.soul == "Sensitive persona text")
    #expect(detail.model == ProfileModelConfiguration(provider: "nous", defaultModel: "hermes-4"))
    #expect(detail.reasoningEffort == "high")
    #expect(detail.skills == [
      ProfileSkill(name: "swift", enabled: true),
      ProfileSkill(name: "disabled", enabled: false),
    ])
    #expect(detail.toolsets.first?.toolCount == 3)
    #expect(detail.toolsetsPinned)
    #expect(detail.mcpServers == [ProfileMCPServer(name: "github", enabled: false, transport: "http")])

    for diagnostic in [String(describing: detail), String(reflecting: detail)] {
      #expect(!diagnostic.contains("Sensitive persona text"))
      #expect(!diagnostic.contains("secret.internal"))
      #expect(!diagnostic.contains("Bearer secret"))
    }
  }

  @Test func configurePreservesReplaceSemanticsAndReportsEveryRequestedSection() async throws {
    let call = LockIsolated<(String, JSONValue)?>(nil)
    let request = ProfileConfigureRequest(
      name: "work",
      description: "Updated",
      soul: "New SOUL",
      model: ProfileModelConfiguration(provider: "openai", defaultModel: "gpt-5.5"),
      reasoningEffort: "xhigh",
      disabledSkills: ["legacy"],
      enabledToolsets: [],
      enabledMCPServers: ["github"]
    )
    let admin = client { method, params in
      call.setValue((method, params))
      return .object([
        "ok": .bool(false),
        "applied": .object([
          "description": .bool(true),
          "soul": .bool(false),
          "model": .bool(true),
          // Current Hermes omits reasoning; it must remain unreported rather than successful.
          "skills": .bool(true),
          "toolsets": .bool(true),
          "mcp_servers": .bool(false),
          "future_section": .bool(true),
        ]),
      ])
    }

    let result = try await admin.configure(connection, request)

    #expect(call.value?.0 == "profiles.configure")
    #expect(call.value?.1 == .object([
      "name": .string("work"),
      "description": .string("Updated"),
      "soul": .string("New SOUL"),
      "provider": .string("openai"),
      "model": .string("gpt-5.5"),
      "reasoning_effort": .string("xhigh"),
      "disabled_skills": .array([.string("legacy")]),
      // Empty is sent, not omitted: Hermes uses this to clear the explicit pin.
      "enabled_toolsets": .array([]),
      "enabled_mcp_servers": .array([.string("github")]),
    ]))
    #expect(result.status(for: .description) == .applied)
    #expect(result.status(for: .soul) == .failed)
    #expect(result.status(for: .model) == .applied)
    #expect(result.status(for: .reasoningEffort) == .notReported)
    #expect(result.status(for: .skills) == .applied)
    #expect(result.status(for: .toolsets) == .applied)
    #expect(result.status(for: .mcpServers) == .failed)
    #expect(result.failedSections == [.soul, .mcpServers])
    #expect(result.unreportedSections == [.reasoningEffort])
    #expect(result.unknownAppliedSections == ["future_section": true])
    #expect(!result.isCompleteSuccess)

    let diagnostic = String(describing: request)
    #expect(!diagnostic.contains("New SOUL"))
    #expect(!diagnostic.contains("github"))
    #expect(!diagnostic.contains("gpt-5.5"))
  }

  @Test func unsupportedMappingUsesOnlyAuthoritativeRPCErrors() async throws {
    for gatewayError in [
      GatewayError.rpc(code: -32601, message: "unknown method: profiles.describe"),
      GatewayError.rpc(code: 4010, message: "unsupported operation"),
      GatewayError.server("unknown method: profiles.describe"),
    ] {
      let admin = client { _, _ in throw gatewayError }
      await #expect(throws: ProfileAdminError.unsupported) {
        _ = try await admin.describe(connection, "work")
      }
    }

    let timedOut = client { _, _ in
      throw GatewayError.timedOut(method: "profiles.describe")
    }
    let error = await #expect(throws: ProfileAdminError.self) {
      _ = try await timedOut.describe(connection, "work")
    }
    #expect(error == .request("request timed out: profiles.describe"))
  }

  @Test func eachCallUsesAndDisconnectsAnIndependentAuthenticatedGateway() async throws {
    let factories = LockIsolated(0)
    let disconnects = LockIsolated(0)
    let auth = LockIsolated<AuthSession?>(nil)
    let admin = client(
      disconnectCount: disconnects,
      factoryCount: factories,
      connectAuth: auth
    ) { method, _ in
      switch method {
      case "profiles.list": return .object(["profiles": .array([])])
      case "profiles.describe": return .object(["name": .string("default")])
      default: return .object([:])
      }
    }

    _ = try await admin.list(connection, false)
    _ = try await admin.describe(connection, "default")

    #expect(factories.value == 2)
    #expect(disconnects.value == 2)
    #expect(auth.value == .token("secret-token"))
  }

  @Test func malformedTopLevelResponseDoesNotBecomeEmptySuccess() async throws {
    let list = client { _, _ in .array([]) }
    await #expect(throws: ProfileAdminError.malformedResponse(method: "profiles.list")) {
      _ = try await list.list(connection, false)
    }

    let describe = client { _, _ in .string("wrong") }
    await #expect(throws: ProfileAdminError.malformedResponse(method: "profiles.describe")) {
      _ = try await describe.describe(connection, "work")
    }
  }
}
