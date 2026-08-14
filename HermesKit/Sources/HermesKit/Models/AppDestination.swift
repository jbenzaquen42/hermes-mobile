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
/// Board and Automations intentionally start unavailable. Their tabs remain useful as
/// isolated roadmap placeholders, while the absence of a reducer/action surface guarantees
/// that selecting one cannot issue an unsupported RPC or disturb chat.
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
