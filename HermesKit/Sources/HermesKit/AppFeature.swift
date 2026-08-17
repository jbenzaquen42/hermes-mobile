import ComposableArchitecture
import Foundation

/// Root feature: onboarding until connected, then the five-destination application shell.
/// Chats retains the existing session-list → live-chat navigation and ownership policy;
/// Home and Settings are sibling children, while unsupported modules stay inert placeholders.
@Reducer
public struct AppFeature {
  @ObservableState
  public struct State: Equatable {
    public var onboarding: ConnectionFeature.State
    /// The selected top-level destination while connected. Home is the default landing;
    /// chat deep links and chat-creating quick actions select Chats before pushing a marker.
    public var selectedDestination: AppDestination
    /// The independently-loading operational dashboard. Its failure state is isolated from
    /// Chats: a failed Home card can never remove or replace the session list below.
    public var dashboard: HomeFeature.State?
    /// The existing session list is intentionally kept under its historical `home` name for
    /// source compatibility. In the new shell this state powers the Chats destination.
    public var home: SessionListFeature.State? {
      didSet {
        // Keep the connected-shell invariant even in TestStore expectation closures and
        // snapshot fixtures that historically assigned only `home`.
        if let home {
          if oldValue == nil {
            selectedDestination = .home
          }
          if dashboard == nil {
            dashboard = HomeFeature.State(connection: home.connection)
          } else if dashboard?.connection != home.connection {
            // The legacy Settings sheet still lives under SessionList for source/UI
            // compatibility. A token save there mutates the Chats connection in the child;
            // mirror it into Home so both Settings entry points stay authenticated.
            dashboard?.connection = home.connection
          }
          if liveChat?.connection.baseURL == home.connection.baseURL,
             liveChat?.connection != home.connection {
            // A detached slot may outlive Chats while the token is replaced. Keep the next
            // reconnect on the new credential without disturbing its current socket/effects.
            liveChat?.connection = home.connection
          }
        } else {
          dashboard = nil
          settings = nil
          automations = nil
          kanban = nil
          selectedDestination = .home
        }
      }
    }
    /// Root Settings destination. Created lazily when selected and cleared when another tab is
    /// chosen, so its debug-log stream retains the old sheet's presentation lifetime.
    public var settings: SettingsFeature.State?
    /// Automations destination. Created lazily when selected and cleared when leaving the
    /// tab so its polling/refresh only runs while visible and it always captures the current
    /// profile selection. A server without cron keeps the tab available and shows an
    /// in-feature unsupported state instead of disabling navigation.
    public var automations: AutomationsFeature.State?
    /// Board destination. Created lazily when selected and cleared when leaving the tab so
    /// polling/refresh only runs while visible. A server without the native Kanban plugin
    /// keeps the tab available and shows an in-feature unsupported state.
    public var kanban: KanbanFeature.State?
    /// Board capability gate for Home quick actions; once a Kanban board loads, the tab is
    /// available. The Board feature itself also capability-gates a missing plugin.
    public var boardAvailability: AppDestinationAvailability
    /// Automations is implemented and its tab is always available; the feature itself
    /// capability-gates servers without cron support.
    public var automationsAvailability: AppDestinationAvailability
    /// The navigation path holds only thin session-key markers (`ChatScreen.State`) — the
    /// real chat state lives in the `liveChat` slot below, so popping a marker never
    /// destroys the chat's state or effects by itself.
    public var path: StackState<ChatScreen.State> {
      didSet {
        // A pushed marker is only renderable in Chats. This also preserves the invariant in
        // older tests/fixtures that build navigation by appending directly to `path`.
        if !path.isEmpty {
          selectedDestination = .chats
        }
      }
    }
    /// The app-owned "live chat slot": the one open (or detached-but-live) chat. Composed
    /// via `.ifLet`, so its socket, reconnect backoff, thinking ticker, and debounced
    /// persist are slot-rooted and survive navigation pops. One live session at a time —
    /// opening a different session replaces the slot.
    public var liveChat: ChatFeature.State?
    /// True during the launch auto-connect probe — `AppView` shows a brief placeholder
    /// instead of flashing the onboarding screen.
    public var autoConnecting: Bool
    /// The "can't reach the server" screen, raised for **every** launch auto-connect failure
    /// that isn't a verdict on the stored credentials — transport (`.offline`/`.unreachable`)
    /// *and* a server that answered badly (500, 404, 429, 503, a captive portal's
    /// `.decoding`). Only `.unauthorized` / a 401-403 `.server` falls back to prefilled
    /// onboarding; the single rule lives in `ConnectionFailedFeature.isRetryable`, which this
    /// routing defers to. Stored credentials stay untouched — a password-mode user must never
    /// be made to re-type a password that never expired just because Tailscale was off or the
    /// agent threw a 500.
    public var connectionFailed: ConnectionFailedFeature.State?
    /// The re-auth modal, presented when a live (gated) session dies mid-use. While shown,
    /// the dead chat's reconnect stays paused (it pauses itself via `awaitingReauth`).
    @Presents public var reauth: ReauthFeature.State?
    /// Session ids with a pending approval surfaced via a push tap, not yet viewed. The app-icon
    /// badge mirrors `pendingApprovalSessionIDs.count`; tapping/opening a session clears its
    /// entry (and recomputes the badge). A small dedicated count — distinct from the list's
    /// per-session *unread* (`seenCounts`) concept, which tracks message deltas, not approvals.
    public var pendingApprovalSessionIDs: Set<String>
    /// Whether the scene is currently backgrounded (set on `.background`, cleared on
    /// `.active`). Guards `.backgroundGraceExpired`: an expiry whose send escaped just as
    /// the user returned must not tear down the socket `.active` freshly redialed.
    var isSceneBackgrounded = false
    /// The launch auto-connect probe has been started once this process — a re-sent `.task`
    /// (a re-created `AppView`) must never restart it, which would flip the root back to the
    /// "Connecting…" spinner over the retry screen the user is standing on.
    var didRunLaunchProbe = false
    /// A push tap that arrived before the session list existed (cold launch — #46): the
    /// routing in `.pushTapped` can't open anything without `home`, so the tap is stashed
    /// here (single stash, last-wins) and replayed once `.autoConnectSucceeded` / a manual
    /// login creates the list. Process-lifetime only (never persisted) — the race it
    /// covers is intra-launch — and cleared on logout (the stash dies with the identity).
    var pendingPushTap: PushTap?
    /// The server the stashed tap belongs to: the persisted server URL at stash time (the
    /// agent whose push plugin this device registered with). Guards the replay — a login
    /// that targets a DIFFERENT server drops the stash instead of resuming a foreign
    /// session id there (the resume self-heal would silently create a spurious empty
    /// chat). `nil` when no URL was stored at stash time (fully logged out); the replay
    /// then proceeds unverified — the plan's logged-out → login → open flow, accepted
    /// because pushes only come from a server this device registered with.
    ///
    /// This is the best identity available CLIENT-SIDE, not proof of origin: the push
    /// payload carries no server identity (the generic-body privacy rule forbids adding
    /// one), so a push from a STALE registration on a previous server — logout's
    /// unregister is best-effort — is stamped with the CURRENT pref and replays here.
    /// Accepted corner: the worst outcome is the same spurious-empty-chat the self-heal
    /// produces for any unknown id, and logout's unregister keeps the window narrow.
    var pendingPushTapServerURL: URL?

