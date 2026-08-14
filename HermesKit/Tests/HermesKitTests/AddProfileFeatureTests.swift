import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct AddProfileFeatureTests {
  private let connection = ServerConnection(baseURL: URL(string: "http://mac.tailnet:9119")!, token: "tok")

  @Test func invalidNameSetsNameErrorAndBlocksCreate() async {
    let store = TestStore(initialState: AddProfileFeature.State(connection: connection)) {
      AddProfileFeature()
    }
    store.exhaustivity = .off

    await store.send(.binding(.set(\.name, "testOS"))) {
      $0.name = "testOS"
    }
    #expect(store.state.nameError == ProfileName.hint)
    #expect(store.state.canCreate == false)
  }

  @Test func validNameEnablesCreate() async {
    let store = TestStore(initialState: AddProfileFeature.State(connection: connection)) {
      AddProfileFeature()
    }
    store.exhaustivity = .off

    await store.send(.binding(.set(\.name, "work"))) {
      $0.name = "work"
    }
    #expect(store.state.nameError == nil)
    #expect(store.state.canCreate == true)
  }

  @Test func emptyNameHasNoErrorButCannotCreate() {
    let state = AddProfileFeature.State(connection: connection)
    #expect(state.nameError == nil)
    #expect(state.canCreate == false)
  }

  @Test func createSuccessWithBlankSoulOmitsSoulFromRequest() async {
    let request = LockIsolated<ProfileCreateRequest?>(nil)
    var state = AddProfileFeature.State(connection: connection)
    state.name = "work"
    state.soul = "   " // blank after trimming

    let store = TestStore(initialState: state) {
      AddProfileFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.create = { @Sendable _, value in
        request.setValue(value)
        return ProfileCreateResult(ok: true, name: value.name)
      }
    }

    await store.send(.createTapped) {
      $0.isCreating = true
    }
    await store.receive(\.createResponse.success) {
      $0.isCreating = false
      $0.createSupported = true
    }
    await store.receive(\.delegate.created)

    #expect(request.value?.name == "work")
    #expect(request.value?.soul == nil)
    #expect(request.value?.cloneFrom == "default")
  }

  @Test func createSuccessIncludesSoulInRequest() async {
    let request = LockIsolated<ProfileCreateRequest?>(nil)
    var state = AddProfileFeature.State(connection: connection)
    state.name = "work"
    state.soul = "You are helpful."

    let store = TestStore(initialState: state) {
      AddProfileFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.create = { @Sendable _, value in
        request.setValue(value)
        return ProfileCreateResult(ok: true, name: value.name)
      }
    }

    await store.send(.createTapped) {
      $0.isCreating = true
    }
    await store.receive(\.createResponse.success) {
      $0.isCreating = false
      $0.createSupported = true
    }
    await store.receive(\.delegate.created)

    #expect(request.value?.name == "work")
    #expect(request.value?.soul == "You are helpful.")
  }

  @Test func createFailureSetsErrorBannerAndClearsCreating() async {
    var state = AddProfileFeature.State(connection: connection)
    state.name = "test"

    let store = TestStore(initialState: state) {
      AddProfileFeature()
    } withDependencies: {
      $0.hermesProfileAdmin.create = { @Sendable _, _ in
        throw ProfileAdminError.request("Profile already exists")
      }
    }

    await store.send(.createTapped) {
      $0.isCreating = true
    }
    await store.receive(\.createResponse.failure) {
      $0.isCreating = false
      $0.errorBanner = "Profile already exists"
    }
  }

  @Test func unsupportedCreateIsCapabilityGated() async {
    var state = AddProfileFeature.State(connection: connection)
    state.name = "work"
    let store = TestStore(initialState: state) { AddProfileFeature() } withDependencies: {
      $0.hermesProfileAdmin.create = { @Sendable _, _ in throw ProfileAdminError.unsupported }
    }

    await store.send(.createTapped) { $0.isCreating = true }
    await store.receive(\.createResponse.failure) {
      $0.isCreating = false
      $0.createSupported = false
      $0.errorBanner = ProfileAdminError.unsupported.message
    }
  }

  @Test func cancelTappedDismissesTheSheet() async {
    let dismissed = LockIsolated(false)
    let store = TestStore(initialState: AddProfileFeature.State(connection: connection)) {
      AddProfileFeature()
    } withDependencies: {
      $0.dismiss = DismissEffect { dismissed.setValue(true) }
    }

    await store.send(.cancelTapped)
    #expect(dismissed.value == true)
  }
}
