import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@Suite struct HermesCapabilityCatalogClientTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "https://hermes.test:9119")!,
    token: "secret-token"
  )

  private func client(
    disconnectCount: LockIsolated<Int> = LockIsolated(0),
    factoryCount: LockIsolated<Int> = LockIsolated(0),
    connectAuth: LockIsolated<AuthSession?> = LockIsolated(nil),
    send: @escaping @Sendable (String, JSONValue) async throws -> JSONValue
  ) -> HermesCapabilityCatalogClient {
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

  @Test func loadUsesNativeCatalogMethodsAndMapsOnlySafeMetadata() async throws {
    let calls = LockIsolated<[(String, JSONValue)]>([])
    let factories = LockIsolated(0)
    let disconnects = LockIsolated(0)
    let auth = LockIsolated<AuthSession?>(nil)
    let catalogClient = client(
      disconnectCount: disconnects,
      factoryCount: factories,
      connectAuth: auth
    ) { method, params in
      calls.withValue { $0.append((method, params)) }
      switch method {
      case "skills.manage":
        return .object([
          "skills": .object([
            "coding": .array([.string("swift-review")]),
            "general": .array([.string("plan"), .number(7)]),
          ]),
        ])
      case "toolsets.list":
        return .object([
          "toolsets": .array([
            .object([
              "name": .string("web"),
              "label": .string("Web tools"),
              "description": .string("Search and extract"),
              "tool_count": .string("4"),
              "enabled": .number(1),
            ]),
            .object([
              "name": .string("file"),
              "description": .string("Read files"),
              "tool_count": .number(-2),
              "enabled": .string("false"),
            ]),
          ]),
        ])
      case "mcp.catalog":
        return .object([
          "servers": .array([
            .object([
              "name": .string("github"),
              "description": .string("GitHub tools"),
              "installed": .bool(true),
              "enabled": .bool(true),
              "transport": .string("http"),
              "status": .string("connected"),
              "tools": .array([
                .object([
                  "name": .string("create_issue"),
                  "description": .string("Create an issue"),
                ]),
                .string("list_repositories"),
              ]),
              // Native/future MCP payloads may contain all of these. None belongs in
              // MCPCatalogServer or its diagnostics.
              "url": .string("https://secret.internal/mcp?ticket=abc"),
              "headers": .object(["Authorization": .string("Bearer secret")]),
              "env": .object(["GITHUB_TOKEN": .string("top-secret")]),
              "requires": .array([.string("GITHUB_TOKEN")]),
              "error": .string("failed at https://secret.internal with top-secret"),
            ]),
            .object([
              "name": .string("unsafe-transport"),
              "installed": .bool(true),
              "transport": .string("https://secret.internal/mcp"),
              "disabled": .bool(true),
              "tools": .number(12),
            ]),
            // The native mcp.catalog includes approved-but-uninstalled entries. They are not
            // configured servers and must not become profile toggles.
            .object([
              "name": .string("not-installed"),
              "installed": .bool(false),
              "enabled": .bool(false),
              "requires": .array([.string("PRIVATE_API_KEY")]),
              "url": .string("https://catalog.example/mcp"),
            ]),
          ]),
        ])
      default:
        throw GatewayError.rpc(code: -32601, message: "unknown method: \(method)")
      }
    }

    let catalog = try await catalogClient.load(connection, "research")

    let captured = calls.value
    #expect(captured.count == 3)
    #expect(captured.first(where: { $0.0 == "skills.manage" })?.1 == .object([
      "action": .string("list"),
      "profile": .string("research"),
    ]))
    #expect(captured.first(where: { $0.0 == "toolsets.list" })?.1 == .object([:]))
    #expect(captured.first(where: { $0.0 == "mcp.catalog" })?.1 == .object([
      "profile": .string("research"),
    ]))
    #expect(catalog.skills == [
      SkillCatalogEntry(name: "swift-review", category: "coding", enabled: true),
      SkillCatalogEntry(name: "plan", category: "general", enabled: true),
    ])
    #expect(catalog.toolsets == [
      ToolsetCatalogEntry(
        name: "web", label: "Web tools", toolsetDescription: "Search and extract",
        toolCount: 4, enabled: true
      ),
      ToolsetCatalogEntry(
        name: "file", label: "file", toolsetDescription: "Read files",
        toolCount: 0, enabled: false
      ),
    ])

    let github = try #require(catalog.mcpServers.first)
    #expect(github.name == "github")
    #expect(github.installed)
    #expect(github.enabled)
    #expect(github.transport == "http")
    #expect(github.health == .connected)
    #expect(github.reportedToolCount == 2)
    #expect(github.tools == [
      MCPToolCatalogEntry(name: "create_issue", description: "Create an issue"),
      MCPToolCatalogEntry(name: "list_repositories"),
    ])
    #expect(catalog.mcpServers[1].transport.isEmpty)
    #expect(catalog.mcpServers[1].health == .disabled)
    #expect(catalog.mcpServers[1].reportedToolCount == 12)
    #expect(catalog.mcpServers.count == 2)

    let diagnostic = String(reflecting: catalog)
    #expect(!diagnostic.contains("secret.internal"))
    #expect(!diagnostic.contains("Bearer secret"))
    #expect(!diagnostic.contains("top-secret"))
    #expect(!diagnostic.contains("GITHUB_TOKEN"))
    #expect(factories.value == 3)
    #expect(disconnects.value == 3)
    #expect(auth.value == .token("secret-token"))
  }

  @Test func browsePinsPaginationAndPreservesReturnedMetadata() async throws {
    let call = LockIsolated<(String, JSONValue)?>(nil)
    let catalogClient = client { method, params in
      call.setValue((method, params))
      return .object([
        "items": .array([
          .object([
            "name": .string("ios-audit"),
            "description": .string("Audit an iOS app"),
            "source": .string("official"),
            "category": .string("mobile"),
            "identifier": .string("nous/ios-audit"),
            "trust": .string("trusted"),
            "future": .bool(true),
          ]),
          .object(["description": .string("missing name")]),
        ]),
        "page": .string("2"),
        "total_pages": .number(9),
        "total": .string("165"),
      ])
    }

    let page = try await catalogClient.browseSkills(
      connection,
      SkillCatalogBrowseRequest(profile: "work", page: 2, pageSize: 500)
    )

    #expect(call.value?.0 == "skills.manage")
    #expect(call.value?.1 == .object([
      "action": .string("browse"),
      "profile": .string("work"),
      "page": .number(2),
      "page_size": .number(100),
    ]))
    #expect(page == SkillCatalogPage(
      entries: [
        SkillCatalogEntry(
          name: "ios-audit",
          description: "Audit an iOS app",
          source: "official",
          category: "mobile",
          identifier: "nous/ios-audit"
        ),
      ],
      page: 2,
      totalPages: 9,
      total: 165
    ))
  }

  @Test func searchAndInspectUseExactActionsAndMapPartialThenDetailedMetadata() async throws {
    let calls = LockIsolated<[(String, JSONValue)]>([])
    let catalogClient = client { method, params in
      calls.withValue { $0.append((method, params)) }
      guard case let .object(object) = params else { return .object([:]) }
      if object["action"] == .string("search") {
        return .object([
          "results": .array([
            .object([
              "name": .string("swift-review"),
              "description": .string("Review Swift"),
              // Newer agents may preserve the richer native search metadata.
              "source": .string("github"),
              "identifier": .string("openai/skills/swift-review"),
            ]),
          ]),
        ])
      } else if object["action"] == .string("inspect") {
        return .object([
          "info": .object([
            "name": .string("swift-review"),
            "description": .string("Review Swift"),
            "source": .string("github"),
            "category": .string("coding"),
            "identifier": .string("openai/skills/swift-review"),
            "tags": .array([.string("swift"), .string("review"), .number(4)]),
            "skill_md_preview": .string("# Swift review\nCheck concurrency."),
          ]),
        ])
      }
      return .object([:])
    }

    let results = try await catalogClient.searchSkills(
      connection,
      SkillCatalogSearchRequest(query: "swift", profile: "work")
    )
    let detail = try await catalogClient.inspectSkill(
      connection,
      SkillCatalogInspectRequest(identifier: "openai/skills/swift-review", profile: "work")
    )

    let captured = calls.value
    #expect(captured.count == 2)
    #expect(captured[0].0 == "skills.manage")
    #expect(captured[0].1 == .object([
      "action": .string("search"),
      "profile": .string("work"),
      "query": .string("swift"),
    ]))
    #expect(captured[1].0 == "skills.manage")
    #expect(captured[1].1 == .object([
      "action": .string("inspect"),
      "profile": .string("work"),
      "query": .string("openai/skills/swift-review"),
    ]))
    #expect(results.first?.documentation == nil)
    #expect(results.first?.source == "github")
    #expect(detail.documentation == "# Swift review\nCheck concurrency.")
    #expect(detail.category == "coding")
    #expect(detail.tags == ["swift", "review"])
  }

  @Test func reloadUsesNativeSkillsReloadAndReturnsStructuredChanges() async throws {
    let call = LockIsolated<(String, JSONValue)?>(nil)
    let catalogClient = client { method, params in
      call.setValue((method, params))
      return .object([
        "output": .string("This presentation string is deliberately ignored"),
        "result": .object([
          "added": .array([
            .object(["name": .string("new-skill"), "path": .string("/private/path")]),
            .string("future-string-shape"),
          ]),
          "removed": .array([.object(["name": .string("old-skill")])]),
          "total": .string("42"),
        ]),
      ])
    }

    let result = try await catalogClient.reload(connection, "work")

    #expect(call.value?.0 == "skills.reload")
    #expect(call.value?.1 == .object(["profile": .string("work")]))
    #expect(result == CapabilityCatalogReloadResult(
      added: ["new-skill", "future-string-shape"],
      removed: ["old-skill"],
      total: 42
    ))
    #expect(!String(reflecting: result).contains("/private/path"))
  }

  @Test func unsupportedMappingUsesOnlyAuthoritativeGatewayErrors() async throws {
    for gatewayError in [
      GatewayError.rpc(code: -32601, message: "unknown method: skills.manage"),
      GatewayError.rpc(code: 4010, message: "unsupported operation"),
      GatewayError.server("unknown method: skills.manage"),
    ] {
      let catalogClient = client { _, _ in throw gatewayError }
      await #expect(throws: CapabilityCatalogError.unsupported) {
        _ = try await catalogClient.searchSkills(
          connection,
          SkillCatalogSearchRequest(query: "swift")
        )
      }
    }

    let timeout = client { _, _ in
      throw GatewayError.timedOut(method: "skills.manage")
    }
    let timeoutError = await #expect(throws: CapabilityCatalogError.self) {
      _ = try await timeout.searchSkills(connection, SkillCatalogSearchRequest(query: "swift"))
    }
    #expect(timeoutError == .request("request timed out: skills.manage"))

    let vagueServerError = client { _, _ in
      throw GatewayError.server("skills are not supported by this deployment")
    }
    let requestError = await #expect(throws: CapabilityCatalogError.self) {
      _ = try await vagueServerError.searchSkills(
        connection,
        SkillCatalogSearchRequest(query: "swift")
      )
    }
    #expect(requestError == .request("skills are not supported by this deployment"))

    let arbitraryTransport = client { _, _ in
      throw NSError(
        domain: "https://secret.internal/mcp?ticket=abc",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Bearer top-secret"]
      )
    }
    let redactedError = await #expect(throws: CapabilityCatalogError.self) {
      _ = try await arbitraryTransport.searchSkills(
        connection,
        SkillCatalogSearchRequest(query: "swift")
      )
    }
    #expect(redactedError == .request("Couldn’t complete skills.manage."))
  }

  @Test func malformedTopLevelAndMissingDetailDoNotBecomeEmptySuccess() async throws {
    let malformedBrowse = client { _, _ in .array([]) }
    await #expect(throws: CapabilityCatalogError.malformedResponse(method: "skills.manage")) {
      _ = try await malformedBrowse.browseSkills(connection, SkillCatalogBrowseRequest())
    }

    let missingInspect = client { _, _ in .object(["info": .object([:])]) }
    await #expect(throws: CapabilityCatalogError.malformedResponse(method: "skills.manage")) {
      _ = try await missingInspect.inspectSkill(
        connection,
        SkillCatalogInspectRequest(identifier: "missing")
      )
    }
  }
}
