import ComposableArchitecture
import Foundation
import Testing

@testable import HermesKit

@MainActor
struct KanbanFeatureTests {
  private let connection = ServerConnection(
    baseURL: URL(string: "https://agent.example")!, token: "tok"
  )

  private var board: KanbanBoard {
    KanbanBoard(
      columns: [
        KanbanColumn(name: "todo", tasks: [
          KanbanTask(id: "t1", title: "Write tests", status: "todo"),
          KanbanTask(id: "t2", title: "Run tests", status: "todo"),
        ]),
        KanbanColumn(name: "done", tasks: [
          KanbanTask(id: "t3", title: "Ship tests", status: "done"),
        ]),
      ],
      assignees: ["dev"],
      latestEventID: 1,
      now: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  @Test func loadStoresBoardAndMarksAvailable() async {
    let board = self.board
    let store = TestStore(
      initialState: KanbanFeature.State(connection: connection)
    ) {
      KanbanFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.hermesREST.kanbanBoard = { @Sendable _, _ in board }
    }
    store.exhaustivity = .off

    await store.send(.task) {
      $0.isVisible = true
      $0.loadState = .loading
    }
    await store.receive(\.loadResponse) {
      $0.writeSupported = true
      $0.board = board
      $0.loadState = .loaded
      $0.isRefreshing = false
    }
    await store.receive(\.delegate.boardBecameAvailable)
    #expect(store.state.board?.columns.first?.tasks.count == 2)
    await store.send(.onDisappear)
  }

  @Test func notFoundMarksUnsupported() async {
    let store = TestStore(
      initialState: KanbanFeature.State(connection: connection)
    ) {
      KanbanFeature()
    } withDependencies: {
      $0.hermesREST.kanbanBoard = { @Sendable _, _ in throw RESTError.notFound }
    }
    store.exhaustivity = .off

    await store.send(.loadResponse(.failure(.notFound))) {
      $0.writeSupported = false
      $0.loadState = .unsupported("Kanban is not available on this server.")
      $0.isRefreshing = false
    }
  }

  @Test func selectingTaskLoadsDetail() async {
    let board = self.board
    let store = TestStore(
      initialState: KanbanFeature.State(
        connection: connection,
        board: board,
        loadState: .loaded
      )
    ) {
      KanbanFeature()
    } withDependencies: {
      $0.hermesREST.kanbanTaskDetail = { @Sendable _, id, _ in
        #expect(id == "t1")
        return KanbanTaskDetail(
          task: KanbanTask(id: "t1", title: "Write tests", status: "todo"),
          comments: [KanbanComment(id: 1, taskID: "t1", author: "dev", body: "hi")],
          runs: []
        )
      }
    }
    store.exhaustivity = .off

    await store.send(.taskTapped("t1")) {
      $0.selectedTaskID = "t1"
      $0.detailLoadState = .loading
    }
    await store.receive(\.detailResponse) {
      $0.detail = KanbanTaskDetail(
        task: KanbanTask(id: "t1", title: "Write tests", status: "todo"),
        comments: [KanbanComment(id: 1, taskID: "t1", author: "dev", body: "hi")],
        runs: []
      )
      $0.detailLoadState = .loaded
    }
  }

  @Test func createSaveUsesVerifiedFieldsAndReloads() async {
    let created = LockIsolated<[KanbanTaskDraft]>([])
    let store = TestStore(
      initialState: KanbanFeature.State(
        connection: connection,
        loadState: .loaded,
        writeSupported: true
      )
    ) {
      KanbanFeature()
    } withDependencies: {
      $0.hermesREST.kanbanCreateTask = { @Sendable _, draft, _ in
        created.withValue { $0.append(draft) }
      }
      $0.hermesREST.kanbanBoard = { @Sendable _, _ in
        KanbanBoard(columns: [
          KanbanColumn(name: "todo", tasks: [KanbanTask(id: "new", title: "Task", status: "todo")])
        ])
      }
    }
    store.exhaustivity = .off

    await store.send(.createTapped) {
      $0.editor = KanbanFeature.EditorState(mode: .create)
    }
    await store.send(.editorTitleChanged("Task"))
    await store.send(.saveEditorTapped) {
      $0.editor?.isSaving = true
    }
    await store.receive(\.saveEditorResponse) {
      $0.editor = nil
    }
    await store.receive(\.loadResponse) {
      $0.board = KanbanBoard(columns: [
        KanbanColumn(name: "todo", tasks: [KanbanTask(id: "new", title: "Task", status: "todo")])
      ])
      $0.loadState = .loaded
      $0.isRefreshing = false
    }
    #expect(created.value.count == 1)
    #expect(created.value.first?.trimmedTitle == "Task")
  }

  @Test func searchFiltersBoard() {
    let state = KanbanFeature.State(
      connection: connection,
      board: board,
      loadState: .loaded,
      searchQuery: "write"
    )

    let filtered = state.filteredBoard
    #expect(filtered?.columns.first(where: { $0.name == "todo" })?.tasks.map(\.id) == ["t1"])
    #expect(filtered?.columns.first(where: { $0.name == "done" })?.tasks.isEmpty == true)
  }

  @Test func deleteConfirmsThenReloads() async {
    let deleted = LockIsolated<[String]>([])
    let board = self.board
    let store = TestStore(
      initialState: KanbanFeature.State(
        connection: connection,
        board: board,
        loadState: .loaded,
        writeSupported: true,
        selectedTaskID: "t2"
      )
    ) {
      KanbanFeature()
    } withDependencies: {
      $0.hermesREST.kanbanDeleteTask = { @Sendable _, id, _ in
        deleted.withValue { $0.append(id) }
      }
      $0.hermesREST.kanbanBoard = { @Sendable _, _ in board }
    }
    store.exhaustivity = .off

    await store.send(.deleteTapped("t2"))
    #expect(store.state.confirmationDialog != nil)
    await store.send(.confirmationDialog(.presented(.confirmDelete("t2")))) {
      $0.confirmationDialog = nil
      $0.actionInFlightIDs = ["t2"]
    }
    await store.receive(\.deleteResponse) {
      $0.actionInFlightIDs = []
      $0.selectedTaskID = nil
      $0.detail = nil
    }
    await store.receive(\.loadResponse) {
      $0.isRefreshing = false
    }
    #expect(deleted.value == ["t2"])
  }
}