    public init(
      onboarding: ConnectionFeature.State = .init(),
      selectedDestination: AppDestination = .home,
      dashboard: HomeFeature.State? = nil,
      home: SessionListFeature.State? = nil,
      settings: SettingsFeature.State? = nil,
      automations: AutomationsFeature.State? = nil,
      kanban: KanbanFeature.State? = nil,
      boardAvailability: AppDestinationAvailability = .unavailable(
        reason: "Board requires a verified Kanban server module."
      ),
      automationsAvailability: AppDestinationAvailability = .available,
      path: StackState<ChatScreen.State> = .init(),
      liveChat: ChatFeature.State? = nil,
      autoConnecting: Bool = false,
      connectionFailed: ConnectionFailedFeature.State? = nil,
      reauth: ReauthFeature.State? = nil,
      pendingApprovalSessionIDs: Set<String> = []
    ) {
      self.onboarding = onboarding
      self.selectedDestination = path.isEmpty ? selectedDestination : .chats
      self.dashboard = dashboard ?? home.map { HomeFeature.State(connection: $0.connection) }
      self.home = home
      self.settings = settings
      self.automations = automations
      self.kanban = kanban
      self.boardAvailability = boardAvailability
      self.automationsAvailability = automationsAvailability
      self.path = path
      self.liveChat = liveChat
      self.autoConnecting = autoConnecting
      self.connectionFailed = connectionFailed
      self.reauth = reauth
      self.pendingApprovalSessionIDs = pendingApprovalSessionIDs
    }

    /// The session the user is currently viewing — the live chat's session key
    /// (`storedSessionID ?? liveSessionID`) while its marker is pushed, or `nil` when no
    /// chat is on screen (or a new chat whose id hasn't resolved yet). A detached slot
    /// (user on the list) reads `nil` so pushes for that session are NOT suppressed.
    /// Drives foreground push suppression via `.onChange`.
    var currentViewingSessionID: String? {
      guard selectedDestination == .chats, !path.isEmpty else { return nil }
      return liveChat?.sessionKey
    }

    /// The capability status the connected shell renders for a destination. Home, Chats,
    /// and Settings are local app capabilities; Board and Automations must be explicitly
    /// enabled by future verified server probes before they can gain live reducers.
    public func availability(for destination: AppDestination) -> AppDestinationAvailability {
      switch destination {
      case .home, .chats, .settings:
        return .available
      case .board:
        return boardAvailability
      case .automations:
        return automationsAvailability
      }
    }

    /// Whether the dashboard child is currently visible. A computed key path keeps the
    /// `.onChange` type-checker happy without optional-chaining through a large state type.
    public var isDashboardVisible: Bool {
      dashboard?.isVisible ?? false
    }

    /// Which root branch the app shell renders. The precedence is **logic, not layout**, so it
    /// lives here rather than in `AppView`: the connection-failed screen (#62) is reachable
    /// purely by sitting between the `autoConnecting` spinner and the onboarding fallback, and
    /// reordering it would silently disable the whole feature with every other test still
    /// green. Keeping it in the package makes that ordering assertable by `swift test`
    /// instead of a simulator run.
    public var rootScreen: RootScreen {
      if home != nil { return .home }
      if autoConnecting { return .connecting }
      if connectionFailed != nil { return .connectionFailed }
      return .onboarding
    }
  }

  /// The root branches of the app shell, in the order `State.rootScreen` resolves them.
  public enum RootScreen: Equatable, Sendable {
    case home
    case connecting
    case connectionFailed
    case onboarding
  }

  /// App lifecycle phase, mirrored from SwiftUI's `ScenePhase` by the thin app shell so
  /// HermesKit never imports SwiftUI. The shell maps `.active/.inactive/.background` onto
  /// these cases and dispatches `scenePhaseChanged`.
  public enum ScenePhase: Equatable {
    case active
    case inactive
    case background
  }

  public enum Action {
    case task
    /// Select one of the connected shell's five top-level destinations. Unsupported Board
    /// and Automations may be selected to show their isolated explanatory placeholders, but
    /// intentionally have no child action surface.
    case destinationSelected(AppDestination)
    case autoConnectSucceeded(ServerConnection)
    /// The launch probe failed. The `RESTError` decides where we land, via the one rule in
    /// `ConnectionFailedFeature.isRetryable`: only a credentials verdict (`.unauthorized`, or
    /// a `.server` with status 401/403) falls back to onboarding for re-entry — **every**
    /// other failure (transport, 500, 404, 429, 503, `.decoding`) raises the retry screen with
    /// the session intact.
    case autoConnectFailed(ServerConnection, RESTError)
    /// The app's scene phase changed (foreground/background) — observed at the app shell and
    /// fanned out: `.active` reconnects + re-hydrates the open chat and refreshes the list;
    /// `.background`/`.inactive` flushes the open chat's snapshot + anchor immediately, and
    /// `.background` with a RUNNING turn additionally requests a finite background window
    /// (`BackgroundTaskClient`) so the socket keeps streaming ~30s past suspension.
    case scenePhaseChanged(ScenePhase)
    /// A push notification was tapped — deep-link to its session, routed by comparing the
    /// tapped id against the live slot + path (#32): already on screen → badge bookkeeping
    /// only; detached slot match → re-attach push; different session → replace the slot and
    /// SET the path (never stack). Approval taps clear their pending-badge entry on view.
    case pushTapped(PushTap)
    case onboarding(ConnectionFeature.Action)
    /// The launch retry screen's actions (present only while the slot is filled).
    case connectionFailed(ConnectionFailedFeature.Action)
    case dashboard(HomeFeature.Action)
    /// Historical name retained for source compatibility; this is the Chats child.
    case home(SessionListFeature.Action)
    case settings(SettingsFeature.Action)
    case automations(AutomationsFeature.Action)
    case kanban(KanbanFeature.Action)
    /// Clear the lazily-created root Settings child on a follow-up action, after a delegate
    /// action has had a chance to reduce through the child.
    case clearSettings
    case path(StackActionOf<ChatScreen>)
    /// The pushed chat view finished leaving the screen (sent by the destination in
    /// `AppView` — never through the child scope, so a nil slot can be guarded here
    /// instead of tripping the `ifLet` nil-child warning). Forwards the view-session
    /// cleanup (`.viewDisappeared`) and applies the pop-to-list teardown policy AFTER the
    /// pop animation — tearing down at `.popFrom` time would blank the outgoing screen
    /// mid-animation.
    case chatViewDisappeared
    /// The live chat slot's actions — the chat is composed here (via `.ifLet`), NOT in the
    /// navigation path, so its effects survive pops.
    case liveChat(ChatFeature.Action)
    /// Internal: fill the live-chat slot with a fresh chat and (re)set its path marker.
    /// Used when opening while the slot is occupied — sequenced after the old slot's
    /// `.teardown` AND `.clearLiveChat` (the nil-out is what cancels the outgoing chat's
    /// un-ID'd one-shot RPC effects) so nothing can leak into the replacement.
    case fillLiveChat(ChatFeature.State)
    /// Internal: clear the slot after its `.teardown` ran (`teardownSlot`). Nil-ing the
    /// slot makes `ifLet` cancel every remaining child effect — including one-shot RPCs
    /// that carry no cancel ID. Does not touch the path (a replacement resets it in the
    /// immediately-following `.fillLiveChat`).
    case clearLiveChat
    /// Internal: the finite background window (`BackgroundTaskClient`) expired while still
    /// backgrounded — final flush, then disconnect the socket cleanly
    /// (`.teardownSocketOnly`), keeping the chat state in memory for the #26-preserving
    /// foreground re-hydrate.
    case backgroundGraceExpired
    /// Internal: seed Home's pending-interaction card when process-local approval data or
    /// dashboard visibility changes.
    case seedPendingInteractionsIfNeeded
    case reauth(PresentationAction<ReauthFeature.Action>)
  }

  /// Ids for the long-running incoming-tap observer and the background-grace listener.
  private enum CancelID { case pushTaps, backgroundGrace }

