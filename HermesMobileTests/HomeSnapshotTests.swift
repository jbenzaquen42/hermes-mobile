import ComposableArchitecture
import HermesKit
import SnapshotTesting
import SwiftUI
import XCTest

@testable import HermesMobile

final class HomeSnapshotTests: SnapshotTestCase {
  /// The native connected landing: operational actions first, freshness visible, and a loaded
  /// card beside cards that independently retain stale/error and unsupported states.
  func testHomeView_partialFailureIsolation() {
    var initial = HomeFeature.State(connection: connection)
    initial.lastSuccessfulRefreshAt = now.addingTimeInterval(-12 * 60)
    initial.cards.gatewayHealth = .init(
      value: HomeGatewayHealth(
        version: "0.12.0",
        gatewayRunning: true,
        gatewayState: "ready",
        activeSessionCount: 2
      ),
      phase: .loaded,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-12 * 60)
    )
    initial.cards.activeProcesses = .init(
      value: HomeActiveProcesses(activeCount: 3),
      phase: .failed("Process details couldn't be refreshed."),
      lastSuccessfulRefreshAt: now.addingTimeInterval(-18 * 60)
    )
    initial.cards.profileModel = .init(
      value: HomeProfileModel(
        profileName: "research",
        model: "claude-sonnet-4",
        provider: "anthropic"
      ),
      phase: .loaded,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-12 * 60)
    )
    initial.cards.runningSessions = .init(
      value: HomeRunningSessions(sessions: [
        HomeSessionSummary(
          id: "session-running",
          title: "Prepare the launch brief",
          updatedAt: now.addingTimeInterval(-4 * 60)
        ),
      ]),
      phase: .loading,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-14 * 60)
    )
    initial.cards.pendingInteractions = .init(
      value: HomePendingInteractions(interactions: [
        HomePendingInteraction(
          id: "approval-1",
          sessionID: "session-running",
          kind: .approval,
          title: "Approve publishing the report"
        ),
      ]),
      phase: .loaded,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-12 * 60)
    )
    initial.cards.recentActivity = .init(
      value: HomeRecentActivity(items: [
        HomeRecentActivityItem(
          id: "activity-1",
          sessionID: "session-finished",
          title: "Validated the source data",
          outcome: .completed,
          occurredAt: now.addingTimeInterval(-38 * 60)
        ),
      ]),
      phase: .loaded,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-12 * 60)
    )
    initial.cards.cronAttention = .init(
      value: HomeCronAttention(jobs: [
        HomeCronJobAttention(id: "daily-report", title: "Daily report", reason: .paused),
      ]),
      phase: .loaded,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-12 * 60)
    )
    initial.cards.kanbanStatus = .init(phase: .unsupported)
    initial.cards.pushHealth = .init(
      value: HomePushHealth(
        pluginStatus: .ready,
        authorizationStatus: .authorized,
        canSendTestPing: true
      ),
      phase: .loaded,
      lastSuccessfulRefreshAt: now.addingTimeInterval(-12 * 60)
    )

    let view = NavigationStack {
      HomeView(
        store: Store(initialState: initial) {
          Reduce<HomeFeature.State, HomeFeature.Action> { _, _ in .none }
        },
        now: now
      )
    }

    assertSnapshot(of: view, as: deviceImage())
  }

  /// All four non-content card phases are pinned together. A regression that replaces the
  /// dashboard with one global spinner/error would necessarily remove this composition.
  func testHomeCardStates() {
    let view = VStack(spacing: 12) {
      HomeStatusCard("Gateway", systemImage: "network", tint: .green) {
        HomeCardStatusView(status: .loading)
      }
      HomeStatusCard("Active processes", systemImage: "cpu", tint: .cyan) {
        HomeCardStatusView(status: .idle)
      }
      HomeStatusCard("Recent activity", systemImage: "clock.arrow.circlepath", tint: .indigo) {
        HomeCardStatusView(
          status: .failed("The activity endpoint timed out."),
          retry: {}
        )
      }
      HomeStatusCard("Board", systemImage: "rectangle.3.group", tint: .purple) {
        HomeCardStatusView(
          status: .unsupported("Install and enable the native Kanban module to use Board.")
        )
      }
    }
    .padding(16)
    .frame(width: 390)
    .background(Color(.systemGroupedBackground))

    assertSnapshot(of: view, as: componentImage())
  }

  /// Selecting an unavailable module still leaves all five native tabs visible and paints an
  /// explicit capability explanation. No module reducer exists behind this destination.
  func testApplicationShell_boardUnavailable() {
    let reason = "Board requires a verified Kanban server module."
    let state = AppFeature.State(
      selectedDestination: .board,
      home: SessionListFeature.State(connection: connection),
      boardAvailability: .unavailable(reason: reason)
    )
    let view = AppView(
      store: Store(initialState: state) {
        Reduce<AppFeature.State, AppFeature.Action> { _, _ in .none }
      }
    )

    assertSnapshot(of: view, as: deviceImage())
  }
}
