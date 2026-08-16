import ComposableArchitecture
import HermesKit
import SnapshotTesting
import SwiftUI
import XCTest

@testable import HermesMobile

final class KanbanSnapshotTests: SnapshotTestCase {
  func testKanbanBoard_loaded() {
    let state = KanbanFeature.State(
      connection: connection,
      board: KanbanBoard(
        columns: [
          KanbanColumn(name: "todo", tasks: [
            KanbanTask(id: "t1", title: "Write tests", status: "todo", priority: 3),
            KanbanTask(id: "t2", title: "Run tests", status: "todo", assignee: "dev"),
          ]),
          KanbanColumn(name: "running", tasks: [
            KanbanTask(id: "t3", title: "Run CI", status: "running", assignee: "dev"),
          ]),
          KanbanColumn(name: "done", tasks: [
            KanbanTask(id: "t4", title: "Ship", status: "done"),
          ]),
        ],
        assignees: ["dev"],
        latestEventID: 3,
        now: now
      ),
      loadState: .loaded,
      writeSupported: true
    )

    let view = NavigationStack {
      KanbanView(
        store: Store(initialState: state) {
          Reduce<KanbanFeature.State, KanbanFeature.Action> { _, _ in .none }
        }
      )
    }

    assertSnapshot(of: view, as: deviceImage())
  }
}
