import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct ProfileAdministrationFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "https://agent.example")!, token: "tok"
  )

  @Test func settingsLoadsNativeProfilesAndOpensScopedEditor() async {
    let requestedIncludeSessions = LockIsolated<Bool?>(nil)
    let profiles = [
      ProfileAdminSummary(name: "default", isDefault: true),
      ProfileAdminSummary(
        name: "work",
        model: "gpt-5.6",
        provider: "openai",
        profileDescription: "Ships the app",
        skillCount: 4
      ),
    ]
    let store = TestStore(initialState: SettingsFeature.State(connection: connection)) {
      SettingsFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.list = { @Sendable _, includeSessions in
        requestedIncludeSessions.setValue(includeSessions)
        return profiles
      }
    }

    await store.send(.loadProfiles) {
      $0.profileLoadState = .loading
    }
    await store.receive(\.profileListResponse) {
      $0.profiles = IdentifiedArray(uniqueElements: profiles)
      $0.profileLoadState = .loaded
    }
    await store.receive(\.delegate.profilesChanged)
    #expect(requestedIncludeSessions.value == false)

    await store.send(.profileTapped(profiles[1])) {
      $0.profileEditor = ProfileEditorFeature.State(
        connection: self.connection,
        summary: profiles[1]
      )
    }
    #expect(store.state.profileEditor?.profileName == "work")
  }

  @Test func listCapabilityGatesOnlyAuthoritativeUnsupported() async {
    let unsupported = TestStore(initialState: SettingsFeature.State(connection: connection)) {
      SettingsFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.list = { @Sendable _, _ in throw ProfileAdminError.unsupported }
    }
    await unsupported.send(.loadProfiles) {
      $0.profileLoadState = .loading
    }
    await unsupported.receive(\.profileListResponse) {
      $0.profileLoadState = .unsupported(ProfileAdminError.unsupported.message)
    }

    let transient = TestStore(initialState: SettingsFeature.State(connection: connection)) {
      SettingsFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.list = { @Sendable _, _ in
        throw ProfileAdminError.request("request timed out: profiles.list")
      }
    }
    await transient.send(.loadProfiles) {
      $0.profileLoadState = .loading
    }
    await transient.receive(\.profileListResponse) {
      $0.profileLoadState = .failed("request timed out: profiles.list")
    }
  }

  @Test func editorRenameAndDeleteBubbleToSettingsParent() async {
    let summary = ProfileAdminSummary(name: "work")
    var state = SettingsFeature.State(
      connection: connection,
      profiles: [summary],
      profileLoadState: .loaded,
      profileEditor: .init(connection: connection, summary: summary)
    )
    state.profileEditor?.loadState = .loaded
    let store = TestStore(initialState: state) { SettingsFeature() } withDependencies: {
      $0.hermesProfileAdmin.list = { @Sendable _, _ in [] }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.profileEditor(.presented(
      .delegate(.renamed(oldName: "work", newName: "work-2"))
    )))
    await store.receive(\.delegate.profileRenamed)

    await store.send(.profileEditor(.presented(.delegate(.deleted(name: "work-2")))))
    #expect(store.state.profileEditor == nil)
    await store.receive(\.delegate.profileDeleted)
  }
}
