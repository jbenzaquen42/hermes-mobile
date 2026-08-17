import ComposableArchitecture
import HermesKit
import SwiftUI
import UIKit

/// Settings sheet: server info, token re-paste/clear, manual reconnect, and a link to
/// the live connection debug log.
struct SettingsView: View {
  @Bindable var store: StoreOf<SettingsFeature>
  /// Sheet presentations need Done; the root Settings tab does not.
  var showsDoneButton = true
  /// Presentation-only: the "how push works / install the plugin" info sheet. Pure view
  /// state — there's no reducer behavior behind it.
  @State private var showingPushGuide = false

  var body: some View {
    Form {
      Section("Server") {
        LabeledContent("URL", value: store.serverURLString)
      }

      Section {
        NavigationLink {
          ProfileAdministrationView(store: store)
        } label: {
          LabeledContent {
            profileStatus
          } label: {
            Label("Profiles", systemImage: "person.2")
          }
        }
        .accessibilityHint("Opens profile administration")
      } header: {
        Text("Profiles")
      } footer: {
        Text("Configure each profile's model, reasoning, SOUL, skills, toolsets, and MCP servers.")
      }

      RunningTurnSettingsSection(
        behavior: $store.midTurnBehavior,
        queueingEnabled: $store.queueingEnabled
      )

      Section {
        SecureField("Session token", text: $store.token)
          .textContentType(.password)
        Button("Save token") { store.send(.saveTokenTapped) }
          .disabled(!store.canSaveToken)
        if store.savedConfirmation {
          Label("Token saved", systemImage: "checkmark.circle")
            .foregroundStyle(.green).font(.footnote)
        }
      } header: {
        Text("Token")
      } footer: {
        Text("Re-paste the stable token if it changed on the server.")
      }

      Section("Connection") {
        Button("Reconnect") { store.send(.reconnectTapped) }
        NavigationLink {
          ConnectionDebugView(entries: store.log)
        } label: {
          LabeledContent("Debug log", value: "\(store.log.count)")
        }
      }

      Section {
        // Plugin update, offered above the toggle because an out-of-date plugin sends pushes
        // the user is actively complaining about. Shown whether or not push is currently
        // available — an installed-but-disabled plugin is still worth updating.
        if store.pluginUpdateAvailable {
          VStack(alignment: .leading, spacing: 4) {
            Label("Plugin update available", systemImage: "arrow.down.circle")
              .font(.subheadline.weight(.semibold))
            Text(pluginUpdateExplanation)
              .font(.footnote).foregroundStyle(.secondary)
          }
          Button("Update plugin") { store.send(.updatePluginTapped) }
            .disabled(store.pluginUpdate == .updating)
        } else if store.pluginUpdateNeedsManualSteps {
          // Out of date but the agent can't pull it (pip install / hand-copied directory), so
          // a button here would only 400. Route to the guide, which offers the chat prompt.
          VStack(alignment: .leading, spacing: 4) {
            Label("Plugin update available", systemImage: "arrow.down.circle")
              .font(.subheadline.weight(.semibold))
            Text("\(pluginUpdateExplanation) This copy can't be updated from the app — ask your agent to update it.")
              .font(.footnote).foregroundStyle(.secondary)
          }
          Button("How to update the plugin") { showingPushGuide = true }
            .font(.footnote)
        }
        switch store.pluginUpdate {
        case .idle:
          EmptyView()
        case .updating:
          Label("Updating…", systemImage: "arrow.triangle.2.circlepath")
            .foregroundStyle(.secondary).font(.footnote)
        case .updated:
          // A pull only changes files on disk — the running agent keeps the old code loaded.
          // This restart notice is the whole point of the success state; don't soften it.
          Label(
            "Plugin updated. Restart your Hermes agent to apply it.",
            systemImage: "exclamationmark.arrow.triangle.2.circlepath"
          )
          .foregroundStyle(.orange).font(.footnote)
        case .alreadyCurrent:
          Label("Plugin is already up to date", systemImage: "checkmark.circle")
            .foregroundStyle(.green).font(.footnote)
        case let .failed(reason):
          Label(reason, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange).font(.footnote)
        }

        if store.pushAvailable {
          Toggle(
            "Notify me about approvals",
            isOn: Binding(
              get: { store.notificationsEnabled },
              set: { store.send(.notificationsToggled($0)) }
            )
          )
          if store.notificationsDenied {
            VStack(alignment: .leading, spacing: 4) {
              Label("Notifications are turned off", systemImage: "bell.slash")
                .foregroundStyle(.orange).font(.footnote)
              if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Enable in iOS Settings", destination: url)
                  .font(.footnote)
              }
            }
          }
          Toggle("Turn complete", isOn: turnCompleteBinding)
          Toggle("Failures and errors", isOn: failureBinding)
          Toggle("Subagent activity", isOn: subagentBinding)
          Button("Send test notification") { store.send(.sendTestPushTapped) }
            .disabled(store.testPushStatus == .sending)
          switch store.testPushStatus {
          case .idle:
            EmptyView()
          case .sending:
            Label("Sending…", systemImage: "paperplane")
              .foregroundStyle(.secondary).font(.footnote)
          case .sent:
            Label("Test notification sent", systemImage: "checkmark.circle")
              .foregroundStyle(.green).font(.footnote)
          case .failed:
            Label("Couldn't send test notification", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange).font(.footnote)
          }
          Button("How push notifications work") { showingPushGuide = true }
            .font(.footnote)
        } else {
          Label("Notifications aren't available on this server", systemImage: "bell.slash")
            .foregroundStyle(.secondary).font(.footnote)
          Button("How to enable push notifications") { showingPushGuide = true }
        }
      } header: {
        Text("Notifications")
      } footer: {
        if store.pushAvailable {
          Text("Choose which push categories alert on this iPhone. Approvals are always shown when notifications are enabled.")
        } else {
          Text("Needs the hermes-push plugin running on your agent. Personal Team builds without an APNs entitlement can still use Hermes Control; notifications are simply unavailable.")
        }
      }

      Section {
        LabeledContent("App", value: "Hermes Control")
        LabeledContent("Version", value: store.appVersion.isEmpty ? "—" : store.appVersion)
        Label("Companion for the open-source Hermes Agent", systemImage: "info.circle")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityElement(children: .combine)
      } header: {
        Text("About")
      } footer: {
        Text("Hermes Control is an independent iOS companion. Agent and server are separate open-source projects.")
      }

      Section {
        Button("Clear token & disconnect", role: .destructive) {
          store.send(.clearTokenTapped)
        }
      } footer: {
        Text("Removes the token from the Keychain and returns to the connection screen.")
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if showsDoneButton {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { store.send(.doneTapped) }
        }
      }
    }
    .sheet(isPresented: $showingPushGuide) {
      PushSetupGuideView(
        // Installed → the sheet drops the "Later" snooze and asks the agent to UPDATE rather
        // than install. It is never purely informational: an installed-but-outdated plugin is
        // exactly the case that needs an action here.
        pluginInstalled: store.pushAvailable,
        onAskAgent: {
          showingPushGuide = false
          store.send(.askAgentToInstallTapped)
        },
        onLater: { showingPushGuide = false }
      )
    }
    .task { store.send(.task) }
  }

  private var turnCompleteBinding: Binding<Bool> {
    Binding(
      get: { store.pushEventPreferences.turnComplete },
      set: { newValue in
        var preferences = store.pushEventPreferences
        preferences.turnComplete = newValue
        store.send(.pushEventPreferenceChanged(preferences))
      }
    )
  }

  private var failureBinding: Binding<Bool> {
    Binding(
      get: { store.pushEventPreferences.failure },
      set: { newValue in
        var preferences = store.pushEventPreferences
        preferences.failure = newValue
        store.send(.pushEventPreferenceChanged(preferences))
      }
    )
  }

  private var subagentBinding: Binding<Bool> {
    Binding(
      get: { store.pushEventPreferences.subagent },
      set: { newValue in
        var preferences = store.pushEventPreferences
        preferences.subagent = newValue
        store.send(.pushEventPreferenceChanged(preferences))
      }
    )
  }

  /// Why the update matters, naming both versions when the agent reported one. Kept in the
  /// view because it is pure display copy — the decision to show it lives in the reducer.
  private var pluginUpdateExplanation: String {
    let latest = PushSetup.minimumPluginVersion
    let reason = "Older versions send a “Turn complete” push each time a delegated subagent finishes."
    guard let installed = store.pushPlugin?.version else {
      return "Update to \(latest). \(reason)"
    }
    return "Installed \(installed), latest \(latest). \(reason)"
  }

  @ViewBuilder
  private var profileStatus: some View {
    switch store.profileLoadState {
    case .idle, .loading:
      ProgressView()
        .controlSize(.small)
        .accessibilityLabel("Loading profiles")
    case .loaded:
      Text(store.profiles.count.formatted())
    case .failed:
      Text("Needs attention")
        .foregroundStyle(.orange)
    case .unsupported:
      Text("Unavailable")
        .foregroundStyle(.secondary)
    }
  }
}
