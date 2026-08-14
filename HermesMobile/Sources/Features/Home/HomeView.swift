import ComposableArchitecture
import HermesKit
import SwiftUI

/// Operational landing page for a connected Hermes server.
///
/// Each card renders its own `HomeCardState`: one unavailable or failed module never replaces
/// successful siblings with a screen-level error. All behavior remains in `HomeFeature`; this
/// view only maps reducer state to native SwiftUI controls.
struct HomeView: View {
  let store: StoreOf<HomeFeature>
  let now: Date

  init(
    store: StoreOf<HomeFeature>,
    now: Date = Date()
  ) {
    self.store = store
    self.now = now
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HomeRefreshStatusView(
          lastSuccessfulRefreshAt: store.lastSuccessfulRefreshAt,
          now: now,
          isRefreshing: store.isRefreshing
        )

        quickActions

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)],
          alignment: .leading,
          spacing: 12
        ) {
          gatewayCard
          activeProcessesCard
          profileModelCard
          runningSessionsCard
          pendingInteractionsCard
          recentActivityCard
          cronAttentionCard
          kanbanStatusCard
          pushHealthCard
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Home")
    .refreshable {
      await store.send(.pulledToRefresh).finish()
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Refresh", systemImage: "arrow.clockwise") {
          store.send(.pulledToRefresh)
        }
        .disabled(store.isRefreshing)
      }
    }
    .task { store.send(.task) }
    .onDisappear { store.send(.onDisappear) }
  }

  private var quickActions: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Quick actions")
        .font(.title3.weight(.bold))
        .accessibilityAddTraits(.isHeader)

      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
        spacing: 10
      ) {
        HomeQuickActionButton(
          title: "New chat",
          subtitle: "Start a session",
          systemImage: "square.and.pencil",
          tint: .accentColor
        ) {
          store.send(.newChatTapped)
        }

        HomeQuickActionButton(
          title: "Active chat",
          subtitle: "Return to the running turn",
          systemImage: "arrow.turn.up.right",
          tint: .green,
          isEnabled: store.cards.runningSessions.value?.sessions.isEmpty == false
        ) {
          store.send(.returnToActiveChatTapped)
        }

        HomeQuickActionButton(
          title: "Board task",
          subtitle: "Create a Kanban task",
          systemImage: "rectangle.3.group",
          tint: .purple,
          isEnabled: store.cards.kanbanStatus.hasLoadedValue
            && !store.cards.kanbanStatus.isUnsupported
        ) {
          store.send(.createKanbanTaskTapped)
        }

        HomeQuickActionButton(
          title: "Schedule",
          subtitle: "Create an automation",
          systemImage: "calendar.badge.plus",
          tint: .orange,
          isEnabled: store.cards.cronAttention.hasLoadedValue
            && !store.cards.cronAttention.isUnsupported
        ) {
          store.send(.createScheduledJobTapped)
        }
      }
    }
  }

  private var gatewayCard: some View {
    HomeStatusCard("Gateway", systemImage: "network", tint: .green) {
      cardContent(
        store.cards.gatewayHealth,
        unsupportedMessage: "Gateway health isn't reported by this Hermes server."
      ) { health in
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            Circle()
              .fill(health.gatewayRunning ? Color.green : Color.red)
              .frame(width: 9, height: 9)
            Text(health.gatewayRunning ? "Online" : "Not running")
              .font(.title3.weight(.semibold))
          }
          HStack(spacing: 8) {
            if let version = health.version {
              HomeMetric(label: "Version", value: version)
            }
            if let count = health.activeSessionCount {
              HomeMetric(label: "Active sessions", value: "\(count)")
            }
          }
          if let state = health.gatewayState, !state.isEmpty {
            Label(state, systemImage: "info.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private var activeProcessesCard: some View {
    HomeStatusCard("Active processes", systemImage: "cpu", tint: .cyan) {
      cardContent(
        store.cards.activeProcesses,
        unsupportedMessage: "Active process reporting isn't available on this Hermes server."
      ) { processes in
        VStack(alignment: .leading, spacing: 10) {
          HomeMetric(
            label: processes.activeCount == 1 ? "process running" : "processes running",
            value: "\(processes.activeCount)",
            tint: processes.activeCount == 0 ? .secondary : .cyan
          )
          ForEach(Array(processes.processes.prefix(3)), id: \.id) { process in
            compactRow(
              title: process.title,
              detail: process.profileName ?? process.status,
              systemImage: "bolt.horizontal.circle"
            )
          }
        }
      }
    }
  }

  private var profileModelCard: some View {
    HomeStatusCard("Profile & model", systemImage: "person.crop.circle", tint: .blue) {
      cardContent(
        store.cards.profileModel,
        unsupportedMessage: "Profile details aren't exposed by this Hermes server."
      ) { profile in
        VStack(alignment: .leading, spacing: 6) {
          Text(profile.profileName)
            .font(.title3.weight(.semibold))
          if let model = profile.model, !model.isEmpty {
            Label(model, systemImage: "brain.head.profile")
              .font(.subheadline)
          } else {
            Text("Server default model")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          if let provider = profile.provider, !provider.isEmpty {
            Text(provider)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private var runningSessionsCard: some View {
    HomeStatusCard("Running sessions", systemImage: "bubble.left.and.bubble.right", tint: .green) {
      cardContent(
        store.cards.runningSessions,
        unsupportedMessage: "Running session summaries aren't available on this Hermes server."
      ) { sessions in
        VStack(alignment: .leading, spacing: 10) {
          HomeMetric(
            label: sessions.count == 1 ? "running session" : "running sessions",
            value: "\(sessions.count)",
            tint: sessions.count == 0 ? .secondary : .green
          )
          ForEach(Array(sessions.sessions.prefix(3)), id: \.id) { session in
            compactRow(
              title: session.title,
              detail: session.updatedAt.map(ageText),
              systemImage: "waveform"
            )
          }
        }
      }
    }
  }

  private var pendingInteractionsCard: some View {
    HomeStatusCard("Needs attention", systemImage: "exclamationmark.bubble", tint: .orange) {
      cardContent(
        store.cards.pendingInteractions,
        unsupportedMessage: "Pending approvals and questions aren't reported by this Hermes server."
      ) { pending in
        VStack(alignment: .leading, spacing: 10) {
          if pending.interactions.isEmpty {
            Label("Nothing waiting", systemImage: "checkmark.circle")
              .foregroundStyle(.secondary)
          } else {
            ForEach(Array(pending.interactions.prefix(3)), id: \.id) { interaction in
              Button {
                store.send(.pendingInteractionTapped(id: interaction.id))
              } label: {
                HStack(spacing: 10) {
                  Image(systemName: interaction.kind == .approval ? "checkmark.shield" : "questionmark.bubble")
                    .foregroundStyle(.orange)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(interaction.title ?? interactionKindTitle(interaction.kind))
                      .font(.subheadline.weight(.medium))
                      .foregroundStyle(.primary)
                      .lineLimit(2)
                    Text(interactionKindTitle(interaction.kind))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer(minLength: 4)
                  Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
  }

  private var recentActivityCard: some View {
    HomeStatusCard("Recent activity", systemImage: "clock.arrow.circlepath", tint: .indigo) {
      cardContent(
        store.cards.recentActivity,
        unsupportedMessage: "Recent outcomes aren't available on this Hermes server."
      ) { activity in
        VStack(alignment: .leading, spacing: 10) {
          if activity.items.isEmpty {
            Text("No recent activity")
              .foregroundStyle(.secondary)
          }
          ForEach(Array(activity.items.prefix(3)), id: \.id) { item in
            HStack(spacing: 10) {
              Image(systemName: item.outcome == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(item.outcome == .completed ? Color.green : Color.red)
              VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                  .font(.subheadline.weight(.medium))
                  .lineLimit(2)
                if let occurredAt = item.occurredAt {
                  Text(ageText(occurredAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
    }
  }

  private var cronAttentionCard: some View {
    HomeStatusCard("Automations", systemImage: "calendar", tint: .orange) {
      cardContent(
        store.cards.cronAttention,
        unsupportedMessage: "Automations aren't supported by this Hermes server."
      ) { attention in
        VStack(alignment: .leading, spacing: 10) {
          if attention.jobs.isEmpty {
            Label("No jobs need attention", systemImage: "checkmark.circle")
              .foregroundStyle(.secondary)
          }
          ForEach(Array(attention.jobs.prefix(3)), id: \.id) { job in
            compactRow(
              title: job.title,
              detail: cronReasonTitle(job.reason),
              systemImage: cronReasonSymbol(job.reason),
              tint: .orange
            )
          }
        }
      }
    }
  }

  private var kanbanStatusCard: some View {
    HomeStatusCard("Board", systemImage: "rectangle.3.group", tint: .purple) {
      cardContent(
        store.cards.kanbanStatus,
        unsupportedMessage: "Install and enable the native Kanban module to use Board."
      ) { kanban in
        HStack(alignment: .top, spacing: 8) {
          HomeMetric(label: "Running", value: "\(kanban.runningCount)", tint: .blue)
          HomeMetric(label: "Blocked", value: "\(kanban.blockedCount)", tint: .red)
          HomeMetric(label: "Review", value: "\(kanban.reviewCount)", tint: .purple)
        }
      }
    }
  }

  private var pushHealthCard: some View {
    HomeStatusCard("Notifications", systemImage: "bell.badge", tint: .pink) {
      cardContent(
        store.cards.pushHealth,
        unsupportedMessage: "The hermes-push module isn't available on this server."
      ) { health in
        VStack(alignment: .leading, spacing: 10) {
          Label(pushPluginTitle(health.pluginStatus), systemImage: pushPluginSymbol(health.pluginStatus))
            .font(.subheadline.weight(.medium))
          Text(pushAuthorizationTitle(health.authorizationStatus))
            .font(.caption)
            .foregroundStyle(.secondary)
          if health.canSendTestPing {
            Button("Send test ping", systemImage: "paperplane") {
              store.send(.sendTestPingTapped)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.testPingStatus == .sending)
          }
          switch store.testPingStatus {
          case .idle:
            EmptyView()
          case .sending:
            HStack(spacing: 8) {
              ProgressView()
                .controlSize(.small)
              Text("Sending test ping…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          case .sent:
            Label("Test ping sent", systemImage: "checkmark.circle.fill")
              .font(.caption)
              .foregroundStyle(.green)
          case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  /// Renders stale content when available, adding a local state footer. This is what keeps a
  /// transient failure isolated: useful data remains visible and only this card reports trouble.
  @ViewBuilder
  private func cardContent<Value: Equatable & Sendable, Content: View>(
    _ state: HomeCardState<Value>,
    unsupportedMessage: String,
    @ViewBuilder content: (Value) -> Content
  ) -> some View {
    switch state.phase {
    case .idle:
      HomeCardStatusView(status: .idle)
    case .loading:
      if let value = state.value {
        content(value)
        Divider()
        Label("Refreshing", systemImage: "arrow.clockwise")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        HomeCardStatusView(status: .loading)
      }
    case .loaded:
      if let value = state.value {
        content(value)
      } else {
        HomeCardStatusView(
          status: .failed("The server returned no data."),
          retry: refresh
        )
      }
    case let .failed(message):
      if let value = state.value {
        content(value)
        Divider()
        Label(message, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
        Button("Try again", action: refresh)
          .buttonStyle(.bordered)
          .controlSize(.small)
      } else {
        HomeCardStatusView(status: .failed(message), retry: refresh)
      }
    case .unsupported:
      HomeCardStatusView(status: .unsupported(unsupportedMessage))
    }
  }

  private func refresh() {
    store.send(.pulledToRefresh)
  }

  private func compactRow(
    title: String,
    detail: String?,
    systemImage: String,
    tint: Color = .secondary
  ) -> some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(tint)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline.weight(.medium))
          .lineLimit(2)
        if let detail, !detail.isEmpty {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
  }

  private func ageText(_ date: Date) -> String {
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "Just now" }
    if seconds < 3_600 { return "\(seconds / 60) min ago" }
    if seconds < 86_400 { return "\(seconds / 3_600) hr ago" }
    return "\(seconds / 86_400) d ago"
  }

  private func interactionKindTitle(_ kind: HomePendingInteraction.Kind) -> String {
    switch kind {
    case .approval: "Approval"
    case .clarification: "Question"
    }
  }

  private func cronReasonTitle(_ reason: HomeCronJobAttention.Reason) -> String {
    switch reason {
    case .failed: "Last run failed"
    case .paused: "Paused"
    case .overdue: "Overdue"
    }
  }

  private func cronReasonSymbol(_ reason: HomeCronJobAttention.Reason) -> String {
    switch reason {
    case .failed: "xmark.circle"
    case .paused: "pause.circle"
    case .overdue: "exclamationmark.circle"
    }
  }

  private func pushPluginTitle(_ status: PushPluginStatus) -> String {
    switch status {
    case .ready: "Push module ready"
    case .notReady: "Push module needs setup"
    case .unknown: "Push module status unknown"
    }
  }

  private func pushPluginSymbol(_ status: PushPluginStatus) -> String {
    switch status {
    case .ready: "checkmark.circle.fill"
    case .notReady: "exclamationmark.triangle.fill"
    case .unknown: "questionmark.circle"
    }
  }

  private func pushAuthorizationTitle(_ status: PushAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: "Notification permission hasn't been requested"
    case .denied: "Notifications are disabled in iOS Settings"
    case .authorized: "Notifications are allowed on this device"
    case .provisional: "Notifications are delivered quietly"
    }
  }
}