  /// Name of the finite background task requested while a running turn is backgrounded
  /// (shows up in OS background-task diagnostics). Tests re-type the literal on purpose —
  /// an accidental rename should fail the suite, not silently follow the constant.
  private static let backgroundGraceTaskName = "hermes.chat.background-grace"

  @Dependency(\.keychain) var keychain
  @Dependency(\.preferences) var preferences
  @Dependency(\.hermesREST) var rest
  @Dependency(\.push) var push
  @Dependency(\.backgroundTask) var backgroundTask
  @Dependency(\.profileDraft) var profileDraft

  public init() {}

  public var body: some ReducerOf<Self> {
    Scope(state: \.onboarding, action: \.onboarding) {
      ConnectionFeature()
    }
    Reduce { state, action in
      switch action {
      case .task:
        // Observe push taps for the whole app lifetime (a tap can arrive cold-launch or while
        // running) and deep-link them; the actual nav happens in `.pushTapped`.
        let tapObserver: Effect<Action> = .run { [push] send in
          for await tap in push.incomingTaps() {
            await send(.pushTapped(tap))
          }
        }
        .cancellable(id: CancelID.pushTaps, cancelInFlight: true)
        // Launch auto-connect: if a persisted session (token *or* gated cookie) + server
        // URL exist, silently validate and skip onboarding. Only runs once, before we have
        // a home. `loadSession` rehydrates a `.cookie` session's cookies into `.shared` so
        // the REST/WS transports authenticate on this fresh launch.
        // `!didRunLaunchProbe` is the real once-per-process gate (see the property): a
        // re-sent `.task` must never start a SECOND probe while the retry screen is up (it
        // would flip the UI back to the "Connecting…" spinner and, on success, build `home`
        // beside a still-populated slot). The other checks are cheap belt-and-braces.
        guard !state.didRunLaunchProbe, state.home == nil, state.connectionFailed == nil,
              !state.autoConnecting,
              let session = keychain.loadSession(.shared),
              let urlString = preferences.loadServerURL(),
              let url = parseServerURL(urlString)
        else { return tapObserver }
        // A `.token` session with an empty token is treated as "no creds" (matches the old
        // `loadToken()`-non-empty guard) so we stay on onboarding rather than probe blindly.
        if case .token("") = session { return tapObserver }
        state.didRunLaunchProbe = true
        state.autoConnecting = true
        let connection = ServerConnection(baseURL: url, auth: session)
        return .merge(
          tapObserver,
          .run { [rest] send in
            do {
              _ = try await rest.sessions(connection, 1, 0, .recent)
              await send(.autoConnectSucceeded(connection))
            } catch {
              await send(.autoConnectFailed(connection, asRESTError(error)))
            }
          }
        )

      case let .destinationSelected(destination):
        // Destination selection exists only inside the connected shell. Keeping this guard in
        // the reducer prevents a stale UI/deep-link action from constructing authenticated
        // children while onboarding or on the retry screen.
        guard let chats = state.home else { return .none }
        guard destination != state.selectedDestination else { return .none }

        let wasShowingChat = state.selectedDestination == .chats && !state.path.isEmpty
        if state.selectedDestination == .settings {
          // Settings owns a long-running debug-log stream. Match its old sheet lifetime by
          // dropping the child whenever its tab stops being visible.
          state.settings = nil
        }
        if state.selectedDestination == .automations {
          // Automations polls only while its tab is visible. Drop the child on the way out
          // so its poll cannot run off-tab and the next visit captures the current profile.
          state.automations = nil
        }
        if state.selectedDestination == .board {
          // Board polling/refresh also runs only while visible; drop the child on the way out.
          state.kanban = nil
        }
        state.selectedDestination = destination
        if destination == .settings {
          state.settings = makeSettingsState(
            chats: chats,
            activeWorkflowProfileName: Self.activeWorkflowProfileName(state.liveChat)
          )
        }
        if destination == .automations {
          state.automations = AutomationsFeature.State(
            connection: chats.connection,
            profileName: chats.scopedProfileName
          )
        }
        if destination == .board {
          state.boardAvailability = .available
          state.kanban = KanbanFeature.State(connection: chats.connection)
        }

        guard wasShowingChat else { return .none }
        // Moving to another top-level destination is a real chat-view disappearance. Reset
        // the marker, then reuse the established detach policy: running/queued work keeps the
        // slot alive; an idle chat is persisted, torn down, and cleared. As with a navigation
        // pop, `AppView` sends `.chatViewDisappeared` after the outgoing view actually leaves;
        // do not fire it early here or the view would deliver cleanup twice.
        state.path.removeAll()
        return .none

      case let .autoConnectSucceeded(connection):
        state.autoConnecting = false
        // Defensive: a retry screen and a live list must never coexist (see the `.task` guard).
        state.connectionFailed = nil
        makeConnectedShell(&state, connection: connection)
        return replayPendingPushTap(&state)

      case let .autoConnectFailed(connection, error):
        state.autoConnecting = false
        guard ConnectionFailedFeature.isRetryable(error) else {
          // Stored creds didn't validate (expired token / dead cookies) — fall back to
          // onboarding for re-entry; retrying can't repair dead credentials.
          fallBackToOnboarding(&state, connection: connection)
          return .none
        }
        // Either we never reached the server, or a proxy told us the agent is down — the
        // stored session is presumed fine, so keep it and offer a Retry instead of dropping to
        // onboarding (which, in password mode, would demand a password that never expired just
        // because the VPN was off).
        state.connectionFailed = ConnectionFailedFeature.State(
          connection: connection, reason: error
        )
        return .none

      case let .connectionFailed(.delegate(.connected(connection))):
        // The retry validated the stored session — identical landing to a successful launch
        // auto-connect, cold-launch push-tap replay included.
        state.connectionFailed = nil
        makeConnectedShell(&state, connection: connection)
        return replayPendingPushTap(&state)

      case let .connectionFailed(.delegate(.credentialsRejected(connection))):
        // The retry reached the server and it turned us away — retrying can't fix that, so
        // land exactly where a launch auth failure lands: prefilled onboarding, nothing
        // cleared, which is also where the connection-help sheet's entry points live.
        state.connectionFailed = nil
        fallBackToOnboarding(&state, connection: connection)
        return .none

      case .connectionFailed(.delegate(.logoutConfirmed)):
        // "Log Out" from the retry screen (confirmed): the user is abandoning the stored
        // session, so run the same logout as "Quit to start" (Keychain session + every pref)
        // and land on a *fresh* onboarding — nothing prefilled, there is no session left to
        // repair. The tap stash and the approval badge set die with the identity too.
        let connection = state.connectionFailed?.connection
        try? keychain.deleteSession()
        preferences.clearServerURL()
        preferences.clearIdentityScopedPrefs()
        profileDraft.removeAll()
        preferences.saveGroupingMode(.default)
        preferences.clearChatInputPreferences()
        state.connectionFailed = nil
        state.path = .init()
        state.liveChat = nil
        state.dashboard = nil
        state.home = nil
        state.settings = nil
        state.automations = nil
        state.kanban = nil
        state.selectedDestination = .home
        state.onboarding = .init()
        state.pendingPushTap = nil
        state.pendingPushTapServerURL = nil
        state.pendingApprovalSessionIDs = []
        return .merge(setBadge(state), unregisterPushOnLogout(connection: connection))

      case let .scenePhaseChanged(phase):
        // Fan lifecycle out to the live chat slot (if any) and the session list — no
        // top-of-path hunting: the slot IS the one live chat, attached or not. We do NOT
        // auto-restore the nav stack on cold launch — opening a session is enough.
        switch phase {
        case .active:
          // Foreground: release the background-execution window (cancel the grace listener;
          // `end()` is idempotent — a no-op when none is active), then re-hydrate the live
          // chat via `.foreground` (which reconnects only if the socket died — a socket the
          // grace window kept alive is reused, not redialed) and refresh the list
          // immediately (don't wait for the poll).
          state.isSceneBackgrounded = false
          return .merge(
            .cancel(id: CancelID.backgroundGrace),
            .run { [backgroundTask] _ in await backgroundTask.end() },
            state.liveChat != nil ? .send(.liveChat(.foreground)) : .none,
            state.dashboard != nil ? .send(.dashboard(.foreground)) : .none,
            state.home != nil ? .send(.home(.pulledToRefresh)) : .none,
            // Stuck on the retry screen? Foregrounding is exactly the moment the user just
            // flipped the VPN back on — re-probe without making them tap. The child SUPERSEDES
            // whatever is in flight (`cancelInFlight` on its probe), so this can't fan out
            // into parallel probes; a stalled one is simply abandoned. Accepted trade-off:
            // `.active` also fires for Control Center / notification-pull / app-switcher
            // blips, so churn can restart the probe more often than the user asked. Gating on
            // "was really backgrounded" would break the main case — flipping airplane mode or
            // Wi-Fi from Control Center never backgrounds the app — and swallowing the
            // foreground is the latch bug this design exists to avoid. One GET per blip.
            state.connectionFailed != nil ? .send(.connectionFailed(.sceneBecameActive)) : .none
          )
        case .background:
          // Backgrounding: flush the live chat's snapshot + anchor IMMEDIATELY (don't rely on
          // the 1s debounce) so a process kill can't lose the latest paint or the timer anchor.
          state.isSceneBackgrounded = true
          guard let chat = state.liveChat else { return .none }
          let flush: Effect<Action> = .send(.liveChat(.persistNow))
          // A RUNNING turn buys itself a finite background window (~30s): the socket simply
          // keeps streaming, no `ChatFeature` changes. If iOS expires the window while still
          // backgrounded, the listener fires `.backgroundGraceExpired` → final flush + clean
          // socket-only disconnect (state stays in memory for the #26-preserving foreground
          // hydrate); catch-up is then the existing push + `.foreground` reconnect. An idle
          // chat starts NO task — nothing to keep alive, no battery burn.
          guard chat.isRunning else { return flush }
          return .merge(
            flush,
            .run { [backgroundTask] send in
              for await _ in await backgroundTask.begin(Self.backgroundGraceTaskName) {
                await send(.backgroundGraceExpired)
              }
            }
            .cancellable(id: CancelID.backgroundGrace, cancelInFlight: true)
          )
        case .inactive:
          // Transient occlusion (app switcher, notification shade): flush only — the process
          // isn't suspending yet, so no background window is needed.
          return state.liveChat != nil ? .send(.liveChat(.persistNow)) : .none
        }

      case .seedPendingInteractionsIfNeeded:
        guard state.dashboard?.isVisible == true else { return .none }
        return .send(.dashboard(.pendingInteractionsUpdated(Self.pendingApprovals(in: state))))

      case .backgroundGraceExpired:
        // The background window ran out while still backgrounded. Final flush, then cancel
        // the socket ONLY — `liveChat` stays in memory so the foreground re-hydrate can
        // preserve the live thinking/tool rows (#26). No explicit `end()` here: the client
        // performed the mandatory end bookkeeping inside its expiration handler before
        // yielding. Guards: an expiry whose send escaped just as `.active` cancelled the
        // listener must be a no-op — `.active` already redialed, and tearing that fresh
        // socket down would strand the chat with no reconnect scheduled. Likewise nothing
        // to do when the slot was already torn down (e.g. the detached turn ended).
        guard state.isSceneBackgrounded, state.liveChat != nil else { return .none }
        return .concatenate(
          .send(.liveChat(.persistNow)),
          .send(.liveChat(.teardownSocketOnly))
        )

      case let .pushTapped(tap):
        // Deep-link a tapped push to its session — routed by comparing `tap.sessionID`
        // against the live slot + path (#32) so a tap for the already-open session never
        // stacks a duplicate chat screen.
        //
        // Badge bookkeeping: an approval tap first MARKS the session pending (it's a relevant
        // approval), then opening it CLEARS that entry below — so a tap that opens nets to zero,
        // while an approval that can't be opened (no list yet) stays badged until viewed.
        if tap.isApproval {
          state.pendingApprovalSessionIDs.insert(tap.sessionID)
        }
        guard state.home != nil else {
          // No session list yet (cold launch still auto-connecting or on onboarding) — can't
          // open. Stash the tap for replay once the list exists (#46), remembering which
          // server it belongs to (the stored URL — the agent this device's push
          // registration points at) so a login to a DIFFERENT server drops it instead of
          // replaying; the badge reflects the now-pending approval either way.
          state.pendingPushTap = tap
          state.pendingPushTapServerURL = preferences.loadServerURL().flatMap(parseServerURL)
          return setBadge(state)
        }
        // The tapped session is the one ALREADY on screen (slot match + marker on the
        // path) → NO navigation. Badge bookkeeping only: the user is now viewing it, so
        // the pending entry clears (mark-then-clear nets zero); the content update arrives
        // in place — the live socket is already streaming, and the tap's app activation
        // fires the existing `.foreground` re-hydrate.
        if state.currentViewingSessionID == tap.sessionID {
          state.pendingApprovalSessionIDs.remove(tap.sessionID)
          // Approval-recovery hint (#30 workaround): the socket may have been down when the
          // `approval.request` fired, so arm the one-shot hint AND drive the consuming
          // hydrate ourselves — the tap's scene activation is delivered independently of
          // this action, so a `.foreground` that reduced BEFORE the tap (or never fires)
          // would otherwise leave the hint armed for an arbitrary later hydrate.
          // `.foreground` is idempotent: it never cancel-and-redials a healthy socket,
          // just re-hydrates. Nil slot guarded (the hint is meaningless without one).
          if tap.isApproval, state.liveChat != nil {
            state.liveChat?.expectsPendingApproval = true
            return .merge(setBadge(state), .send(.liveChat(.foreground)))
          }
          return setBadge(state)
        }
        // Otherwise share the SAME `openSession` flow a list tap uses: a detached slot match
        // (user on the list) pushes the marker back and re-attaches live (no re-init, no dup);
        // a different session replaces the slot and SETS the path to the single new marker
        // (`fillLiveChat` resets rather than appends — no stacking on cold launch either).
        // Prefer the loaded `Session` (carries a title); fall back to a minimal `Session(id:)`
        // if it isn't in the list (the chat resumes by stored id and hydrates the title).
        let session = state.home?.sessions[id: tap.sessionID] ?? Session(id: tap.sessionID)
        // Opening clears the badge entry + marks current-viewing (handled in the openSession case).
        return .send(.home(.delegate(.openSession(session))))

      case let .onboarding(.delegate(.connected(connection))):
        // Defensive, mirroring `.autoConnectSucceeded`: a retry screen and a live list must
        // never coexist. `AppView` would render `home` while the `ifLet` child stayed alive,
        // re-probing on every foreground for the process lifetime.
        state.connectionFailed = nil
        makeConnectedShell(&state, connection: connection)
        // Auto-connect failure falls back to onboarding, so a manual login must also replay
        // a stashed cold-launch tap (#46).
        return replayPendingPushTap(&state)

      case .dashboard(.delegate(.newChat)):
        // Home never owns chat construction. Route through the existing SessionList delegate
        // so profile scoping, slot replacement, and composer preference seeding stay singular.
        guard state.home != nil else { return .none }
        return .send(.home(.delegate(.createSession(initialComposerText: nil))))

      case let .dashboard(.delegate(.openSession(id))):
        guard let chats = state.home else { return .none }
        // Prefer the loaded row for its resolved title; Home summaries and the active-chat
        // shortcut may also point at a session outside the current list, which the established
        // minimal-session resume path already supports.
        let session = chats.sessions[id: id] ?? Session(id: id)
        return .send(.home(.delegate(.openSession(session))))

      case .dashboard(.delegate(.createKanbanTask)):
        // Require the successfully-loaded Kanban card as the capability proof even if a stale
        // or programmatic delegate slips past the disabled button. Phase 2 still has no Board
        // reducer: mark the module verified and show the placeholder without another RPC.
        guard state.dashboard?.cards.kanbanStatus.hasLoadedValue == true,
              state.dashboard?.cards.kanbanStatus.isUnsupported == false
        else { return .none }
        state.boardAvailability = .available
        return .send(.destinationSelected(.board))

      case .dashboard(.delegate(.createScheduledJob)):
        // Same isolation rule as Board. A successful cron-attention card proves the module,
        // but create/edit behavior belongs to the later Automations phase.
        guard state.dashboard?.cards.cronAttention.hasLoadedValue == true,
              state.dashboard?.cards.cronAttention.isUnsupported == false
        else { return .none }
        state.automationsAvailability = .available
        return .send(.destinationSelected(.automations))

      case let .dashboard(.delegate(.openPendingInteraction(interaction))):
        guard let chats = state.home else { return .none }
        if interaction.kind == .approval {
          // Reuse the existing approval-recovery handshake: the normal open route reads this
          // marker before clearing it and arms `expectsPendingApproval` on the chat. A
          // clarification opens normally because its payload cannot be synthesized here.
          state.pendingApprovalSessionIDs.insert(interaction.sessionID)
        }
        let session = chats.sessions[id: interaction.sessionID]
          ?? Session(id: interaction.sessionID)
        return .send(.home(.delegate(.openSession(session))))

      case let .settings(.delegate(.tokenSaved(token))):
        // Settings updates its own connection before delegating. Keep every authenticated
        // sibling on the same token so the next Home refresh or Chats action cannot use the
        // stale credential.
        state.home?.connection.token = token
        state.dashboard?.connection.token = token
        return .none

      case .settings(.delegate(.disconnect)):
        // Let the child reduce the delegate first, then clear its optional state and reuse the
        // existing Chats disconnect route (badge, push unregister, and shell teardown included).
        return .concatenate(
          .send(.clearSettings),
          .send(.home(.delegate(.disconnect)))
        )

      case .settings(.delegate(.reconnect)):
        state.selectedDestination = .chats
        return .concatenate(
          .send(.clearSettings),
          .merge(
            state.home != nil ? .send(.home(.pulledToRefresh)) : .none,
            state.dashboard != nil ? .send(.dashboard(.pulledToRefresh)) : .none
          )
        )

      case let .settings(
        .delegate(.chatInputPreferencesChanged(behavior, queueingEnabled))
      ):
        state.liveChat?.midTurnBehavior = behavior
        state.liveChat?.queueingEnabled = queueingEnabled
        return .none

      case let .settings(.delegate(.profilesChanged(summaries))):
        guard state.home != nil else { return .none }
        state.home?.profiles = IdentifiedArray(uniqueElements: summaries.map {
          Profile(
            name: $0.name,
            isDefault: $0.isDefault,
            model: $0.model,
            provider: $0.provider,
            skillCount: $0.skillCount
          )
        })
        state.home?.profilesSupported = true
        guard let selected = state.home?.selectedProfileName,
              state.home?.profiles[id: selected] == nil else { return .none }
        return .send(.home(.selectProfile(name: SessionListFeature.State.defaultProfileName)))

      case .settings(.delegate(.profileCreated)):
        // The following native profiles.list response carries the authoritative row and
        // flows through `profilesChanged`; creating a profile does not change Chats' device-
        // local selection by itself.
        return .none

      case let .settings(.delegate(.profileRenamed(oldName, newName))):
        if let old = state.home?.profiles[id: oldName] {
          var renamed = old
          renamed.name = newName
          state.home?.profiles[id: oldName] = nil
          state.home?.profiles.append(renamed)
        }
        if state.home?.selectedProfileName == oldName {
          state.home?.selectedProfileName = newName
          preferences.saveSelectedProfileID(newName)
        }
        if state.liveChat?.profileName == oldName {
          state.liveChat?.profileName = newName
        }
        if state.settings?.activeWorkflowProfileName == oldName {
          state.settings?.activeWorkflowProfileName = newName
        }
        return .none

      case let .settings(.delegate(.profileDeleted(name))):
        state.home?.profiles[id: name] = nil
        let selectDefault: Effect<Action> = state.home?.selectedProfileName == name
          ? .send(.home(.selectProfile(name: SessionListFeature.State.defaultProfileName)))
          : .none
        let clearDeletedChat = state.liveChat?.profileName == name ? teardownSlot() : .none
        return .merge(selectDefault, clearDeletedChat)

      case .settings(.delegate(.installPushPlugin)):
        // Root Settings is not a sheet, but the intent is identical: leave Settings and open
        // a reviewable, pre-filled chat through the SessionList delegate path.
        return .concatenate(
          .send(.clearSettings),
          .send(
            .home(
              .delegate(.createSession(initialComposerText: PushSetup.installPrompt))
            )
          )
        )

      case .clearSettings:
        state.settings = nil
        return .none

      case let .home(.delegate(.openSession(session))):
        guard let home = state.home else { return .none }
        state.selectedDestination = .chats
        state.settings = nil
        state.automations = nil
        state.kanban = nil
        // Approval-recovery hint (#30 workaround): a badged session (approval push tapped or
        // received) may have missed the real `approval.request` while detached — read the flag
        // BEFORE clearing the badge entry so the hydrating chat can synthesize a generic card
        // when the turn is still running. Covers tap→open, slot replacement, and a badged
        // session opened later from the list.
        let expectsApproval = state.pendingApprovalSessionIDs.contains(session.id)
        // Opening a session clears its pending-approval badge entry (the user is now viewing it).
        // The current-viewing marker is updated by the `.onChange(of: currentViewingSessionID)`
        // modifier below (one source of truth for nav-derived state).
        state.pendingApprovalSessionIDs.remove(session.id)
        let badge = setBadge(state)
        // Re-opening the slot's OWN session (e.g. tapping the glowing row of a detached
        // running turn): the accumulated live state must survive — a fresh
        // `ChatFeature.State` would discard the detached thinking/tool/streaming rows.
        // Push the marker back (the path is empty when coming from the list) and
        // re-attach: hydrate against the live socket, reconnecting only if it died.
        if let chat = state.liveChat, chat.sessionKey == session.id {
          if expectsApproval {
            state.liveChat?.expectsPendingApproval = true
          }
          // Defensive guard: the path is normally empty here (re-opens come from the list,
          // and an on-screen match short-circuits in `pushTapped` before reaching this
          // delegate) — but a double-delivered open must not stack a second marker.
          if state.path.isEmpty {
            state.path.append(ChatScreen.State(sessionKey: session.id))
          }
          return .merge(badge, .send(.liveChat(.reattached)))
        }
        // `resolvedTitle` keeps the server's "Untitled" placeholder out of the header
        // (and the rename pre-fill); a real title arrives via `session.info` on resume.
        // Carry the active profile so resume/history scope to the right `state.db`.
        var chat = ChatFeature.State(
          connection: home.connection,
          resumeStoredID: session.id,
          profileName: home.scopedProfileName,
          title: session.resolvedTitle
        )
        chat.expectsPendingApproval = expectsApproval
        guard state.liveChat != nil else {
          fillLiveChat(chat, into: &state)
          return badge
        }
        // Slot occupied (e.g. a push tap while a chat is open): replace it — the old chat
        // must be fully torn down (through the nil-out, so even its un-ID'd one-shot RPC
        // effects are cancelled) before the new chat fills the slot.
        return .merge(badge, teardownSlot(thenFill: chat))

      case let .home(.delegate(.createSession(initialComposerText))):
        guard let home = state.home else { return .none }
        // New chats are created under the currently-selected profile. `initialComposerText`
        // (push "Ask agent to install") seeds the composer draft but is NOT auto-sent.
        let chat = ChatFeature.State(
          connection: home.connection,
          profileName: home.scopedProfileName,
          composerText: initialComposerText ?? ""
        )
        guard state.liveChat != nil else {
          fillLiveChat(chat, into: &state)
          return .none
        }
        // Slot occupied: flush + fully tear the old chat down before filling (same rule
        // as open — the replacement goes through the nil-out).
        return teardownSlot(thenFill: chat)

      case let .fillLiveChat(chat):
        fillLiveChat(chat, into: &state)
        return .none

      case .clearLiveChat:
        // Pop-to-list teardown completed — drop the slot state. `ifLet` auto-cancels any
        // remaining child effects on the nil-out.
        state.liveChat = nil
        return .none

      case .path(.popFrom):
        // Popped back to the session list. Nothing to do at pop-START: the teardown policy
        // runs on `.chatViewDisappeared` (below), once the pop animation has finished —
        // clearing the slot here would blank the outgoing screen mid-animation and route
        // the view's disappearance into a nil child.
        return .none

      case .chatViewDisappeared:
        // The pushed chat view finished leaving the screen: the pop animation completed,
        // or its marker was swapped by a slot replacement. Forward the view-session
        // cleanup (mic/voice) to whatever chat owns the slot, then apply the pop policy:
        // a RUNNING detached turn keeps its slot untouched — the socket streams on, rows
        // accumulate, and the list's row glow tracks via `runningChanged` (whose
        // `running: false` while detached tears the slot down below). An idle detached
        // chat has nothing to keep alive — flush the snapshot, cancel everything, clear
        // the slot. A non-empty path means the disappearance came from a slot replacement
        // (the new chat is on screen) → cleanup only. No slot (logout/quit/teardown
        // already cleared it) → no-op.
        guard let chat = state.liveChat else { return .none }
        let cleanup: Effect<Action> = .send(.liveChat(.viewDisappeared))
        // `hasQueuedWork` (#66) keeps the slot alive like a running turn does: queued
        // prompts are in-memory only, so an idle pop with entries waiting (a parked
        // queue, or the gap before a drain's turn starts) must not destroy them — the
        // drain fires the next turn into the detached slot, and teardown comes when the
        // queue empties and that turn ends (the `runningChanged` policy below).
        guard state.path.isEmpty, !chat.isRunning, !chat.hasQueuedWork else { return cleanup }
        return .concatenate(cleanup, teardownSlot())

      case let .home(.delegate(.sessionArchived(id))):
        // The user archived a session from the list. If it's the slot's session (possibly
        // detached mid-turn), tear the live chat down FIRST — its socket must not keep
        // streaming into a session that's now archived. Any other session → nothing to do
        // (the list's optimistic archive handles itself).
        guard let chat = state.liveChat, chat.sessionKey == id else { return .none }
        // Deliberate asymmetry: if the archive PATCH later FAILS, the list restores the
        // row (optimistic rollback) but the slot stays torn down — re-opening simply
        // resumes the session fresh. Resurrecting live slot state for a rare failure path
        // isn't worth replaying the teardown.
        return teardownSlot()

      case .home(.delegate(.disconnect)):
        // Token cleared in Settings → tear down and return to onboarding. Nil-ing the slot
        // auto-cancels its effects (socket included). The tap stash is structurally nil
        // here (home existed, so any stash was consumed at creation) — cleared
        // defensively: the stash dies with the identity. The pending-approval badge set
        // dies with it too (entries reference sessions on the server just left — they'd
        // leak a stale icon badge into the next login), so reset the badge to zero.
        let connection = state.home?.connection
        state.path = .init()
        state.liveChat = nil
        state.dashboard = nil
        state.home = nil
        state.settings = nil
        state.automations = nil
        state.kanban = nil
        state.selectedDestination = .home
        state.onboarding = .init()
        state.pendingPushTap = nil
        state.pendingPushTapServerURL = nil
        state.pendingApprovalSessionIDs = []
        return .merge(setBadge(state), unregisterPushOnLogout(connection: connection))

      case let .home(.delegate(.chatInputPreferencesChanged(behavior, queueingEnabled))):
        state.liveChat?.midTurnBehavior = behavior
        state.liveChat?.queueingEnabled = queueingEnabled
        return .none

      case .liveChat(.delegate(.sessionExpired)):
        // The live (gated) session died — attached or detached, the slot is the one chat.
        // The chat already paused its own reconnect; raise the re-auth modal seeded from its
        // connection (server URL + regime + identity). Ignore if a modal is already up.
        guard state.reauth == nil, let chat = state.liveChat else { return .none }
        state.reauth = makeReauthState(for: chat.connection)
        return .none

      case let .reauth(.presented(.delegate(.reauthenticated(connection, sameUser)))):
        state.reauth = nil
        if sameUser {
          // Same user → resume the dead slot chat in place with the fresh auth regime.
          guard state.liveChat != nil else { return .none }
          return .send(.liveChat(.resumeAfterReauth(connection)))
        }
        // Different user signed in → drop everything identity-scoped and force a fresh list.
        // (`makeHomeState` reads the profile pref AFTER the clear, so it seeds defaults.)
        // The approval badge set + tap stash are identity-scoped too — the old user's
        // pending approvals must not badge (or replay into) the new user's list.
        preferences.clearIdentityScopedPrefs()
        profileDraft.removeAll()
        state.path = .init()
        state.liveChat = nil
        state.pendingPushTap = nil
        state.pendingPushTapServerURL = nil
        state.pendingApprovalSessionIDs = []
        makeConnectedShell(&state, connection: connection)
        return setBadge(state)

      case .reauth(.presented(.delegate(.quit))):
        // "Quit to start" → full logout (Keychain session + every pref) → onboarding.
        // The tap stash and the approval badge set die with the identity (same clears
        // as `.disconnect`, through the other logout path); badge reset to zero.
        let connection = state.home?.connection ?? state.liveChat?.connection
        try? keychain.deleteSession()
        preferences.clearServerURL()
        preferences.clearIdentityScopedPrefs()
        profileDraft.removeAll()
        preferences.saveGroupingMode(.default)
        preferences.clearChatInputPreferences()
        state.reauth = nil
        state.path = .init()
        state.liveChat = nil
        state.dashboard = nil
        state.home = nil
        state.settings = nil
        state.automations = nil
        state.kanban = nil
        state.selectedDestination = .home
        state.onboarding = .init()
        state.pendingPushTap = nil
        state.pendingPushTapServerURL = nil
        state.pendingApprovalSessionIDs = []
        return .merge(setBadge(state), unregisterPushOnLogout(connection: connection))

      case let .liveChat(.delegate(.branchCreated(creation))):
        // A branch `session.create` resolved (#34). The new session lives ONLY in server
        // memory until its first prompt (the DB row is created lazily), so it must NOT go
        // through the resume-by-stored-id `openSession` flow — `session.resume` hard-fails
        // "session not found" without a DB row, and the not-found self-heal would then
        // strand the user in a fresh, unrelated, EMPTY session. Mirror the desktop's fork
        // flow instead: prime the replacement chat straight from the create response —
        // the stored id (list/marker identity) plus `attachLiveSessionID`, which makes
        // the new chat's socket attach via `session.activate` (re-binding the live
        // session's transport and returning the seeded history), plus the SEED (text +
        // parent id) so a server-side orphan reap of the never-prompted branch can be
        // healed by replaying the seeded create. Slot replacement still runs through
        // `teardownSlot(thenFill:)` (persist → teardown → nil-out → fill — never a
        // direct swap). Finally request a list refetch so the branch shows (nested
        // under its parent) once its DB row exists server-side — an abandoned branch
        // simply never appears (documented v1 behavior, no optimistic insert).
        guard let home = state.home else { return .none }
        var chat = ChatFeature.State(
          connection: home.connection,
          resumeStoredID: creation.handle.storedSessionID,
          profileName: home.scopedProfileName
        )
        chat.attachLiveSessionID = creation.handle.sessionID
        chat.branchSeed = creation.seed
        let reload: Effect<Action> = .send(.home(.pulledToRefresh))
        guard state.liveChat != nil else {
          fillLiveChat(chat, into: &state)
          return reload
        }
        return .concatenate(teardownSlot(thenFill: chat), reload)

      case let .liveChat(.delegate(.runningChanged(sessionID, running))):
        // Route the live chat's authoritative working-state change to the session list so its
        // row glow clears/lights INSTANTLY (event-driven), without waiting for the next poll.
        // The poll stays the backstop for not-open sessions. No `home` → nothing to patch.
        let glow: Effect<Action> = state.home != nil
          ? .send(.home(.setSessionRunning(id: sessionID, running: running)))
          : .none
        let activeProfile = running ? Self.activeWorkflowProfileName(state.liveChat) : nil
        state.settings?.activeWorkflowProfileName = activeProfile
        if state.settings?.capabilityManagement != nil {
          state.settings?.capabilityManagement?.hasActiveWorkflow =
            state.settings?.capabilityManagement?.profileName == activeProfile
        }
        // A DETACHED slot (no marker in the path — the user popped to the list) only
        // outlives the pop while its turn runs. The turn ending — `message.complete`,
        // `.error`, or a foreground hydrate confirming `running == false` — means there's
        // nothing left to keep alive: flush the snapshot, then tear the slot down.
        // UNLESS the queue still owes work (#66): the chat's own reducer drained (or
        // parked) in the same reduction that emitted this delegate, so by now
        // `hasQueuedWork` is true exactly when a next turn is mid-drain or entries are
        // parked waiting — either way the in-memory queue must survive. The drained
        // turn's own end (queue empty by then) re-enters here and tears down normally;
        // a queue parked by an error while detached deliberately keeps the slot (bounded
        // by the user re-opening or archiving the session).
        guard !running, state.path.isEmpty, let chat = state.liveChat, !chat.hasQueuedWork
        else { return glow }
        return .concatenate(glow, teardownSlot())

      case .onboarding, .connectionFailed, .dashboard, .home, .settings, .automations, .kanban,
           .path, .reauth, .liveChat:
        return .none
      }
    }
    .ifLet(\.connectionFailed, action: \.connectionFailed) {
      ConnectionFailedFeature()
    }
    .ifLet(\.dashboard, action: \.dashboard) {
      HomeFeature()
    }
    .ifLet(\.home, action: \.home) {
      SessionListFeature()
    }
    .ifLet(\.settings, action: \.settings) {
      SettingsFeature()
    }
    .ifLet(\.automations, action: \.automations) {
      AutomationsFeature()
    }
    .ifLet(\.kanban, action: \.kanban) {
      KanbanFeature()
    }
    .ifLet(\.$reauth, action: \.reauth) {
      ReauthFeature()
    }
    .ifLet(\.liveChat, action: \.liveChat) {
      ChatFeature()
    }
    .forEach(\.path, action: \.path) {
      ChatScreen()
    }
    // Keep the push bridge's "currently viewing" session in sync with the slot + nav stack
    // (one source of truth, evaluated AFTER the child reducers so pops/dismissals AND a new chat
    // resolving its `liveSessionID` are reflected) so a foreground push for the on-screen session
    // is suppressed. Opening, popping back to the list, and id-resolution all flow through here.
    .onChange(of: \.currentViewingSessionID) { _, newValue in
      Reduce { _, _ in
        .run { [push] _ in push.setCurrentSession(newValue) }
      }
    }
    // Hermes has no global pending-interaction read endpoint. While Home is visible, project
    // the process-local approval knowledge AppFeature already owns into its card; the child
    // action also cancels the unsupported network probe so a late response cannot erase it.
    .onChange(of: \.pendingApprovalSessionIDs) { _, _ in
      .send(.seedPendingInteractionsIfNeeded)
    }
    // A badge may have arrived while another tab was selected. Seed the same process-local
    // summaries when Home becomes visible rather than waiting for another set mutation.
    .onChange(of: \.isDashboardVisible) { _, isVisible in
      isVisible ? .send(.seedPendingInteractionsIfNeeded) : .none
    }
  }

