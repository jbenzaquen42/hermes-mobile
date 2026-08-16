import Foundation
import Testing

@testable import HermesKit

struct KanbanTests {
  @Test func decodesBoardColumnsAndTasks() throws {
    let board = try JSONDecoder().decode(
      KanbanBoard.self,
      from: Data("""
      {
        "columns": [
          {"name": "todo", "tasks": [{"id": "t1", "title": "Write tests", "status": "todo", "priority": 3, "comment_count": 2}]},
          {"name": "running", "tasks": [{"id": "t2", "title": "Run tests", "status": "running", "assignee": "dev", "started_at": 1700000000, "worker_pid": 42}]}
        ],
        "tenants": ["work"],
        "assignees": ["dev"],
        "latest_event_id": 99,
        "now": 1700000100
      }
      """.utf8)
    )

    #expect(board.columns.count == 2)
    #expect(board.columns[0].tasks.first?.id == "t1")
    #expect(board.columns[0].tasks.first?.priority == 3)
    #expect(board.columns[0].tasks.first?.commentCount == 2)
    #expect(board.columns[1].tasks.first?.startedAt == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(board.columns[1].tasks.first?.workerPID == 42)
    #expect(board.latestEventID == 99)
  }

  @Test func decodesTaskDetailWithRunsAndComments() throws {
    let detail = try JSONDecoder().decode(
      KanbanTaskDetail.self,
      from: Data("""
      {
        "task": {"id": "t1", "title": "Task", "status": "review"},
        "comments": [{"id": 1, "task_id": "t1", "author": "dev", "body": "please review", "created_at": 1700000000}],
        "runs": [{"id": 10, "task_id": "t1", "profile": "dev", "status": "done", "outcome": "success", "summary": "all good", "started_at": 1700000000, "ended_at": 1700000100}]
      }
      """.utf8)
    )

    #expect(detail.task.id == "t1")
    #expect(detail.comments.first?.author == "dev")
    #expect(detail.runs.first?.status == "done")
    #expect(detail.runs.first?.summary == "all good")
  }

  @Test func draftBuildsVerifiedKanbanPayloads() {
    let draft = KanbanTaskDraft(
      title: "Ship feature", body: "Details", assignee: "dev", priority: 2, status: "ready"
    )
    let create = draft.createPayload
    #expect(create["title"] as? String == "Ship feature")
    #expect(create["body"] as? String == "Details")
    #expect(create["assignee"] as? String == "dev")
    #expect(create["priority"] as? Int == 2)
    #expect(create["status"] == nil)

    let update = draft.updatePayload
    #expect(update["title"] as? String == "Ship feature")
    #expect(update["status"] as? String == "ready")
    #expect(update["priority"] as? Int == 2)
  }
}
