import ComposableArchitecture
import DependenciesMacros
import Foundation

/// Device-local crash recovery for an in-progress profile edit.
///
/// Drafts are keyed by both server and profile. A profile named `work` on one Hermes host
/// must never be offered while editing the identically-named profile on another host.
/// The reducer owns the encoded draft schema; this client only persists opaque data so local
/// storage does not become coupled to the server's profile contract.
@DependencyClient
public struct ProfileDraftClient: Sendable {
  public var load: @Sendable (_ server: URL, _ profileName: String) -> Data?
  public var save: @Sendable (_ server: URL, _ profileName: String, _ data: Data) -> Void
  public var remove: @Sendable (_ server: URL, _ profileName: String) -> Void
  public var removeAll: @Sendable () -> Void
}

public extension ProfileDraftClient {
  static func live(defaults: UserDefaults = .standard) -> ProfileDraftClient {
    let storageKey = "hermes.profile-editor-drafts.v1"
    nonisolated(unsafe) let store = defaults

    @Sendable func key(_ server: URL, _ profileName: String) -> String {
      "\(server.absoluteString)|\(profileName)"
    }

    return ProfileDraftClient(
      load: { server, profileName in
        (store.dictionary(forKey: storageKey) as? [String: Data])?[key(server, profileName)]
      },
      save: { server, profileName, data in
        var drafts = (store.dictionary(forKey: storageKey) as? [String: Data]) ?? [:]
        drafts[key(server, profileName)] = data
        store.set(drafts, forKey: storageKey)
      },
      remove: { server, profileName in
        var drafts = (store.dictionary(forKey: storageKey) as? [String: Data]) ?? [:]
        drafts[key(server, profileName)] = nil
        if drafts.isEmpty {
          store.removeObject(forKey: storageKey)
        } else {
          store.set(drafts, forKey: storageKey)
        }
      },
      removeAll: {
        store.removeObject(forKey: storageKey)
      }
    )
  }

  /// Deterministic storage for previews and reducer tests.
  static func inMemory() -> ProfileDraftClient {
    let drafts = LockIsolated<[String: Data]>([:])
    @Sendable func key(_ server: URL, _ profileName: String) -> String {
      "\(server.absoluteString)|\(profileName)"
    }
    return ProfileDraftClient(
      load: { server, profileName in drafts.value[key(server, profileName)] },
      save: { server, profileName, data in
        drafts.withValue { $0[key(server, profileName)] = data }
      },
      remove: { server, profileName in
        drafts.withValue { $0[key(server, profileName)] = nil }
      },
      removeAll: { drafts.setValue([:]) }
    )
  }
}

extension ProfileDraftClient: DependencyKey {
  public static var liveValue: ProfileDraftClient { .live() }
  public static var testValue: ProfileDraftClient { .inMemory() }
}

public extension DependencyValues {
  var profileDraft: ProfileDraftClient {
    get { self[ProfileDraftClient.self] }
    set { self[ProfileDraftClient.self] = newValue }
  }
}
