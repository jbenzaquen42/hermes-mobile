import Foundation
import Testing

@testable import HermesKit

struct CronJobTests {
  private func decode(_ json: String) throws -> CronJob {
    try JSONDecoder().decode(CronJob.self, from: Data(json.utf8))
  }

  // MARK: Decoding

  @Test func decodesFullPayload() throws {
    let job = try decode(
      """
      {
        "id": "a1b2c3d4e5f6",
        "name": "Morning digest",
        "prompt": "Summarize my inbox",
        "schedule_display": "every day at 09:00",
        "enabled": true,
        "state": "scheduled",
        "next_run_at": "2026-07-02T09:00:00+00:00",
        "last_run_at": "2026-07-01T09:00:00.123456+00:00",
        "last_status": "success",
        "profile": "default"
      }
      """
    )

    #expect(job.id == "a1b2c3d4e5f6")
    #expect(job.name == "Morning digest")
    #expect(job.prompt == "Summarize my inbox")
    #expect(job.scheduleDisplay == "every day at 09:00")
    #expect(job.enabled == true)
    #expect(job.state == "scheduled")
    #expect(job.nextRunAt == Date(timeIntervalSince1970: 1_782_982_800))
    // Fractional-seconds variant parses too (sub-second precision retained).
    #expect(job.lastRunAt.map { Swift.abs($0.timeIntervalSince1970 - 1_782_896_400.123456) < 0.001 } == true)
    #expect(job.lastStatus == "success")
    #expect(job.profile == "default")
  }

  @Test func decodesMinimalPayloadAndIgnoresUnknowns() throws {
    let job = try decode(
      """
      {"id": "abc123", "future_field": {"nested": true}, "state": "hibernating"}
      """
    )

    #expect(job.id == "abc123")
    #expect(job.name == nil)
    #expect(job.nextRunAt == nil)
    // Unknown state strings pass through raw — never crash, never coerce.
    #expect(job.state == "hibernating")
    #expect(job.effectiveState == "hibernating")
  }

  @Test func unparseableDatesDegradeToNil() throws {
    let job = try decode(
      """
      {"id": "abc123", "next_run_at": "not-a-date", "last_run_at": ""}
      """
    )

    #expect(job.nextRunAt == nil)
    #expect(job.lastRunAt == nil)
  }

  // MARK: Title fallback chain (name → prompt clip → id)

  @Test func titlePrefersName() {
    let job = CronJob(id: "abc", name: "Digest", prompt: "Summarize")
    #expect(job.title == "Digest")
  }

  @Test func titleFallsBackToClippedPrompt() {
    let long = String(repeating: "x", count: 80)
    let job = CronJob(id: "abc", name: "  ", prompt: long)
    #expect(job.title == String(repeating: "x", count: 60) + "…")

    let short = CronJob(id: "abc", prompt: "Summarize my inbox")
    #expect(short.title == "Summarize my inbox")
  }

  @Test func titleFallsBackToID() {
    let job = CronJob(id: "abc123", name: " ", prompt: "\n")
    #expect(job.title == "abc123")
  }

  // MARK: Effective state (explicit wins, else enabled flag)

  @Test func effectiveStateInfersFromEnabledFlag() {
    #expect(CronJob(id: "a", enabled: false).effectiveState == "disabled")
    #expect(CronJob(id: "a", enabled: true).effectiveState == "scheduled")
    #expect(CronJob(id: "a").effectiveState == "scheduled")
    #expect(CronJob(id: "a", enabled: false, state: "paused").effectiveState == "paused")
    #expect(CronJob(id: "a", state: "paused").isPaused)
    #expect(!CronJob(id: "a", state: "running").isPaused)
  }

  // MARK: Session-id → job-id parse

  @Test func parsesJobIDFromRunSessionID() {
    #expect(CronJob.jobID(fromSessionID: "cron_a1b2c3d4e5f6_20260702_090000") == "a1b2c3d4e5f6")
  }

  @Test func parsesJobIDContainingUnderscores() {
    // Legacy/imported job ids can carry underscores — anchor on the datetime tail,
    // not on splitting.
    #expect(CronJob.jobID(fromSessionID: "cron_my_legacy_job_20260702_090000") == "my_legacy_job")
  }

  @Test func rejectsNonCronSessionIDs() {
    #expect(CronJob.jobID(fromSessionID: "20260610_120231_afcca6") == nil)
    #expect(CronJob.jobID(fromSessionID: "cron_missing_datetime_tail") == nil)
    #expect(CronJob.jobID(fromSessionID: "cron_20260702_090000") == nil)  // no job id segment
    #expect(CronJob.jobID(fromSessionID: "") == nil)
  }

  // MARK: Relative run label

