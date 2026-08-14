import Foundation

/// The three node classes emitted by Hermes' native learning graph.
///
/// `MEMORY.md` entries are agent-authored durable notes, while `USER.md` entries describe
/// the user. Learned skills share the graph and are included because their delete semantics
/// differ: Hermes archives them instead of removing a memory entry.
public enum LearningEntryKind: String, Equatable, Sendable {
  case agentMemory
  case userProfile
  case learnedSkill
}

public struct LearningEntrySummary: Equatable, Sendable, Identifiable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  public var id: String
  public var label: String
  public var kind: LearningEntryKind

  public init(id: String, label: String, kind: LearningEntryKind) {
    self.id = id
    self.label = label
    self.kind = kind
  }

  /// Memory labels are the first line of user-authored content, so diagnostics redact them.
  public var description: String {
    "LearningEntrySummary(id: <redacted>, kind: \(kind.rawValue), label: <redacted>)"
  }

  public var debugDescription: String { description }
}

public struct LearningEntryDetail: Equatable, Sendable, Identifiable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  public var id: String
  public var label: String
  public var kind: LearningEntryKind
  /// Full raw memory entry or SKILL.md returned by `learning.detail`.
  public var content: String

  public init(id: String, label: String, kind: LearningEntryKind, content: String) {
    self.id = id
    self.label = label
    self.kind = kind
    self.content = content
  }

  public var description: String {
    "LearningEntryDetail(id: <redacted>, kind: \(kind.rawValue), content: <redacted>)"
  }

  public var debugDescription: String { description }
}

/// Capacity metadata is optional because current `learning.frames` responses do not report
/// the configured character limits. Hermes defaults are configurable per profile, so the
/// client must not manufacture the documented defaults for a remote server.
public struct LearningCapacityInfo: Equatable, Sendable {
  public var agentMemory: LearningStoreCapacity
  public var userProfile: LearningStoreCapacity

  public init(agentMemory: LearningStoreCapacity, userProfile: LearningStoreCapacity) {
    self.agentMemory = agentMemory
    self.userProfile = userProfile
  }
}

public struct LearningStoreCapacity: Equatable, Sendable {
  public var usedCharacters: Int
  public var limitCharacters: Int

  public init(usedCharacters: Int, limitCharacters: Int) {
    self.usedCharacters = max(0, usedCharacters)
    self.limitCharacters = max(0, limitCharacters)
  }

  public var remainingCharacters: Int {
    max(0, limitCharacters - usedCharacters)
  }
}

/// The learning gateway methods resolve the server's Hermes home directly and accept no
/// profile selector. A device-local profile choice must therefore never be represented as
/// authoritative scoping for these mutations.
public enum LearningProfileScope: String, Equatable, Sendable {
  case serverDefaultProfile
}

public enum LearningMemoryRefreshPolicy: String, Equatable, Sendable {
  /// Writes persist immediately, but a fresh session captures the latest prompt snapshot.
  /// The current session may continue using the snapshot it started with.
  case freshSessionSnapshot

  public var explanation: String {
    switch self {
    case .freshSessionSnapshot:
      "Changes persist immediately. A fresh session captures the latest memory snapshot; the current session may keep the snapshot it started with."
    }
  }
}

public enum LearningCapabilityAvailability: String, Equatable, Sendable {
  case unsupported
}

public enum LearningCapacityReporting: String, Equatable, Sendable {
  /// `learning.frames` does not expose live character usage or configured limits.
  case notReportedByServer
}

public struct LearningSnapshotMetadata: Equatable, Sendable {
  public var profileScope: LearningProfileScope
  public var memoryRefreshPolicy: LearningMemoryRefreshPolicy
  /// Hermes exposes entry-level detail/edit/delete, but no raw USER.md/MEMORY.md document
  /// replacement RPC. This is explicit metadata, not a speculative filesystem operation.
  public var rawDocumentReplacement: LearningCapabilityAvailability
  /// Explicitly distinguishes an absent native capacity contract from zero usage.
  public var capacityReporting: LearningCapacityReporting

  public init(
    profileScope: LearningProfileScope = .serverDefaultProfile,
    memoryRefreshPolicy: LearningMemoryRefreshPolicy = .freshSessionSnapshot,
    rawDocumentReplacement: LearningCapabilityAvailability = .unsupported,
    capacityReporting: LearningCapacityReporting = .notReportedByServer
  ) {
    self.profileScope = profileScope
    self.memoryRefreshPolicy = memoryRefreshPolicy
    self.rawDocumentReplacement = rawDocumentReplacement
    self.capacityReporting = capacityReporting
  }
}

public struct LearningSnapshot: Equatable, Sendable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  public var entries: [LearningEntrySummary]
  /// Server-reported graph node count, retained even if a future malformed node is skipped.
  public var reportedCount: Int
  public var capacity: LearningCapacityInfo?
  public var metadata: LearningSnapshotMetadata

  public init(
    entries: [LearningEntrySummary] = [],
    reportedCount: Int = 0,
    capacity: LearningCapacityInfo? = nil,
    metadata: LearningSnapshotMetadata = LearningSnapshotMetadata()
  ) {
    self.entries = entries
    self.reportedCount = max(0, reportedCount)
    self.capacity = capacity
    self.metadata = metadata
  }

  public var description: String {
    "LearningSnapshot(entries: \(entries.count), reportedCount: \(reportedCount), capacityReported: \(capacity != nil))"
  }

  public var debugDescription: String { description }
}

public struct LearningEditRequest: Equatable, Sendable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  public var id: String
  public var content: String

  public init(id: String, content: String) {
    self.id = id
    self.content = content
  }

  public var description: String {
    "LearningEditRequest(id: <redacted>, content: <redacted>)"
  }

  public var debugDescription: String { description }
}

public enum LearningMutationAction: String, Equatable, Sendable {
  case updated
  case deleted
  case archived
}

public struct LearningMutationResult: Equatable, Sendable,
  CustomStringConvertible, CustomDebugStringConvertible
{
  public var succeeded: Bool
  public var id: String
  public var action: LearningMutationAction
  /// Native human-readable result. Diagnostics redact it because it can contain a skill name
  /// or server-local detail; callers may show it only in the scoped learning UI.
  public var message: String

  public init(succeeded: Bool, id: String, action: LearningMutationAction, message: String = "") {
    self.succeeded = succeeded
    self.id = id
    self.action = action
    self.message = message
  }

  public var description: String {
    "LearningMutationResult(succeeded: \(succeeded), id: <redacted>, action: \(action.rawValue), message: <redacted>)"
  }

  public var debugDescription: String { description }
}
