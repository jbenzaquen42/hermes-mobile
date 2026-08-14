import ComposableArchitecture
import Foundation

/// The Add-profile form (presented as a sheet from the session list). Mirrors the
/// desktop's create-profile dialog: a name (validated against `ProfileName`), a
/// "clone from default" toggle, and an optional SOUL.md body.
///
/// Creating uses the native `profiles.create` RPC, including optional SOUL content in the
/// same typed request. On success it emits
/// `.delegate(.created(name:))` so the parent can refresh and select the new profile; on
/// failure it surfaces the safe profile-admin error message in an inline error banner.
@Reducer
public struct AddProfileFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    public var name: String
    public var cloneFromDefault: Bool
    public var soul: String
    public var isCreating: Bool
    public var errorBanner: String?
    /// `false` only after Hermes authoritatively rejects `profiles.create` as unsupported.
    public var createSupported: Bool?

    /// Inline name validation: `nil` while the field is empty (so the form starts clean),
    /// otherwise `ProfileName.hint` when the typed name fails the profile-name pattern.
    public var nameError: String? {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return ProfileName.isValid(trimmed) ? nil : ProfileName.hint
    }

    /// The Create button is enabled only for a non-empty, valid name that isn't already
    /// being created.
    public var canCreate: Bool {
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      return !trimmed.isEmpty && ProfileName.isValid(trimmed) && !isCreating
        && createSupported != false
    }

    public init(
      connection: ServerConnection,
      name: String = "",
      cloneFromDefault: Bool = true,
      soul: String = "",
      isCreating: Bool = false,
      errorBanner: String? = nil,
      createSupported: Bool? = nil
    ) {
      self.connection = connection
      self.name = name
      self.cloneFromDefault = cloneFromDefault
      self.soul = soul
      self.isCreating = isCreating
      self.errorBanner = errorBanner
      self.createSupported = createSupported
    }
  }

  public enum Action: BindableAction {
    case binding(BindingAction<State>)
    case createTapped
    /// Result of the native create request — the success payload is the new name.
    case createResponse(Result<String, CreateFailure>)
    case cancelTapped
    case delegate(Delegate)

    @CasePathable
    public enum Delegate {
      /// A profile was created — the parent refreshes the list and selects it.
      case created(name: String)
    }

    public struct CreateFailure: Error, Equatable, Sendable {
      public var message: String
      public var isUnsupported: Bool

      public init(message: String, isUnsupported: Bool = false) {
        self.message = message
        self.isUnsupported = isUnsupported
      }
    }
  }

  @Dependency(\.hermesProfileAdmin) var profileAdmin
  @Dependency(\.dismiss) var dismiss

  public init() {}

  public var body: some ReducerOf<Self> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .createTapped:
        guard state.canCreate else { return .none }
        state.isCreating = true
        state.errorBanner = nil
        let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let soul = state.soul.trimmingCharacters(in: .whitespacesAndNewlines)
        return .run { [profileAdmin, connection = state.connection, cloneFromDefault = state.cloneFromDefault] send in
          do {
            let result = try await profileAdmin.create(
              connection,
              ProfileCreateRequest(
                name: name,
                cloneFrom: cloneFromDefault ? SessionListFeature.State.defaultProfileName : nil,
                cloneAll: cloneFromDefault,
                soul: soul.isEmpty ? nil : soul
              )
            )
            guard result.ok, result.name == name else {
              await send(.createResponse(.failure(.init(
                message: "Hermes did not create the profile."
              ))))
              return
            }
            await send(.createResponse(.success(result.name)))
          } catch let error as ProfileAdminError {
            await send(.createResponse(.failure(.init(
              message: error.message,
              isUnsupported: error == .unsupported
            ))))
          } catch {
            await send(.createResponse(.failure(.init(message: "Couldn’t create the profile."))))
          }
        }

      case let .createResponse(.success(name)):
        state.isCreating = false
        state.createSupported = true
        return .send(.delegate(.created(name: name)))

      case let .createResponse(.failure(error)):
        state.isCreating = false
        if error.isUnsupported { state.createSupported = false }
        state.errorBanner = error.message
        return .none

      case .cancelTapped:
        return .run { [dismiss] _ in await dismiss() }

      case .delegate:
        return .none
      }
    }
  }
}
