import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

/// True running-turn guidance: the composer remains the durable draft until Hermes
/// acknowledges, and every acknowledgement is paired to one request and one live session.
@MainActor
struct ChatSteeringTests {
  private let conn = ServerConnection(baseURL: URL(string: "http://mac.tailnet:9119")!, token: "t")

  private func uuid(_ n: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", n))")!
  }

  private func runningState(composerText: String = "") -> ChatFeature.State {
    var state = ChatFeature.State(connection: conn)
    state.liveSessionID = "live123"
    state.storedSessionID = "stored123"
    state.status = .ready
    state.isSending = true
    state.composerText = composerText
    return state
  }

  private func pendingState(
    kind: ChatFeature.GuidanceKind = .steer,
    composerText: String = "  guide this way  ",
    requestID: UUID? = nil
  ) -> ChatFeature.State {
    var state = runningState(composerText: composerText)
    state.pendingGuidance = ChatFeature.PendingGuidance(
      id: requestID ?? uuid(50), sessionID: "live123", kind: kind,
      draftText: composerText,
      wireText: composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    return state
  }

  @Test func runningComposerDefaultsToSteerAndRetainsDraftUntilAccepted() async {
    let clock = TestClock()
    let calls = LockIsolated<[(String, String)]>([])
    let store = TestStore(initialState: runningState(composerText: "  go left  ")) {
      ChatFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.continuousClock = clock
      $0.chatSnapshot = .inMemory()
      $0.hermesGateway.steer = { sessionID, text in
        calls.withValue { $0.append((sessionID, text)) }
        return .accepted(text: text)
      }
    }

    #expect(store.state.midTurnBehavior == .steer)
    await store.send(.composerSubmitted) {
      $0.pendingGuidance = ChatFeature.PendingGuidance(
        id: self.uuid(0), sessionID: "live123", kind: .steer,
        draftText: "  go left  ", wireText: "go left"
      )
      // The draft deliberately remains visible until acknowledgement.
      $0.composerText = "  go left  "
    }
    await store.receive(\.steerResult) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .supported
      $0.composerText = ""
      $0.transcript = [
        ChatRow(id: self.uuid(1), kind: .message(role: .user, text: "go left", isComplete: true))
      ]
    }
    #expect(calls.value.count == 1)
    #expect(calls.value.first?.0 == "live123")
    #expect(calls.value.first?.1 == "go left")
    await store.send(.teardown)
    await store.finish()
  }

  @Test func rejectionKeepsExactDraft() async {
    let requestID = uuid(50)
    let store = TestStore(initialState: pendingState(requestID: requestID)) { ChatFeature() }

    await store.send(.steerResult(
      requestID: requestID, sessionID: "live123",
      result: .success(.rejected(text: "guide this way"))
    )) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .supported
      $0.errorBanner = "Hermes rejected the steering guidance. Your draft was kept."
    }
    #expect(store.state.composerText == "  guide this way  ")
    #expect(store.state.transcript.isEmpty)
  }

  @Test func unsupportedSteerKeepsDraftAndDisablesOnlySteering() async {
    let requestID = uuid(50)
    let store = TestStore(initialState: pendingState(requestID: requestID)) { ChatFeature() }

    await store.send(.steerResult(
      requestID: requestID, sessionID: "live123", result: .success(.unsupported)
    )) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .unsupported
      $0.errorBanner = "Steering is not supported by this Hermes session. Your draft was kept."
    }
    #expect(store.state.composerText == "  guide this way  ")
    #expect(store.state.redirectCapability == .unknown)
  }

  @Test func timeoutKeepsDraftAndCapabilityUnknown() async {
    let requestID = uuid(50)
    var initial = pendingState(requestID: requestID)
    initial.steeringCapability = .supported
    let store = TestStore(initialState: initial) { ChatFeature() }

    await store.send(.steerResult(
      requestID: requestID, sessionID: "live123",
      result: .failure(.timedOut(method: "session.steer"))
    )) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .unknown
      $0.errorBanner = "Steering acknowledgement was not received. Your draft was kept."
    }
    #expect(store.state.composerText == "  guide this way  ")
  }

  @Test func disconnectBeforeAcknowledgementKeepsDraftAndForgetsVerdict() async {
    let clock = TestClock()
    var initial = pendingState()
    initial.steeringCapability = .supported
    let store = TestStore(initialState: initial) {
      ChatFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }

    await store.send(.gatewayClosed) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .unknown
      $0.isSending = false
      $0.status = .reconnecting
      $0.reconnectAttempt = 1
    }
    #expect(store.state.composerText == "  guide this way  ")
    await store.send(.teardown)
    await store.finish()
  }

  @Test func turnMayCompleteWhileSteerAcknowledgementIsInFlight() async {
    let clock = TestClock()
    let requestID = uuid(50)
    let store = TestStore(initialState: pendingState(requestID: requestID)) {
      ChatFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.continuousClock = clock
      $0.chatSnapshot = .inMemory()
    }

    await store.send(.gatewayEvent(.messageComplete(text: "done", usage: nil))) {
      $0.transcript = [
        ChatRow(id: self.uuid(0), kind: .message(role: .assistant, text: "done", isComplete: true))
      ]
      $0.isSending = false
    }
    await store.receive(\.delegate.runningChanged)
    #expect(store.state.pendingGuidance?.id == requestID)
    #expect(store.state.composerText == "  guide this way  ")

    await store.send(.steerResult(
      requestID: requestID, sessionID: "live123",
      result: .success(.accepted(text: "guide this way"))
    )) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .supported
      $0.composerText = ""
      $0.transcript.append(ChatRow(
        id: self.uuid(1), kind: .message(role: .user, text: "guide this way", isComplete: true)
      ))
    }
    await store.send(.teardown)
    await store.finish()
  }

  @Test func sessionChangeInvalidatesPendingAndLateAcknowledgementIsIgnored() async {
    let requestID = uuid(50)
    var initial = pendingState(requestID: requestID)
    initial.steeringCapability = .supported
    let store = TestStore(initialState: initial) { ChatFeature() }

    await store.send(.liveSessionIDRefreshed(
      liveSessionID: "live456", storedSessionID: "stored123"
    )) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .unknown
      $0.liveSessionID = "live456"
    }
    await store.send(.steerResult(
      requestID: requestID, sessionID: "live123",
      result: .success(.accepted(text: "guide this way"))
    ))
    #expect(store.state.composerText == "  guide this way  ")
    #expect(store.state.transcript.isEmpty)
  }

  @Test func duplicateAcceptedResultAppendsGuidanceExactlyOnce() async {
    let clock = TestClock()
    let requestID = uuid(50)
    let action = ChatFeature.Action.steerResult(
      requestID: requestID, sessionID: "live123",
      result: .success(.accepted(text: "guide this way"))
    )
    let store = TestStore(initialState: pendingState(requestID: requestID)) {
      ChatFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.continuousClock = clock
      $0.chatSnapshot = .inMemory()
    }

    await store.send(action) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .supported
      $0.composerText = ""
      $0.transcript = [
        ChatRow(id: self.uuid(0), kind: .message(role: .user, text: "guide this way", isComplete: true))
      ]
    }
    await store.send(action)
    #expect(store.state.transcript.count == 1)
    await store.send(.teardown)
    await store.finish()
  }

  @Test func acceptedAcknowledgementDoesNotEraseNewerComposerEdit() async {
    let clock = TestClock()
    let requestID = uuid(50)
    var initial = pendingState(requestID: requestID)
    initial.composerText = "newer draft"
    let store = TestStore(initialState: initial) {
      ChatFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.continuousClock = clock
      $0.chatSnapshot = .inMemory()
    }

    await store.send(.steerResult(
      requestID: requestID, sessionID: "live123",
      result: .success(.accepted(text: "guide this way"))
    )) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .supported
      $0.transcript = [
        ChatRow(id: self.uuid(0), kind: .message(role: .user, text: "guide this way", isComplete: true))
      ]
    }
    #expect(store.state.composerText == "newer draft")
    await store.send(.teardown)
    await store.finish()
  }

  @Test func unsupportedRedirectFallsBackOnceToSteer() async {
    let clock = TestClock()
    let requestID = uuid(50)
    let calls = LockIsolated<[(String, String)]>([])
    let store = TestStore(initialState: pendingState(kind: .redirect, requestID: requestID)) {
      ChatFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.continuousClock = clock
      $0.chatSnapshot = .inMemory()
      $0.hermesGateway.steer = { sessionID, text in
        calls.withValue { $0.append((sessionID, text)) }
        return .accepted(text: text)
      }
    }

    await store.send(.redirectResult(
      requestID: requestID, sessionID: "live123", result: .success(.unsupported)
    )) {
      $0.redirectCapability = .unsupported
      $0.pendingGuidance?.kind = .steer
    }
    await store.receive(\.steerResult) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .supported
      $0.composerText = ""
      $0.transcript = [
        ChatRow(id: self.uuid(0), kind: .message(role: .user, text: "guide this way", isComplete: true))
      ]
    }
    #expect(calls.value.count == 1)
    await store.send(.teardown)
    await store.finish()
  }

  @Test func stopPreservesDraft() async {
    var initial = runningState(composerText: "do not lose this")
    initial.queueingEnabled = true
    let store = TestStore(initialState: initial) {
      ChatFeature()
    } withDependencies: {
      $0.chatSnapshot = .inMemory()
      $0.hermesGateway.send = { _, _ in .object([:]) }
    }

    await store.send(.interruptTapped) {
      $0.isSending = false
    }
    #expect(store.state.composerText == "do not lose this")
    #expect(store.state.queuedPrompts.isEmpty)
    await store.finish()
  }

  @Test func acceptedSteerSurvivesDisconnectWithoutDuplicateOrDraftRestore() async {
    let clock = TestClock()
    let requestID = uuid(50)
    let store = TestStore(initialState: pendingState(requestID: requestID)) {
      ChatFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.continuousClock = clock
      $0.chatSnapshot = .inMemory()
    }

    await store.send(.steerResult(
      requestID: requestID, sessionID: "live123",
      result: .success(.accepted(text: "guide this way"))
    )) {
      $0.pendingGuidance = nil
      $0.steeringCapability = .supported
      $0.composerText = ""
      $0.transcript = [
        ChatRow(id: self.uuid(0), kind: .message(role: .user, text: "guide this way", isComplete: true))
      ]
    }
    await store.send(.gatewayClosed) {
      $0.isSending = false
      $0.status = .reconnecting
      $0.reconnectAttempt = 1
    }
    #expect(store.state.transcript.count == 1)
    #expect(store.state.composerText.isEmpty)
    #expect(store.state.steeringCapability == .supported)
    await store.send(.teardown)
    await store.finish()
  }
}
