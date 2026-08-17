import ComposableArchitecture
import DependenciesMacros
import Foundation

/// Non-secret, persisted app preferences. Currently just the last server URL, kept so
/// the app can auto-reconnect on launch without re-running onboarding (the token lives
/// in `KeychainClient`). Live implementation backs onto `UserDefaults`; an in-memory
/// variant is used for previews and tests.
@DependencyClient
public struct PreferencesClient: Sendable {
  public var loadServerURL: @Sendable () -> String? = { nil }
  public var saveServerURL: @Sendable (_ url: String) -> Void
  public var clearServerURL: @Sendable () -> Void
  /// Last-seen message count per session id — used to flag unread activity.
  public var loadSeenCounts: @Sendable () -> [String: Int] = { [:] }
  public var saveSeenCounts: @Sendable (_ counts: [String: Int]) -> Void
  /// Pinned session ids, ordered = display order in the top "Pinned" section.
  public var loadPinnedIDs: @Sendable () -> [String] = { [] }
  public var savePinnedIDs: @Sendable (_ ids: [String]) -> Void
  /// How the session list groups its rows (workspace vs chronological). Device-local UI pref.
  public var loadGroupingMode: @Sendable () -> SessionGroupingMode = { .default }
  public var saveGroupingMode: @Sendable (_ mode: SessionGroupingMode) -> Void
  /// What Send does while a turn is running. Device-local UI preference; true steering is
  /// the safe default when no value has been stored or an older value can no longer decode.
  public var loadMidTurnBehavior: @Sendable () -> ChatFeature.MidTurnBehavior = { .steer }
  public var saveMidTurnBehavior: @Sendable (_ behavior: ChatFeature.MidTurnBehavior) -> Void
  public var clearMidTurnBehavior: @Sendable () -> Void
  /// The legacy client-side queue is opt-in. A missing value must stay disabled so upgrading
  /// cannot silently change how a running-turn Send is handled.
  public var loadQueueingEnabled: @Sendable () -> Bool = { false }
  public var saveQueueingEnabled: @Sendable (_ enabled: Bool) -> Void
  public var clearQueueingEnabled: @Sendable () -> Void
  /// Currently selected Hermes profile name. Device-local — we never change the server's
  /// sticky active profile. `nil` means the default profile.
  public var loadSelectedProfileID: @Sendable () -> String? = { nil }
  public var saveSelectedProfileID: @Sendable (_ id: String) -> Void
  public var clearSelectedProfileID: @Sendable () -> Void
  /// Last APNs device token we registered with the agent (lowercase hex). Non-secret — it's
  /// just the routing address. Persisted so logout can `unregisterPush` with the right token
  /// even if the live `register()` stream isn't currently producing one. Cleared on logout.
  public var loadPushDeviceToken: @Sendable () -> String? = { nil }
  public var savePushDeviceToken: @Sendable (_ token: String) -> Void
  public var clearPushDeviceToken: @Sendable () -> Void
  /// Push info-sheet snooze: the number of "Later" taps so far (drives the Fibonacci backoff)
  /// and the Date until which the sheet stays suppressed. `nil` count/date means never snoozed.
  /// Cleared on logout (and when the plugin becomes ready, so a later uninstall re-prompts fresh).
  public var loadPushPromptSnooze: @Sendable () -> (count: Int, until: Date)? = { nil }
  public var savePushPromptSnooze: @Sendable (_ count: Int, _ until: Date) -> Void
  public var clearPushPromptSnooze: @Sendable () -> Void
  /// Device-local push event presentation preferences. Defaults to showing approvals and
  /// failures; turn-complete and subagent pushes are opt-in (the generic-body privacy rule
  /// means these are only used to decide whether to present a banner/badge on this device).
  public var loadPushEventPreferences: @Sendable () -> PushEventPreferences = { .default }
  public var savePushEventPreferences: @Sendable (_ preferences: PushEventPreferences) -> Void
  public var clearPushEventPreferences: @Sendable () -> Void
}

