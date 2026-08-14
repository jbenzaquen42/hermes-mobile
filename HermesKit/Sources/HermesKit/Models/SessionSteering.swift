import Foundation

/// The acknowledgement for `session.steer`.
///
/// Hermes names the successful wire status `queued` because the guidance is queued for the
/// next tool boundary. At the client boundary that is an accepted steer, not a queued next
/// turn, so the typed result deliberately calls it `accepted`.
public enum SessionSteerResult: Equatable, Sendable {
  /// Hermes accepted the guidance for delivery inside the active turn.
  case accepted(text: String)
  /// The active runtime declined the guidance without failing the RPC.
  case rejected(text: String)
  /// The gateway or active runtime does not implement steering.
  case unsupported
}

/// The acknowledgement for `session.redirect`.
public enum SessionRedirectResult: Equatable, Sendable {
  /// Hermes redirected the active response while retaining valid work.
  case redirected(text: String)
  /// The correction landed during the agent-build window and was queued as the next turn.
  case queued(text: String)
  /// The active runtime declined the redirect without failing the RPC.
  case rejected(text: String)
  /// The gateway or active runtime does not implement active-turn redirects.
  case unsupported
}