  /// The standard "slot is done" sequence (idle view-disappearance, detached turn
  /// completion, archived session, slot replacement): flush the snapshot + turn anchor
  /// first (the debounced persist is about to be cancelled), cancel every long-running
  /// chat effect, then clear the slot — the nil-out makes `ifLet` cancel ALL remaining
  /// child effects, including the un-ID'd one-shot RPCs (hydrate, submit, rename …) whose
  /// results must never reduce into a replacement chat. Passing `thenFill` replaces the
  /// slot with a fresh chat right after the clear. Any background grace window is released
  /// early in parallel (idempotent no-ops in the foreground) — a torn-down slot has
  /// nothing left for the OS task to keep alive.
  ///
  /// The action chain is delivered atomically: `Effect.send` emits synchronously, so the
  /// store drains persist → teardown → clear (→ fill) in one send loop — no user action
  /// can interleave between the steps.
  private func teardownSlot(thenFill replacement: ChatFeature.State? = nil) -> Effect<Action> {
    var chain: [Effect<Action>] = [
      .send(.liveChat(.persistNow)),
      .send(.liveChat(.teardown)),
      .send(.clearLiveChat),
    ]
    if let replacement {
      chain.append(.send(.fillLiveChat(replacement)))
    }
    return .merge(
      .cancel(id: CancelID.backgroundGrace),
      .run { [backgroundTask] _ in await backgroundTask.end() },
      .concatenate(chain)
    )
  }

