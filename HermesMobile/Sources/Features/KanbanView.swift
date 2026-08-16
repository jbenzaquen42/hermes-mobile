import ComposableArchitecture
import HermesKit
import SwiftUI

/// Thin SwiftUI shell for the native Kanban plugin. Board polling, capability gating,
/// task detail, and editing live in `KanbanFeature`; this view renders state and forwards
/// user actions.
struct KanbanView: View {
  @Bindable var store: StoreOf<KanbanFeature>

  var body: some View {
    List {
      switch store.loadState {
      case .unsupported(let message):
        ContentUnavailableView {
          Label("Kanban isn't available", systemImage: "rectangle.3.group")
        } description: {
          Text(message)
        }
      case .failed(let message) where store.board == nil:
        ContentUnavailableView {
          Label("Couldn't load Kanban", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        }
        .listRowBackground(Color.clear)
      default:
        if let board = store.filteredBoard {
          ForEach(board.columns.filter { !$0.tasks.isEmpty || $0.name == "running" }) { column in
            Section {
              ForEach(column.tasks) { task in
                Button {
                  store.send(.taskTapped(task.id))
                } label: {
                  KanbanTaskRow(task: task)
                }
                .buttonStyle(.plain)
                .contextMenu {
                  if store.writeSupported != false {
                    Button {
                      store.send(.editTapped(task.id))
                    } label: {
                      Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                      store.send(.deleteTapped(task.id))
                    } label: {
                      Label("Delete", systemImage: "trash")
                    }
                  }
                }
                .disabled(store.actionInFlightIDs.contains(task.id))
              }
            } header: {
              Label(column.name.capitalized, systemImage: "square.stack")
            }
          }
        } else {
          ProgressView("Loading Kanban…")
            .frame(maxWidth: .infinity)
        }
      }
    }
    .searchable(text: searchBinding, prompt: "Search tasks")
    .navigationTitle("Board")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.createTapped)
        } label: {
          Label("New task", systemImage: "plus")
        }
        .disabled(!store.canCreateOrEdit)
      }
      ToolbarItem(placement: .secondaryAction) {
        Button {
          store.send(.refreshTapped)
        } label: {
          Label("Refresh board", systemImage: "arrow.clockwise")
        }
      }
    }
    .refreshable { store.send(.refreshTapped) }
    .task { store.send(.task) }
    .onDisappear { store.send(.onDisappear) }
    .confirmationDialog(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
    .navigationDestination(isPresented: detailIsPresented) {
      if let detail = store.detail {
        KanbanDetailView(detail: detail, store: store)
      } else {
        ProgressView("Loading task…")
      }
    }
    .sheet(isPresented: editorIsPresented) {
      KanbanEditorView(store: store)
    }
  }

  private var searchBinding: Binding<String> {
    Binding(
      get: { store.searchQuery },
      set: { store.send(.searchQueryChanged($0)) }
    )
  }

  private var detailIsPresented: Binding<Bool> {
    Binding(
      get: { store.selectedTaskID != nil },
      set: { isPresented in
        if !isPresented { store.send(.detailDismissed) }
      }
    )
  }

  private var editorIsPresented: Binding<Bool> {
    Binding(
      get: { store.editor != nil },
      set: { isPresented in
        if !isPresented { store.send(.editorDismissed) }
      }
    )
  }
}

private struct KanbanTaskRow: View {
  let task: KanbanTask

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Circle()
        .fill(statusColor(task.status))
        .frame(width: 10, height: 10)
        .padding(.top, 5)
      VStack(alignment: .leading, spacing: 4) {
        Text(task.title)
          .font(.headline)
          .lineLimit(2)
        if let summary = task.latestSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
          Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        HStack(spacing: 8) {
          if let assignee = task.assignee, !assignee.isEmpty {
            Label(assignee, systemImage: "person")
          }
          if let count = task.commentCount, count > 0 {
            Label("\(count)", systemImage: "bubble.left")
          }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
      }
      Spacer()
    }
    .padding(.vertical, 2)
  }

  private func statusColor(_ status: String) -> Color {
    switch status {
    case "done": .green
    case "running": .blue
    case "blocked": .red
    case "review": .orange
    case "triage", "todo", "scheduled", "ready": .gray
    default: .gray
    }
  }
}

