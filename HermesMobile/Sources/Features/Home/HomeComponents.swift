import SwiftUI

/// Shared visual shell for Home's independently loaded status cards.
///
/// The reducer owns whether a card is loading, stale, failed, or unsupported. This view
/// deliberately owns only presentation so one card can change phase without changing the
/// layout or interaction of any sibling card.
struct HomeStatusCard<Content: View>: View {
  let title: String
  let systemImage: String
  let tint: Color
  let content: Content

  init(
    _ title: String,
    systemImage: String,
    tint: Color = .accentColor,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.tint = tint
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label {
        Text(title)
          .font(.headline)
          .foregroundStyle(.primary)
      } icon: {
        Image(systemName: systemImage)
          .foregroundStyle(tint)
      }
      .accessibilityAddTraits(.isHeader)

      content
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(
      Color(.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }
}

/// Consistent non-content states used inside each independent Home card.
struct HomeCardStatusView: View {
  enum Status: Equatable {
    case idle
    case loading
    case failed(String)
    case unsupported(String)
  }

  let status: Status
  var retry: (() -> Void)?

  var body: some View {
    switch status {
    case .idle:
      Label("Waiting to refresh", systemImage: "clock")
        .foregroundStyle(.secondary)
    case .loading:
      Label("Loading…", systemImage: "arrow.clockwise")
        .foregroundStyle(.secondary)
    case let .failed(message):
      VStack(alignment: .leading, spacing: 10) {
        Label("Couldn't load", systemImage: "exclamationmark.triangle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.orange)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if let retry {
          Button("Try again", action: retry)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
      }
    case let .unsupported(message):
      VStack(alignment: .leading, spacing: 6) {
        Label("Not available", systemImage: "nosign")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// One tappable tile in Home's compact operational-actions grid.
struct HomeQuickActionButton: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let tint: Color
  var isEnabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: systemImage)
          .font(.title3.weight(.semibold))
          .foregroundStyle(isEnabled ? tint : Color.secondary)
          .frame(width: 34, height: 34)
          .background(
            (isEnabled ? tint : Color.secondary).opacity(0.14),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
          )

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text(isEnabled ? subtitle : "Unavailable")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
      .background(
        Color(.secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Color.primary.opacity(0.07), lineWidth: 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.68)
  }
}

/// Honest landing page for a top-level module whose server contract is unavailable.
/// Keeping the tab selectable explains the capability boundary without issuing a fallback RPC.
struct UnsupportedDestinationView: View {
  let title: String
  let systemImage: String
  let reason: String

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(reason)
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// Small, deterministic freshness label. `now` is injectable so snapshot tests do not depend
/// on wall-clock time while the live view still reads naturally ("just now", "12 min ago").
struct HomeRefreshStatusView: View {
  let lastSuccessfulRefreshAt: Date?
  let now: Date
  let isRefreshing: Bool

  var body: some View {
    HStack(spacing: 7) {
      if isRefreshing {
        ProgressView()
          .controlSize(.small)
      } else {
        Image(systemName: lastSuccessfulRefreshAt == nil ? "clock" : "checkmark.circle.fill")
          .foregroundStyle(lastSuccessfulRefreshAt == nil ? Color.secondary : Color.green)
      }
      Text(statusText)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  private var statusText: String {
    if isRefreshing { return "Refreshing" }
    guard let date = lastSuccessfulRefreshAt else { return "Not refreshed yet" }
    let elapsed = max(0, Int(now.timeIntervalSince(date)))
    if elapsed < 60 { return "Updated just now" }
    let minutes = elapsed / 60
    if minutes < 60 { return "Updated \(minutes) min ago" }
    let hours = minutes / 60
    if hours < 24 { return "Updated \(hours) hr ago" }
    return "Updated \(hours / 24) d ago"
  }
}

/// Compact label/value primitive for dense card content.
struct HomeMetric: View {
  let label: String
  let value: String
  var tint: Color = .primary

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.title3.weight(.semibold))
        .foregroundStyle(tint)
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