  /// Install all state owned by the connected shell in one place. Login, launch auto-connect,
  /// retry success, and a different-user reauth must land on an identical Home-first shell;
  /// partial dashboard failures then remain inside `HomeFeature` and cannot remove Chats.
  private func makeConnectedShell(_ state: inout State, connection: ServerConnection) {
    state.selectedDestination = .home
    state.dashboard = HomeFeature.State(connection: connection)
    state.home = makeHomeState(connection: connection)
    state.settings = nil
    state.automations = nil
    state.kanban = nil
  }

  /// Build the root Settings destination from the latest Chats capability state and persisted
  /// running-turn preferences. It is recreated on every selection so capabilities discovered
  /// since login (notably push-plugin support) never paint stale controls.
  private func makeSettingsState(
    chats: SessionListFeature.State,
    activeWorkflowProfileName: String?
  ) -> SettingsFeature.State {
    SettingsFeature.State(
      connection: chats.connection,
      pushAvailable: chats.pushAvailable,
      midTurnBehavior: preferences.loadMidTurnBehavior(),
      queueingEnabled: preferences.loadQueueingEnabled(),
      activeWorkflowProfileName: activeWorkflowProfileName
    )
  }

  /// The gateway scopes the default profile by omitting the profile name. Settings uses an
  /// explicit string key, so normalize the live chat before comparing it with a profile row.
  private static func activeWorkflowProfileName(_ chat: ChatFeature.State?) -> String? {
    guard let chat, chat.isRunning else { return nil }
    return chat.profileName ?? SessionListFeature.State.defaultProfileName
  }