public extension PreferencesClient {
  /// Drop the prefs that are scoped to a *specific user/account* — pins, per-session unread
  /// counts, and the selected profile. Used on a re-auth **user-switch** (different account
  /// signs in mid-session) where the prior user's device-local state must not leak across.
  /// The server URL (and grouping mode) survive — the user stays on the same server.
  func clearIdentityScopedPrefs() {
    savePinnedIDs([])
    saveSeenCounts([:])
    clearSelectedProfileID()
  }

  /// Restore the running-turn composer policy used by a fresh install. Called by full logout
  /// paths; an in-place re-auth user switch keeps these device-level interaction preferences.
  func clearChatInputPreferences() {
    clearMidTurnBehavior()
    clearQueueingEnabled()
  }
}

public extension PreferencesClient {
  /// `UserDefaults`-backed implementation.
  static func live(defaults: UserDefaults = .standard) -> PreferencesClient {
    let key = "hermes.server-url"
    let seenKey = "hermes.seen-message-counts"
    let pinnedKey = "hermes.pinned-session-ids"
    let groupingKey = "hermes.session-grouping-mode"
    let midTurnBehaviorKey = "hermes.chat-mid-turn-behavior"
    let queueingEnabledKey = "hermes.chat-queueing-enabled"
    let selectedProfileKey = "hermes.selected-profile-id"
    let pushTokenKey = "hermes.push-device-token"
    let pushSnoozeCountKey = "hermes.push-prompt-snooze-count"
    let pushSnoozeUntilKey = "hermes.push-prompt-snooze-until"
    let pushEventPrefsKey = "hermes.push-event-preferences"
    // UserDefaults is documented thread-safe but not Sendable.
    nonisolated(unsafe) let store = defaults
    return PreferencesClient(
      loadServerURL: { store.string(forKey: key) },
      saveServerURL: { store.set($0, forKey: key) },
      clearServerURL: { store.removeObject(forKey: key) },
      loadSeenCounts: { (store.dictionary(forKey: seenKey) as? [String: Int]) ?? [:] },
      saveSeenCounts: { store.set($0, forKey: seenKey) },
      loadPinnedIDs: { (store.array(forKey: pinnedKey) as? [String]) ?? [] },
      savePinnedIDs: { store.set($0, forKey: pinnedKey) },
      loadGroupingMode: {
        store.string(forKey: groupingKey).flatMap(SessionGroupingMode.init(rawValue:)) ?? .default
      },
      saveGroupingMode: { store.set($0.rawValue, forKey: groupingKey) },
      loadMidTurnBehavior: {
        store.string(forKey: midTurnBehaviorKey)
          .flatMap(ChatFeature.MidTurnBehavior.init(rawValue:)) ?? .steer
      },
      saveMidTurnBehavior: { store.set($0.rawValue, forKey: midTurnBehaviorKey) },
      clearMidTurnBehavior: { store.removeObject(forKey: midTurnBehaviorKey) },
      loadQueueingEnabled: { store.bool(forKey: queueingEnabledKey) },
      saveQueueingEnabled: { store.set($0, forKey: queueingEnabledKey) },
      clearQueueingEnabled: { store.removeObject(forKey: queueingEnabledKey) },
      loadSelectedProfileID: { store.string(forKey: selectedProfileKey) },
      saveSelectedProfileID: { store.set($0, forKey: selectedProfileKey) },
      clearSelectedProfileID: { store.removeObject(forKey: selectedProfileKey) },
      loadPushDeviceToken: { store.string(forKey: pushTokenKey) },
      savePushDeviceToken: { store.set($0, forKey: pushTokenKey) },
      clearPushDeviceToken: { store.removeObject(forKey: pushTokenKey) },
      loadPushPromptSnooze: {
        // A missing `until` (never snoozed) returns nil; the count defaults to 0 otherwise.
        guard store.object(forKey: pushSnoozeUntilKey) != nil else { return nil }
        let until = Date(timeIntervalSince1970: store.double(forKey: pushSnoozeUntilKey))
        return (count: store.integer(forKey: pushSnoozeCountKey), until: until)
      },
      savePushPromptSnooze: { count, until in
        store.set(count, forKey: pushSnoozeCountKey)
        store.set(until.timeIntervalSince1970, forKey: pushSnoozeUntilKey)
      },
      clearPushPromptSnooze: {
        store.removeObject(forKey: pushSnoozeCountKey)
        store.removeObject(forKey: pushSnoozeUntilKey)
      },
      loadPushEventPreferences: {
        guard let raw = store.dictionary(forKey: pushEventPrefsKey) as? [String: Bool] else {
          return .default
        }
        return PushEventPreferences(
          approval: raw["approval"] ?? true,
          turnComplete: raw["turnComplete"] ?? false,
          failure: raw["failure"] ?? true,
          subagent: raw["subagent"] ?? false
        )
      },
      savePushEventPreferences: { preferences in
        store.set([
          "approval": preferences.approval,
          "turnComplete": preferences.turnComplete,
          "failure": preferences.failure,
          "subagent": preferences.subagent,
        ], forKey: pushEventPrefsKey)
      },
      clearPushEventPreferences: {
        store.removeObject(forKey: pushEventPrefsKey)
      }
    )
  }

