import ComposableArchitecture
import HermesKit
import SwiftUI

/// Root view: onboarding until connected, then the five-destination application shell.
/// Chats retains the original app-owned navigation stack so running turns survive tab changes
/// and pops under the same reducer policy as before.
struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    content
      .task { store.send(.task) }
      .sheet(item: $store.scope(state: \.reauth, action: \.reauth)) { reauthStore in
        ReauthView(store: reauthStore)
      }
      // Observe lifecycle here (view stays thin) and dispatch into the reducer, which fans
      // foreground out to reconnect/re-hydrate + list refresh and background out to an
      // immediate snapshot/anchor flush. Behaviour is unit-tested via `scenePhaseChanged`.
      .onChange(of: scenePhase) { _, newPhase in
        store.send(.scenePhaseChanged(newPhase.appPhase))
      }
  }

  /// Which root branch wins is decided ONCE, by `AppFeature.State.rootScreen` in HermesKit
  /// (where its precedence is unit-tested by `swift test`) — this `switch` only renders the
  /// verdict. Deliberately NOT `if rootScreen == .home, let homeStore = …`: re-deriving the
  /// same optional the resolver already consulted means a disagreement falls silently through
  /// to onboarding, which is the exact failure the enum exists to prevent.
  @ViewBuilder
  private var content: some View {
    switch store.rootScreen {
    case .home:
      connectedShell
    case .connecting:
      ProgressView("Connecting…")
    case .connectionFailed:
      // Launch auto-connect failed for a reason that isn't a verdict on the credentials
      // (no network, or a proxy reporting the agent down): the stored credentials are fine,
      // so keep them and offer a retry instead of dropping to onboarding. Auth failures never
      // populate this slot — they land on the onboarding branch below.
      if let failedStore = store.scope(state: \.connectionFailed, action: \.connectionFailed) {
        ConnectionFailedView(store: failedStore)
      }
    case .onboarding:
      NavigationStack {
        ConnectionView(store: store.scope(state: \.onboarding, action: \.onboarding))
          .navigationTitle("Connect to Hermes")
          .navigationBarTitleDisplayMode(.inline)
      }
    }
  }

  private var connectedShell: some View {
    TabView(selection: destinationSelection) {
      Tab("Home", systemImage: "house", value: AppDestination.home) {
        NavigationStack {
          if let dashboardStore = store.scope(state: \.dashboard, action: \.dashboard) {
            HomeView(store: dashboardStore)
          } else {
            ProgressView("Loading Home…")
          }
        }
      }

      Tab("Chats", systemImage: "bubble.left.and.bubble.right", value: AppDestination.chats) {
        chatsNavigation
      }

      Tab("Board", systemImage: "rectangle.3.group", value: AppDestination.board) {
        NavigationStack {
          UnsupportedDestinationView(
            title: "Board",
            systemImage: "rectangle.3.group",
            reason: store.boardAvailability.unavailableReason
              ?? "Board is available, but its workspace isn't included in this build yet."
          )
        }
      }

      Tab("Automations", systemImage: "calendar", value: AppDestination.automations) {
        NavigationStack {
          UnsupportedDestinationView(
            title: "Automations",
            systemImage: "calendar",
            reason: store.automationsAvailability.unavailableReason
              ?? "Automations are available, but their editor isn't included in this build yet."
          )
        }
      }

      Tab("Settings", systemImage: "gearshape", value: AppDestination.settings) {
        NavigationStack {
          if let settingsStore = store.scope(state: \.settings, action: \.settings) {
            SettingsView(store: settingsStore, showsDoneButton: false)
          } else {
            ProgressView("Loading Settings…")
          }
        }
      }
    }
  }

  /// Keep Chats' pre-shell navigation structure byte-for-byte in spirit: the path still holds
  /// thin markers, live state still belongs to `AppFeature.liveChat`, and disappearance still
  /// routes through the parent only after the outgoing screen has finished animating.
  private var chatsNavigation: some View {
    NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
      if let chatsStore = store.scope(state: \.home, action: \.home) {
        SessionListView(store: chatsStore, showsSettingsButton: false)
      }
    } destination: { _ in
      if let chatStore = store.scope(state: \.liveChat, action: \.liveChat) {
        ChatView(store: chatStore)
          .onDisappear { store.send(.chatViewDisappeared) }
      }
    }
  }

  private var destinationSelection: Binding<AppDestination> {
    Binding(
      get: { store.selectedDestination },
      set: { store.send(.destinationSelected($0)) }
    )
  }
}

private extension ScenePhase {
  /// Map SwiftUI's `ScenePhase` onto HermesKit's SwiftUI-free `AppFeature.ScenePhase`.
  var appPhase: AppFeature.ScenePhase {
    switch self {
    case .active: return .active
    case .inactive: return .inactive
    case .background: return .background
    @unknown default: return .inactive
    }
  }
}

#Preview {
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