  /// Deterministic, non-sensitive Home summaries for approval ids learned from push routing.
  /// Clarifications are intentionally absent: without their ephemeral gateway payload the app
  /// cannot safely reconstruct them, whereas ChatFeature already owns an approval fallback.
  private static func pendingApprovals(in state: State) -> [HomePendingInteraction] {
    state.pendingApprovalSessionIDs.sorted().map { sessionID in
      HomePendingInteraction(
        id: "approval:\(sessionID)",
        sessionID: sessionID,
        kind: .approval,
        title: state.home?.sessions[id: sessionID]?.resolvedTitle
      )
    }
  }

  /// Build a fresh session-list state, seeding the device-local persisted profile
  /// selection (normally reloaded later, in the list view's `.task`). Seeding at creation
  /// matters for work that runs BEFORE the list appears — the cold-launch push-tap replay
  /// (#46) opens a chat synchronously here, and an unseeded `scopedProfileName` would
  /// resume the session UNSCOPED (wrong `state.db` on a non-default profile →
  /// "session not found" → the self-heal recreates a spurious empty chat under
  /// "default"). A persisted non-default name implies the agent supported profiles when
  /// it was selected (prefs are wiped on logout, bounding staleness); the list's
  /// capability probe still corrects `profilesSupported` right after. A profile
  /// deleted/renamed server-side since selection is the accepted corner: the scoped
  /// resume fails exactly as a warm list-tap under the same stale pref would — parity
  /// with the warm path is the contract, and the rare stale-profile miss is a far
  /// smaller surface than the unscoped-resume misroute this seeding fixes (which hit
  /// EVERY cold-launch replay on a non-default profile).
  private func makeHomeState(connection: ServerConnection) -> SessionListFeature.State {
    let persisted = SessionListFeature.State.persistedProfileName(preferences)
    return SessionListFeature.State(
      connection: connection,
      selectedProfileName: persisted,
      profilesSupported: persisted != SessionListFeature.State.defaultProfileName
    )
  }

