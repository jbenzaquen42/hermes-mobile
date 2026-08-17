import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct NotificationPreferencesTests {
  private let connection = ServerConnection(baseURL: URL(string: "https://agent.example")!, token: "tok")

  @Test func preferencesDefaultAndPersistInMemory() {
    let preferences = PreferencesClient.inMemory()

    #expect(preferences.loadPushEventPreferences() == .default)
    #expect(preferences.loadPushEventPreferences().approval)
    #expect(!preferences.loadPushEventPreferences().turnComplete)

    preferences.savePushEventPreferences(PushEventPreferences(
      approval: true, turnComplete: true, failure: true, subagent: true
    ))
    #expect(preferences.loadPushEventPreferences().turnComplete)
    #expect(preferences.loadPushEventPreferences().subagent)

    preferences.clearPushEventPreferences()
    #expect(preferences.loadPushEventPreferences() == .default)
  }

  @Test func settingsTaskLoadsEventPreferencesAndVersion() async {
    let preferences = PreferencesClient.inMemory()
    preferences.savePushEventPreferences(PushEventPreferences(
      approval: false, turnComplete: true, failure: false, subagent: true
    ))
    let store = TestStore(
      initialState: SettingsFeature.State(connection: connection)
    ) {
      SettingsFeature()
    } withDependencies: {
      $0.preferences = preferences
      $0.push.appVersion = { @Sendable in "9.9" }
      $0.hermesProfileAdmin.list = { @Sendable _, _ in throw ProfileAdminError.unsupported }
    }
    store.exhaustivity = .off

    await store.send(.task)
    await store.receive(\.appVersionLoaded) {
      $0.appVersion = "9.9"
    }
    await store.receive(\.pushEventPreferencesLoaded) {
      $0.pushEventPreferences = PushEventPreferences(
        approval: false, turnComplete: true, failure: false, subagent: true
      )
    }
    #expect(store.state.pushEventPreferences.turnComplete)
  }

  @Test func settingsEventPreferenceChangePersists() async {
    let preferences = PreferencesClient.inMemory()
    let store = TestStore(
      initialState: SettingsFeature.State(connection: connection)
    ) {
      SettingsFeature()
    } withDependencies: {
      $0.preferences = preferences
    }

    var updated = PushEventPreferences.default
    updated.turnComplete = true
    updated.subagent = true
    await store.send(.pushEventPreferenceChanged(updated)) {
      $0.pushEventPreferences = updated
    }
    #expect(preferences.loadPushEventPreferences().turnComplete)
    #expect(preferences.loadPushEventPreferences().subagent)
  }
}
