import ComposableArchitecture
import HermesKit
import SnapshotTesting
import SwiftUI
import XCTest

@testable import HermesMobile

final class AutomationsSnapshotTests: SnapshotTestCase {
  func testAutomationsList_loaded() {
    let state = AutomationsFeature.State(
      connection: connection,
      profileName: nil,
      jobs: [
        CronJob(
          id: "job1",
          name: "Morning digest",
          prompt: "Summarize my inbox",
          scheduleDisplay: "every day at 09:00",
          scheduleExpression: "0 9 * * *",
          enabled: true,
          state: "scheduled",
          nextRunAt: now.addingTimeInterval(3600),
          lastRunAt: now.addingTimeInterval(-86400),
          lastStatus: "success",
          deliver: "local",
          model: "claude-sonnet-4-5",
          provider: "anthropic",
          skills: ["research"]
        ),
        CronJob(
          id: "job2",
          name: "Nightly backup",
          prompt: "Back up the workspace",
          scheduleDisplay: "every day at 02:00",
          scheduleExpression: "0 2 * * *",
          enabled: false,
          state: "paused"
        ),
      ],
      writeSupported: true,
      listLoadState: .loaded
    )

    let view = NavigationStack {
      AutomationsView(
        store: Store(initialState: state) {
          Reduce<AutomationsFeature.State, AutomationsFeature.Action> { _, _ in .none }
        }
      )
    }

    assertSnapshot(of: view, as: deviceImage())
  }
}