  /// Consume the cold-launch tap stash (#46): a tap dropped while `home` was nil is
  /// replayed through the normal `.pushTapped` routing the moment the list exists — slot
  /// compare, #32 dedup, and approval-hint arming all reuse the one code path (duplicating
  /// any of it here would drift). No stash → no effect. The replayed approval badge insert
  /// is idempotent (`Set` insert; the open then clears it, netting zero like a warm tap).
  ///
  /// Cross-server guard: a stash whose recorded origin differs from the server just
  /// connected to is DROPPED, not replayed — resuming a foreign session id would trip the
  /// "session not found" self-heal into creating a spurious empty chat. Dropping also
  /// scrubs EVERY pending-approval badge entry, not just the stashed tap's: the stash is
  /// last-wins, but every pre-home tap was stamped with the same origin (the persisted
  /// URL is constant across the pre-home window, and each identity teardown clears the
  /// set), so earlier badged approvals are equally foreign — they can never be viewed
  /// here (a foreign session never appears in this server's list, and opening is the
  /// only other clear path), and would otherwise stick for the process lifetime. An
  /// unknown origin (`nil` — no stored URL at stash time) replays unverified; see
  /// `pendingPushTapServerURL`.
  private func replayPendingPushTap(_ state: inout State) -> Effect<Action> {
    guard let tap = state.pendingPushTap else { return .none }
    let origin = state.pendingPushTapServerURL
    state.pendingPushTap = nil
    state.pendingPushTapServerURL = nil
    if let origin, let connected = state.home?.connection.baseURL,
       !Self.isSameServer(origin, connected) {
      guard !state.pendingApprovalSessionIDs.isEmpty else { return .none }
      state.pendingApprovalSessionIDs.removeAll()
      return setBadge(state)
    }
    return .send(.pushTapped(tap))
  }

