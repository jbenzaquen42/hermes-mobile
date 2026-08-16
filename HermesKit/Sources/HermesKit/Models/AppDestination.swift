import Foundation

/// The connected app shell's five top-level destinations.
///
/// This is deliberately a HermesKit model rather than a SwiftUI `Tab` concern: reducers
/// can route Home quick actions and deep links through the same selection state the shell
/// renders, and unsupported modules can be capability-gated before they gain child reducers.
public enum AppDestination: String, CaseIterable, Equatable, Hashable, Sendable {
  case home
  case chats
  case board
  case automations
  case settings
}

/// Whether a shell destination is backed by a verified server capability.
///
/// Automations and Board are implemented as first-class tabs. Board availability is
/// initially off until a Kanban board is known to exist; the in-feature unsupported state
/// keeps the tab navigable even when the server lacks the plugin.
public enum AppDestinationAvailability: Equatable, Sendable {
  case available
  case unavailable(reason: String)

  public var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }

  public var unavailableReason: String? {
    guard case let .unavailable(reason) = self else { return nil }
    return reason
  }
}
