import ComposableArchitecture
import Foundation

/// Native Kanban plugin board and task management.
///
/// The plugin's REST surface is mounted under `/api/plugins/kanban`; a missing plugin
/// surfaces as `RESTError.notFound` and the feature keeps the Board tab available while
/// showing an in-feature unsupported state. Polling only runs while the Board tab is
/// visible, and writes reload server-authoritative board/detail state.
@Reducer
public struct KanbanFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    public var boardSlug: String?
    public var board: KanbanBoard?
    public var loadState: LoadState
    public var writeSupported: Bool?
    public var selectedTaskID: String?
    public var detail: KanbanTaskDetail?
    public var detailLoadState: LoadState
    public var searchQuery: String
    public var errorBanner: String?
    public var actionInFlightIDs: Set<String>
    public var editor: EditorState?
    public var isVisible: Bool
    public var isRefreshing: Bool
    @Presents public var confirmationDialog: ConfirmationDialogState<Action.Dialog>?

    public init(
      connection: ServerConnection,
      boardSlug: String? = nil,
      board: KanbanBoard? = nil,
      loadState: LoadState = .idle,
      writeSupported: Bool? = nil,
      selectedTaskID: String? = nil,
      detail: KanbanTaskDetail? = nil,
      detailLoadState: LoadState = .idle,
      searchQuery: String = "",
      errorBanner: String? = nil,
      actionInFlightIDs: Set<String> = [],
      editor: EditorState? = nil,
      isVisible: Bool = false,
      isRefreshing: Bool = false,
      confirmationDialog: ConfirmationDialogState<Action.Dialog>? = nil
    ) {
      self.connection = connection
      self.boardSlug = boardSlug
      self.board = board
      self.loadState = loadState
      self.writeSupported = writeSupported
      self.selectedTaskID = selectedTaskID
      self.detail = detail
      self.detailLoadState = detailLoadState
      self.searchQuery = searchQuery
      self.errorBanner = errorBanner
      self.actionInFlightIDs = actionInFlightIDs
      self.editor = editor
      self.isVisible = isVisible
      self.isRefreshing = isRefreshing
      self.confirmationDialog = confirmationDialog
    }

    public var filteredBoard: KanbanBoard? {
      guard let board else { return nil }
      let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else { return board }
      return KanbanBoard(
        columns: board.columns.map { column in
          KanbanColumn(
            name: column.name,
            tasks: column.tasks.filter { task in
              task.title.localizedCaseInsensitiveContains(query)
                || (task.body?.localizedCaseInsensitiveContains(query) ?? false)
            }
          )
        },
        tenants: board.tenants,
        assignees: board.assignees,
        latestEventID: board.latestEventID,
        now: board.now
      )
    }

    public var canCreateOrEdit: Bool {
      guard loadState == .loaded, writeSupported != false else { return false }
      if editor?.isSaving == true { return false }
      return true
    }
  }

  public enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
    case unsupported(String)
  }

  public struct EditorState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
      case create
      case edit(KanbanTask)
    }

    public var mode: Mode
    public var title: String
    public var body: String
    public var assignee: String
    public var priority: Int
    public var status: String
    public var isSaving: Bool
    public var validationMessage: String?

    public init(mode: Mode, task: KanbanTask? = nil) {
      self.mode = mode
      title = task?.title ?? ""
      body = task?.body ?? ""
      assignee = task?.assignee ?? ""
      priority = task?.priority ?? 0
      status = task?.status ?? "todo"
      isSaving = false
      validationMessage = nil
    }

    public var editingTaskID: String? {
      if case let .edit(task) = mode { return task.id }
      return nil
    }

    public var draft: KanbanTaskDraft {
      KanbanTaskDraft(
        title: title,
        body: body,
        assignee: assignee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : assignee,
        priority: priority,
        status: editingTaskID == nil ? nil : status
      )
    }

    public var validationError: String? {
      let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty {
        return "Title is required."
      }
      return nil
    }
  }

  public enum Action {
    case task
    case onDisappear
    case foreground
    case pollTick
    case refreshTapped
    case loadResponse(Result<KanbanBoard, RESTError>)
    case taskTapped(String)
    case detailResponse(Result<KanbanTaskDetail, RESTError>)
    case detailDismissed
    case createTapped
    case editTapped(String)
    case editorDismissed
    case editorTitleChanged(String)
    case editorBodyChanged(String)
    case editorAssigneeChanged(String)
    case editorPriorityChanged(Int)
    case editorStatusChanged(String)
    case saveEditorTapped
    case saveEditorResponse(Result<Void, RESTError>)
    case deleteTapped(String)
    case deleteResponse(id: String, error: RESTError?)
    case searchQueryChanged(String)
    case errorBannerDismissed
    case confirmationDialog(PresentationAction<Dialog>)
    case delegate(Delegate)

    @CasePathable
    public enum Dialog: Equatable, Sendable {
      case confirmDelete(String)
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case boardBecameAvailable
    }
  }

  private enum CancelID: Hashable {
    case poll
    case load
    case detail
  }

  @Dependency(\.hermesREST) var rest
  @Dependency(\.continuousClock) var clock

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        guard !state.isVisible else { return .none }
        state.isVisible = true
        state.loadState = .loading
        state.errorBanner = nil
        return .merge(
          refresh(&state),
          .run { [clock] send in
            while true {
              try await clock.sleep(for: .seconds(10))
              await send(.pollTick)
            }
          }
          .cancellable(id: CancelID.poll, cancelInFlight: true)
        )

      case .onDisappear:
        state.isVisible = false
        state.isRefreshing = false
        return .merge(
          .cancel(id: CancelID.poll),
          .cancel(id: CancelID.load),
          .cancel(id: CancelID.detail)
        )

      case .foreground:
        guard state.isVisible else { return .none }
        return refresh(&state)

      case .pollTick:
        guard state.isVisible, !state.isRefreshing else { return .none }
        return refresh(&state)

      case .refreshTapped:
        return refresh(&state)

      case let .loadResponse(.success(board)):
        state.writeSupported = state.writeSupported ?? true
        state.board = board
        state.loadState = .loaded
        state.isRefreshing = false
        state.errorBanner = nil
        if let selectedTaskID = state.selectedTaskID,
           !Self.containsTask(id: selectedTaskID, in: board) {
          state.selectedTaskID = nil
          state.detail = nil
          state.detailLoadState = .idle
        }
        return .send(.delegate(.boardBecameAvailable))

      case let .loadResponse(.failure(error)):
        state.isRefreshing = false
        if error == .notFound {
          state.writeSupported = false
          state.board = nil
          state.selectedTaskID = nil
          state.detail = nil
          state.loadState = .unsupported("Kanban is not available on this server.")
          state.errorBanner = nil
        } else if state.board == nil {
          state.loadState = .failed(error.message)
          state.errorBanner = error.message
        } else {
          state.errorBanner = error.message
        }
        return .none

      case let .taskTapped(id):
        guard Self.containsTask(id: id, in: state.board) else { return .none }
        state.selectedTaskID = id
        state.detail = nil
        state.detailLoadState = .loading
        state.errorBanner = nil
        return loadDetail(id, state: state)

      case let .detailResponse(.success(detail)):
        guard state.selectedTaskID == detail.task.id else { return .none }
        state.detail = detail
        state.detailLoadState = .loaded
        return .none

      case let .detailResponse(.failure(error)):
        guard state.selectedTaskID != nil else { return .none }
        state.detailLoadState = .failed(error.message)
        state.errorBanner = error.message
        return .none

      case .detailDismissed:
        guard state.editor?.isSaving != true else { return .none }
        state.selectedTaskID = nil
        state.detail = nil
        state.detailLoadState = .idle
        return .cancel(id: CancelID.detail)

      case .createTapped:
        guard state.canCreateOrEdit else { return .none }
        state.editor = EditorState(mode: .create)
        return .none

      case let .editTapped(id):
        guard state.canCreateOrEdit, let task = Self.task(id: id, in: state.board) else { return .none }
        state.editor = EditorState(mode: .edit(task), task: task)
        return .none

      case .editorDismissed:
        guard state.editor?.isSaving != true else { return .none }
        state.editor = nil
        return .none

      case let .editorTitleChanged(value):
        state.editor?.title = value
        state.editor?.validationMessage = nil
        return .none

      case let .editorBodyChanged(value):
        state.editor?.body = value
        return .none

      case let .editorAssigneeChanged(value):
        state.editor?.assignee = value
        return .none

      case let .editorPriorityChanged(value):
        state.editor?.priority = value
        return .none

      case let .editorStatusChanged(value):
        state.editor?.status = value
        return .none

      case .saveEditorTapped:
        guard let editor = state.editor, !editor.isSaving else { return .none }
        if let validationError = editor.validationError {
          state.editor?.validationMessage = validationError
          return .none
        }
        state.editor?.isSaving = true
        state.editor?.validationMessage = nil
        let draft = editor.draft
        let connection = state.connection
        let boardSlug = state.boardSlug
        let editingID = editor.editingTaskID
        return .run { [rest] send in
          do {
            if let editingID {
              try await rest.kanbanUpdateTask(connection, editingID, draft, boardSlug)
            } else {
              try await rest.kanbanCreateTask(connection, draft, boardSlug)
            }
            await send(.saveEditorResponse(.success(())))
          } catch {
            await send(.saveEditorResponse(.failure(asRESTError(error))))
          }
        }

      case let .saveEditorResponse(.success):
        let selectedTaskID = state.selectedTaskID
        state.editor = nil
        state.errorBanner = nil
        if let selectedTaskID, state.detail?.task.id == selectedTaskID {
          state.detailLoadState = .loading
          return .merge(
            refresh(&state),
            loadDetail(selectedTaskID, state: state)
          )
        }
        return refresh(&state)

      case let .saveEditorResponse(.failure(error)):
        state.editor?.isSaving = false
        state.editor?.validationMessage = error.message
        if error == .notFound {
          state.writeSupported = false
        }
        return .none

      case let .deleteTapped(id):
        guard state.writeSupported != false,
              Self.containsTask(id: id, in: state.board),
              !state.actionInFlightIDs.contains(id) else { return .none }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Delete task?")
        } actions: {
          ButtonState(role: .destructive, action: .confirmDelete(id)) {
            TextState("Delete")
          }
          ButtonState(role: .cancel) {
            TextState("Cancel")
          }
        } message: {
          TextState("This permanently deletes the Kanban task and its history.")
        }
        return .none

      case let .confirmationDialog(.presented(.confirmDelete(id))):
        state.confirmationDialog = nil
        guard state.writeSupported != false,
              Self.containsTask(id: id, in: state.board),
              !state.actionInFlightIDs.contains(id) else { return .none }
        state.actionInFlightIDs.insert(id)
        let connection = state.connection
        let boardSlug = state.boardSlug
        return .run { [rest] send in
          do {
            try await rest.kanbanDeleteTask(connection, id, boardSlug)
            await send(.deleteResponse(id: id, error: nil))
          } catch {
            await send(.deleteResponse(id: id, error: asRESTError(error)))
          }
        }

      case let .deleteResponse(id, error):
        state.actionInFlightIDs.remove(id)
        if let error {
          state.errorBanner = error.message
          return .none
        }
        if state.selectedTaskID == id {
          state.selectedTaskID = nil
          state.detail = nil
          state.detailLoadState = .idle
        }
        return refresh(&state)

      case let .searchQueryChanged(value):
        state.searchQuery = value
        return .none

      case .errorBannerDismissed:
        state.errorBanner = nil
        return .none

      case .confirmationDialog:
        return .none

      case .delegate:
        return .none
      }
    }
  }

  private func refresh(_ state: inout State) -> Effect<Action> {
    state.isRefreshing = true
    state.loadState = state.board == nil ? .loading : state.loadState
    state.errorBanner = nil
    let connection = state.connection
    let boardSlug = state.boardSlug
    return .run { [rest] send in
      do {
        let board = try await rest.kanbanBoard(connection, boardSlug)
        await send(.loadResponse(.success(board)))
      } catch {
        await send(.loadResponse(.failure(asRESTError(error))))
      }
    }
    .cancellable(id: CancelID.load, cancelInFlight: true)
  }

  private func loadDetail(_ id: String, state: State) -> Effect<Action> {
    let connection = state.connection
    let boardSlug = state.boardSlug
    return .run { [rest] send in
      do {
        let detail = try await rest.kanbanTaskDetail(connection, id, boardSlug)
        await send(.detailResponse(.success(detail)))
      } catch {
        await send(.detailResponse(.failure(asRESTError(error))))
      }
    }
    .cancellable(id: CancelID.detail, cancelInFlight: true)
  }

  private static func task(id: String, in board: KanbanBoard?) -> KanbanTask? {
    guard let board else { return nil }
    for column in board.columns {
      if let task = column.tasks.first(where: { $0.id == id }) {
        return task
      }
    }
    return nil
  }

  private static func containsTask(id: String, in board: KanbanBoard?) -> Bool {
    task(id: id, in: board) != nil
  }
}