  /// Server identity for the stash guard: scheme + host (both case-insensitive per
  /// RFC 3986, so lowercased) + literal port — path/trailing-slash/casing variations of
  /// the same server must not drop a legitimate replay. Default-port drift
  /// (`http://host` vs `http://host:80`) is accepted as a mismatch: both URLs come from
  /// the same persisted-string pipeline, so they only diverge across a genuine re-login.
  private static func isSameServer(_ a: URL, _ b: URL) -> Bool {
    a.scheme?.lowercased() == b.scheme?.lowercased()
      && a.host?.lowercased() == b.host?.lowercased()
      && a.port == b.port
  }

  /// Fill the live-chat slot and (re)set the navigation path to that chat's single marker.
  /// One slot ↔ one marker: the path never holds more than one chat screen, so replacing the
  /// contents (rather than appending) can't stack duplicates.
  private func fillLiveChat(_ incomingChat: ChatFeature.State, into state: inout State) {
    var chat = incomingChat
    chat.midTurnBehavior = preferences.loadMidTurnBehavior()
    chat.queueingEnabled = preferences.loadQueueingEnabled()
    // Every chat entry point (Chats row, Home quick action/card, push, branch, Settings
    // install prompt) converges here, so this is the one selection rule.
    state.selectedDestination = .chats
    state.settings = nil
    state.automations = nil
    state.kanban = nil
    state.liveChat = chat
    state.path.removeAll()
    state.path.append(ChatScreen.State(sessionKey: chat.sessionKey))
  }

  /// The prefilled-onboarding landing for a connection that needs *editing* rather than
  /// retrying: token mode prefills both fields so the user can fix them; cookie mode prefills
  /// only the URL (the password is never persisted), so they re-enter it. Shared by the launch
  /// auth-failure fallback and the retry screen's `.credentialsRejected` delegate, so
  /// onboarding is constructed in exactly one place.
  private func fallBackToOnboarding(_ state: inout State, connection: ServerConnection) {
    state.onboarding = ConnectionFeature.State(
      serverURL: connection.baseURL.absoluteString,
      token: connection.auth.token ?? ""
    )
  }

  /// Best-effort push cleanup on logout: unregister the last-known device token with the
  /// agent's push plugin (failures ignored — the server prunes dead tokens on a 410 anyway),
  /// then clear the persisted device token (prefs). Part of
  /// "logout clears everything". Uses the persisted token so it works even when the live
  /// `register()` stream isn't producing; a `nil` connection (nothing to talk to) still clears
  /// local push state.
  private func unregisterPushOnLogout(connection: ServerConnection?) -> Effect<AppFeature.Action> {
    let token = preferences.loadPushDeviceToken()
    preferences.clearPushDeviceToken()
    preferences.clearPushPromptSnooze() // device-local push prompt state — reset on logout
    guard let connection, let token else { return .none }
    return .run { [rest] _ in
      try? await rest.unregisterPush(connection, token)
    }
  }

  /// Push the app-icon badge to the current pending-approval count (the only side effect; the
  /// count itself lives in `state.pendingApprovalSessionIDs`, kept testable in the reducer).
  private func setBadge(_ state: State) -> Effect<AppFeature.Action> {
    let count = state.pendingApprovalSessionIDs.count
    return .run { [push] _ in await push.setBadgeCount(count) }
  }

  /// Seed a `ReauthFeature.State` from the connection of the expired chat: a fixed server
  /// URL, the matching auth regime, and (cookie mode) the prefilled username + provider used
  /// for the same-user vs user-switch decision.
  private func makeReauthState(for connection: ServerConnection) -> ReauthFeature.State {
    switch connection.auth {
    case .token:
      return ReauthFeature.State(serverURL: connection.baseURL, method: .token)
    case let .cookie(session):
      return ReauthFeature.State(
        serverURL: connection.baseURL,
        method: .password,
        provider: session.provider,
        previousUsername: session.username
      )
    }
  }
}