private struct KanbanDetailView: View {
  let detail: KanbanTaskDetail
  let store: StoreOf<KanbanFeature>

  var body: some View {
    List {
      Section("Task") {
        Text(detail.task.title)
          .font(.headline)
        if let body = detail.task.body?.trimmingCharacters(in: .whitespacesAndNewlines),
           !body.isEmpty {
          Text(body)
        }
        LabeledContent("Status", value: detail.task.status.capitalized)
        if let assignee = detail.task.assignee, !assignee.isEmpty {
          LabeledContent("Assignee", value: assignee)
        }
        LabeledContent("Priority", value: "\(detail.task.priority ?? 0)")
      }

      if !detail.runs.isEmpty {
        Section("Runs") {
          ForEach(detail.runs) { run in
            VStack(alignment: .leading, spacing: 4) {
              Text(run.status.capitalized)
                .font(.subheadline)
              if let summary = run.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                 !summary.isEmpty {
                Text(summary)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              if let error = run.error?.trimmingCharacters(in: .whitespacesAndNewlines),
                 !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                  .font(.caption)
                  .foregroundStyle(.red)
              }
            }
          }
        }
      }

      if !detail.comments.isEmpty {
        Section("Comments") {
          ForEach(detail.comments) { comment in
            VStack(alignment: .leading, spacing: 4) {
              Text(comment.author)
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(comment.body)
            }
          }
        }
      }

      if store.writeSupported != false {
        Section {
          Button {
            store.send(.editTapped(detail.task.id))
          } label: {
            Label("Edit task", systemImage: "pencil")
          }
          Button(role: .destructive) {
            store.send(.deleteTapped(detail.task.id))
          } label: {
            Label("Delete task", systemImage: "trash")
          }
          .disabled(store.actionInFlightIDs.contains(detail.task.id))
        }
      }
    }
    .navigationTitle(detail.task.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct KanbanEditorView: View {
  let store: StoreOf<KanbanFeature>

  var body: some View {
    if store.editor != nil {
      editorContent
    }
  }

  private var editor: KanbanFeature.EditorState {
    store.editor ?? .init(mode: .create)
  }

  private var editorContent: some View {
    NavigationStack {
      Form {
        Section("Basics") {
          TextField("Title", text: titleBinding)
          TextField("Body", text: bodyBinding, axis: .vertical)
            .lineLimit(3...8)
          TextField("Assignee", text: assigneeBinding)
          Stepper("Priority: \(editor.priority)", value: priorityBinding, in: 0...10)
        }

        if editor.editingTaskID != nil {
          Section("Lane") {
            Picker("Status", selection: statusBinding) {
              ForEach(KanbanFeature.EditorState.statusOptions, id: \.self) { status in
                Text(status.capitalized).tag(status)
              }
            }
          }
        }

        if let message = editor.validationMessage {
          Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(editor.editingTaskID == nil ? "New task" : "Edit task")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { store.send(.editorDismissed) }
            .disabled(editor.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { store.send(.saveEditorTapped) }
            .disabled(editor.isSaving)
        }
      }
      .interactiveDismissDisabled(editor.isSaving)
    }
  }

  private var titleBinding: Binding<String> {
    Binding(
      get: { editor.title },
      set: { store.send(.editorTitleChanged($0)) }
    )
  }

  private var bodyBinding: Binding<String> {
    Binding(
      get: { editor.body },
      set: { store.send(.editorBodyChanged($0)) }
    )
  }

  private var assigneeBinding: Binding<String> {
    Binding(
      get: { editor.assignee },
      set: { store.send(.editorAssigneeChanged($0)) }
    )
  }

  private var priorityBinding: Binding<Int> {
    Binding(
      get: { editor.priority },
      set: { store.send(.editorPriorityChanged($0)) }
    )
  }

  private var statusBinding: Binding<String> {
    Binding(
      get: { editor.status },
      set: { store.send(.editorStatusChanged($0)) }
    )
  }
}

extension KanbanFeature.EditorState {
  static let statusOptions = ["triage", "todo", "scheduled", "ready", "blocked", "review", "done"]
}