  /// Deterministic in-memory store for previews and tests.
  static func inMemory() -> PreferencesClient {
    let box = LockIsolated<String?>(nil)
    let seen = LockIsolated<[String: Int]>([:])
    let pinned = LockIsolated<[String]>([])
    let grouping = LockIsolated<SessionGroupingMode>(.default)
    let midTurnBehavior = LockIsolated<ChatFeature.MidTurnBehavior>(.steer)
    let queueingEnabled = LockIsolated(false)
    let selectedProfile = LockIsolated<String?>(nil)
    let pushToken = LockIsolated<String?>(nil)
    let pushSnooze = LockIsolated<(count: Int, until: Date)?>(nil)
    let pushEventPrefs = LockIsolated<PushEventPreferences>(.default)
    return PreferencesClient(
      loadServerURL: { box.value },
      saveServerURL: { url in box.setValue(url) },
      clearServerURL: { box.setValue(nil) },
      loadSeenCounts: { seen.value },
      saveSeenCounts: { seen.setValue($0) },
      loadPinnedIDs: { pinned.value },
      savePinnedIDs: { pinned.setValue($0) },
      loadGroupingMode: { grouping.value },
      saveGroupingMode: { grouping.setValue($0) },
      loadMidTurnBehavior: { midTurnBehavior.value },
      saveMidTurnBehavior: { midTurnBehavior.setValue($0) },
      clearMidTurnBehavior: { midTurnBehavior.setValue(.steer) },
      loadQueueingEnabled: { queueingEnabled.value },
      saveQueueingEnabled: { queueingEnabled.setValue($0) },
      clearQueueingEnabled: { queueingEnabled.setValue(false) },
      loadSelectedProfileID: { selectedProfile.value },
      saveSelectedProfileID: { selectedProfile.setValue($0) },
      clearSelectedProfileID: { selectedProfile.setValue(nil) },
      loadPushDeviceToken: { pushToken.value },
      savePushDeviceToken: { pushToken.setValue($0) },
      clearPushDeviceToken: { pushToken.setValue(nil) },
      loadPushPromptSnooze: { pushSnooze.value },
      savePushPromptSnooze: { count, until in pushSnooze.setValue((count: count, until: until)) },
      clearPushPromptSnooze: { pushSnooze.setValue(nil) },
      loadPushEventPreferences: { pushEventPrefs.value },
      savePushEventPreferences: { pushEventPrefs.setValue($0) },
      clearPushEventPreferences: { pushEventPrefs.setValue(.default) }
    )
  }
}

extension PreferencesClient: DependencyKey {
  public static var liveValue: PreferencesClient { .live() }
  public static var testValue: PreferencesClient { .inMemory() }
}

public extension DependencyValues {
  var preferences: PreferencesClient {
    get { self[PreferencesClient.self] }
    set { self[PreferencesClient.self] = newValue }
  }
}