  @Test func relativeRunLabelFuture() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(CronJob.relativeRunLabel(for: now.addingTimeInterval(30), now: now) == "in 30 sec.")
    #expect(CronJob.relativeRunLabel(for: now.addingTimeInterval(5 * 60), now: now) == "in 5 min.")
    #expect(CronJob.relativeRunLabel(for: now.addingTimeInterval(7 * 3600), now: now) == "in 7 hr.")
    #expect(CronJob.relativeRunLabel(for: now.addingTimeInterval(86400), now: now) == "in 1 day")
    #expect(CronJob.relativeRunLabel(for: now.addingTimeInterval(3 * 86400), now: now) == "in 3 days")
  }

  @Test func relativeRunLabelPast() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(CronJob.relativeRunLabel(for: now.addingTimeInterval(-90), now: now) == "2 min. ago")
    #expect(CronJob.relativeRunLabel(for: now.addingTimeInterval(-2 * 3600), now: now) == "2 hr. ago")
    #expect(CronJob.relativeRunLabel(for: now.addingTimeInterval(-2 * 86400), now: now) == "2 days ago")
  }

  @Test func relativeRunLabelClampsSubSecondToOneSecond() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(CronJob.relativeRunLabel(for: now, now: now) == "in 1 sec.")
  }

  // MARK: Rich field decoding (Phase 6 contract)

  @Test func decodesRichListPayload() throws {
    let job = try decode(
      """
      {
        "id": "a1b2c3d4e5f6",
        "name": "Morning digest",
        "prompt": "Summarize my inbox",
        "schedule": {"display": "every day at 09:00", "expr": "0 9 * * *", "kind": "cron"},
        "schedule_display": "every day at 09:00",
        "enabled": true,
        "state": "scheduled",
        "next_run_at": "2026-07-02T09:00:00+00:00",
        "last_run_at": "2026-07-01T09:00:00+00:00",
        "last_status": "success",
        "last_error": null,
        "last_delivery_error": null,
        "deliver": "local",
        "model": "claude-sonnet-4-5",
        "provider": "anthropic",
        "base_url": "https://example.test/v1",
        "skills": ["research", "summarize"],
        "repeat": {"times": 5, "completed": 2},
        "no_agent": false,
        "script": null,
        "context_from": ["abc123"],
        "enabled_toolsets": ["shell"],
        "workdir": "/tmp/jobs",
        "created_at": "2026-06-01T00:00:00+00:00",
        "profile": "default",
        "profile_name": "default",
        "is_default_profile": true
      }
      """
    )

    #expect(job.scheduleExpression == "0 9 * * *")
    #expect(job.scheduleKind == "cron")
    #expect(job.deliver == "local")
    #expect(job.model == "claude-sonnet-4-5")
    #expect(job.provider == "anthropic")
    #expect(job.baseURL == "https://example.test/v1")
    #expect(job.skills == ["research", "summarize"])
    #expect(job.repeatTimes == 5)
    #expect(job.repeatCompleted == 2)
    #expect(job.contextFrom == ["abc123"])
    #expect(job.enabledToolsets == ["shell"])
    #expect(job.workdir == "/tmp/jobs")
    #expect(job.effectiveProfile == "default")
    #expect(job.isDefaultProfile == true)
    #expect(job.repeatLabel == "2/5")
  }

  @Test func decodesLegacyIntegerRepeatAndStringSkills() throws {
    let job = try decode(
      """
      {
        "id": "abc123",
        "repeat": 3,
        "skills": "research, summarize",
        "context_from": "abc123"
      }
      """
    )

    #expect(job.repeatTimes == 3)
    #expect(job.repeatCompleted == nil)
    #expect(job.skills == ["research", "summarize"])
    #expect(job.contextFrom == ["abc123"])
  }

  @Test func draftBuildsOnlyVerifiedWritableFields() {
    let draft = CronJobDraft(
      name: "Digest",
      prompt: "Summarize",
      schedule: "0 9 * * *",
      deliver: "telegram",
      model: "model-x",
      provider: "provider-y",
      skills: ["a", "b"]
    )

    let create = draft.createPayload
    #expect(create["name"] as? String == "Digest")
    #expect(create["prompt"] as? String == "Summarize")
    #expect(create["schedule"] as? String == "0 9 * * *")
    #expect(create["deliver"] as? String == "telegram")
    #expect(create["model"] as? String == "model-x")
    #expect(create["provider"] as? String == "provider-y")
    #expect(create["skills"] as? [String] == ["a", "b"])
    #expect(create["repeat"] == nil)

    let update = draft.updatePayload
    let updates = update["updates"] as? [String: Any]
    #expect(updates?["name"] as? String == "Digest")
    #expect(updates?["schedule"] as? String == "0 9 * * *")
    #expect(updates?["model"] as? String == "model-x")
    #expect(updates?["provider"] as? String == "provider-y")
    #expect(updates?["skills"] as? [String] == ["a", "b"])
  }
}
