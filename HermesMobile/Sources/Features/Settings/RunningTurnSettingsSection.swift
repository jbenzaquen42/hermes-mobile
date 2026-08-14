import HermesKit
import SwiftUI

/// Settings controls for choosing what a normal composer submit does while the agent is
/// already responding. State and persistence remain reducer-owned through the bindings.
struct RunningTurnSettingsSection: View {
  @Binding var behavior: ChatFeature.MidTurnBehavior
  @Binding var queueingEnabled: Bool

  var body: some View {
    Section {
      Picker("Default action", selection: $behavior) {
        preferenceRow(.steer)
        preferenceRow(.redirect)
        preferenceRow(.queue)
          .disabled(!queueingEnabled)
        preferenceRow(.askEveryTime)
      }

      Toggle("Allow Send after completion", isOn: queueingBinding)
    } header: {
      Text("During a response")
    } footer: {
      Text(footerText)
    }
  }

  private var queueingBinding: Binding<Bool> {
    Binding(
      get: { queueingEnabled },
      set: { isEnabled in
        queueingEnabled = isEnabled
        // Never leave the picker pointing at an action the user just disabled.
        if !isEnabled, behavior == .queue { behavior = .steer }
      }
    )
  }

  private func preferenceRow(_ choice: ChatFeature.MidTurnBehavior) -> some View {
    Label(choice.settingsTitle, systemImage: choice.settingsSystemImage)
      .tag(choice)
  }

  private var footerText: String {
    switch behavior {
    case .steer:
      "New text guides the active response without stopping it."
    case .redirect:
      "New text replaces the active direction and restarts the response."
    case .queue:
      "New text waits locally and sends when the current response finishes."
    case .askEveryTime:
      "The composer asks which action to use for each active response."
    }
  }
}

private extension ChatFeature.MidTurnBehavior {
  var settingsTitle: String {
    switch self {
    case .steer: "Steer during response"
    case .redirect: "Redirect during response"
    case .queue: "Queue for next turn"
    case .askEveryTime: "Ask every time"
    }
  }

  var settingsSystemImage: String {
    switch self {
    case .steer: "arrow.turn.up.right"
    case .redirect: "arrow.right.circle"
    case .queue: "clock"
    case .askEveryTime: "questionmark.circle"
    }
  }
}
