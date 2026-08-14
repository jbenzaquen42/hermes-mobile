import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

private func steeringRequest(_ frame: String) -> JSONValue? {
  try? JSONDecoder().decode(JSONValue.self, from: Data(frame.utf8))
}

@Suite struct SessionSteeringGatewayTests {
  private let url = URL(string: "http://test.local:9119")!

  @Test func steerSendsTypedRequestAndMapsQueuedToAccepted() async throws {
    let captured = LockIsolated<JSONValue?>(nil)
    let transport = FakeTransport { frame, inbound in
      guard let request = steeringRequest(frame), let id = request["id"]?.intValue else { return }
      captured.setValue(request)
      inbound.yield(
        #"{"jsonrpc":"2.0","id":\#(id),"result":{"status":"queued","text":"check auth.log"}}"#
      )
    }
    let client = HermesGatewayClient.make { _ in transport }
    let stream = client.connect(url, .token("t"))
    defer { withExtendedLifetime(stream) {} }

    let result = try await client.steer("live-123", "check auth.log")

    #expect(result == .accepted(text: "check auth.log"))
    #expect(captured.value?["method"]?.stringValue == "session.steer")
    #expect(captured.value?["params"]?["session_id"]?.stringValue == "live-123")
    #expect(captured.value?["params"]?["text"]?.stringValue == "check auth.log")
  }

  @Test func steerMapsRejectedAcknowledgement() async throws {
    let transport = FakeTransport { frame, inbound in
      guard let id = steeringRequest(frame)?["id"]?.intValue else { return }
      inbound.yield(
        #"{"jsonrpc":"2.0","id":\#(id),"result":{"status":"rejected","text":"too late"}}"#
      )
    }
    let client = HermesGatewayClient.make { _ in transport }
    let stream = client.connect(url, .token("t"))
    defer { withExtendedLifetime(stream) {} }

    #expect(try await client.steer("live-123", "too late") == .rejected(text: "too late"))
  }

  @Test(arguments: [
    ("redirected", SessionRedirectResult.redirected(text: "use Postgres")),
    ("queued", SessionRedirectResult.queued(text: "use Postgres")),
    ("rejected", SessionRedirectResult.rejected(text: "use Postgres")),
  ])
  func redirectMapsEveryAcknowledgement(
    status: String,
    expected: SessionRedirectResult
  ) async throws {
    let captured = LockIsolated<JSONValue?>(nil)
    let transport = FakeTransport { frame, inbound in
      guard let request = steeringRequest(frame), let id = request["id"]?.intValue else { return }
      captured.setValue(request)
      inbound.yield(
        #"{"jsonrpc":"2.0","id":\#(id),"result":{"status":"\#(status)","text":"use Postgres"}}"#
      )
    }
    let client = HermesGatewayClient.make { _ in transport }
    let stream = client.connect(url, .token("t"))
    defer { withExtendedLifetime(stream) {} }

    #expect(try await client.redirect("live-456", "use Postgres") == expected)
    #expect(captured.value?["method"]?.stringValue == "session.redirect")
    #expect(captured.value?["params"]?["session_id"]?.stringValue == "live-456")
    #expect(captured.value?["params"]?["text"]?.stringValue == "use Postgres")
  }

  @Test(arguments: [4010, -32601])
  func steerMapsUnsupportedRPCCodes(code: Int) async throws {
    let transport = FakeTransport { frame, inbound in
      guard let id = steeringRequest(frame)?["id"]?.intValue else { return }
      inbound.yield(
        #"{"jsonrpc":"2.0","id":\#(id),"error":{"code":\#(code),"message":"unsupported"}}"#
      )
    }
    let client = HermesGatewayClient.make { _ in transport }
    let stream = client.connect(url, .token("t"))
    defer { withExtendedLifetime(stream) {} }

    #expect(try await client.steer("live-123", "guide") == .unsupported)
  }

  @Test func redirectMapsLegacyUnknownMethodToUnsupported() async throws {
    let transport = FakeTransport { frame, inbound in
      guard let id = steeringRequest(frame)?["id"]?.intValue else { return }
      inbound.yield(
        #"{"jsonrpc":"2.0","id":\#(id),"error":{"message":"unknown method: session.redirect"}}"#
      )
    }
    let client = HermesGatewayClient.make { _ in transport }
    let stream = client.connect(url, .token("t"))
    defer { withExtendedLifetime(stream) {} }

    #expect(try await client.redirect("live-123", "guide") == .unsupported)
  }

  @Test func validationFailurePreservesRPCCodeAndMessage() async throws {
    let transport = FakeTransport { frame, inbound in
      guard let id = steeringRequest(frame)?["id"]?.intValue else { return }
      inbound.yield(
        #"{"jsonrpc":"2.0","id":\#(id),"error":{"code":4002,"message":"text is required"}}"#
      )
    }
    let client = HermesGatewayClient.make { _ in transport }
    let stream = client.connect(url, .token("t"))
    defer { withExtendedLifetime(stream) {} }

    await #expect(throws: GatewayError.rpc(code: 4002, message: "text is required")) {
      _ = try await client.steer("live-123", "   ")
    }
  }

  @Test func malformedSteerSuccessDoesNotBecomeAnAcceptance() async throws {
    let transport = FakeTransport { frame, inbound in
      guard let id = steeringRequest(frame)?["id"]?.intValue else { return }
      inbound.yield(
        #"{"jsonrpc":"2.0","id":\#(id),"result":{"status":"maybe","text":"guide"}}"#
      )
    }
    let client = HermesGatewayClient.make { _ in transport }
    let stream = client.connect(url, .token("t"))
    defer { withExtendedLifetime(stream) {} }

    await #expect(throws: GatewayError.malformedResponse(method: "session.steer")) {
      _ = try await client.steer("live-123", "guide")
    }
  }

  @Test func typedMethodsPreserveNotConnected() async {
    let client = HermesGatewayClient.make { _ in FakeTransport() }

    await #expect(throws: GatewayError.notConnected) {
      _ = try await client.steer("live-123", "guide")
    }
    await #expect(throws: GatewayError.notConnected) {
      _ = try await client.redirect("live-123", "guide")
    }
  }

  @Test func codedFailureDecodingRetainsApplicationCode() throws {
    let frame = try InboundFrame(
      data: Data(
        #"{"jsonrpc":"2.0","id":7,"error":{"code":4010,"message":"agent does not support steer"}}"#.utf8
      )
    )

    #expect(
      frame == .codedFailure(
        id: 7,
        code: 4010,
        message: "agent does not support steer"
      )
    )
  }

  @Test func codedGatewayErrorMatchersRemainStructured() {
    let unsupportedRuntime = GatewayError.rpc(code: 4010, message: "agent does not support steer")
    #expect(unsupportedRuntime.isUnsupportedOperation)
    #expect(!unsupportedRuntime.isUnknownMethod)

    let unknownMethod = GatewayError.rpc(code: -32601, message: "Method not found")
    #expect(unknownMethod.isUnsupportedOperation)
    #expect(unknownMethod.isUnknownMethod)

    let staleSession = GatewayError.rpc(code: 4004, message: "session not found: live-123")
    #expect(staleSession.isSessionNotFound)
    #expect(!staleSession.isUnsupportedOperation)
  }
}
