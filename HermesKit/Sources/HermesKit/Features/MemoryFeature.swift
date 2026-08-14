import ComposableArchitecture
import Foundation

/// Structured, entry-level management for Hermes' learning graph.
///
/// The native `learning.*` methods always resolve the server's default Hermes home and accept
/// no profile argument. This reducer therefore refuses every client operation for a custom
/// device-selected profile. Entry edits are local until one explicit Save, and every successful
/// mutation is followed by a server-authoritative list/detail reload.
@Reducer
public struct MemoryFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    public var profileName: String
    public var isServerDefaultProfile: Bool
    public var entries: [LearningEntrySummary]
    public var reportedCount: Int
    public var capacity: LearningCapacityInfo?
    public var metadata: LearningSnapshotMetadata
    public var selectedStore: StoreFilter
    public var searchQuery: String
    public var loadState: LoadState
    public var detailLoadState: LoadState
    public var mutationState: MutationState
    public var detailSupported: Bool?
    public var editSupported: Bool?
    public var deleteSupported: Bool?
    public var errorBanner: String?
    public var selectedEntryID: String?
    public var selectedDetail: LearningEntryDetail?
    public var editDraft: EditDraft?
    @Presents public var confirmationDialog: ConfirmationDialogState<Action.Dialog>?

    public init(
      connection: ServerConnection,
      profileName: String,
      isServerDefaultProfile: Bool,
      selectedStore: StoreFilter = .all
    ) {
      self.connection = connection
      self.profileName = profileName
      self.isServerDefaultProfile = isServerDefaultProfile
      entries = []
      reportedCount = 0
      capacity = nil
      metadata = LearningSnapshotMetadata()
      self.selectedStore = selectedStore
      searchQuery = ""
      loadState = .idle
      detailLoadState = .idle
      mutationState = .idle
      detailSupported = nil
      editSupported = nil
      deleteSupported = nil
      errorBanner = nil
      selectedEntryID = nil
      selectedDetail = nil
      editDraft = nil
      confirmationDialog = nil
    }

    public var scope: Scope {
      Scope(profileName: profileName, isServerDefaultProfile: isServerDefaultProfile)
    }

    public var filteredEntries: [LearningEntrySummary] {
      entries.filter { entry in
        selectedStore.includes(entry.kind)
          && (normalizedSearchQuery.isEmpty
            || entry.label.localizedCaseInsensitiveContains(normalizedSearchQuery))
      }
    }

    public var isEditDirty: Bool { editDraft?.isDirty == true }

    public var canSaveEdit: Bool {
      guard isServerDefaultProfile, loadState == .loaded, editSupported != false,
            let editDraft, editDraft.isDirty,
            !editDraft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            entries.contains(where: {
              $0.id == editDraft.id && $0.kind == editDraft.kind
            }) else { return false }
      switch mutationState {
      case .saving, .deleting: return false
      default: return true
      }
    }

    public var canDeleteOrArchive: Bool {
      guard isServerDefaultProfile, loadState == .loaded, deleteSupported != false,
            let detail = selectedDetail else { return false }
      guard entries.contains(where: { $0.id == detail.id && $0.kind == detail.kind }) else {
        return false
      }
      switch mutationState {
      case .saving, .deleting: return false
      default: return true
      }
    }

    public var sessionSnapshotExplanation: String {
      metadata.memoryRefreshPolicy.explanation
    }

    public var capacityReporting: LearningCapacityReporting {
      metadata.capacityReporting
    }

    var normalizedSearchQuery: String {
      searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  public static let customProfileMessage =
    "Structured memory is only available for the server’s default profile. "
    + "This Hermes server cannot scope learning operations to a custom profile."

  public enum StoreFilter: String, CaseIterable, Equatable, Hashable, Sendable {
    case all
    case userProfile
    case agentMemory
    case learnedSkill

    func includes(_ kind: LearningEntryKind) -> Bool {
      switch self {
      case .all: true
      case .userProfile: kind == .userProfile
      case .agentMemory: kind == .agentMemory
      case .learnedSkill: kind == .learnedSkill
      }
    }
  }

  public enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
    case unsupported(String)
  }

  public enum MutationState: Equatable, Sendable {
    case idle
    case saving
    case deleting
    case succeeded(MutationReport)
    /// The mutation was acknowledged, but one or more authoritative reloads failed.
    case partial(MutationReport)
    case failed(String)
    case unsupported(String)
  }

  public struct MutationReport: Equatable, Sendable {
    public var action: LearningMutationAction
    public var message: String
    public var reloadErrors: [String]

    public init(
      action: LearningMutationAction,
      message: String = "",
      reloadErrors: [String] = []
    ) {
      self.action = action
      self.message = message
      self.reloadErrors = reloadErrors
    }
  }

  public struct Scope: Equatable, Sendable {
    public var profileName: String
    public var isServerDefaultProfile: Bool

    public init(profileName: String, isServerDefaultProfile: Bool) {
      self.profileName = profileName
      self.isServerDefaultProfile = isServerDefaultProfile
    }
  }

  public struct EntryIdentity: Equatable, Sendable {
    public var profileName: String
    public var id: String
    public var kind: LearningEntryKind

    public init(profileName: String, id: String, kind: LearningEntryKind) {
      self.profileName = profileName
      self.id = id
      self.kind = kind
    }
  }

  public struct EditDraft: Equatable, Sendable, Identifiable {
    public var id: String
    public var profileName: String
    public var label: String
    public var kind: LearningEntryKind
    public var originalContent: String
    public var content: String

    public init(
      id: String,
      profileName: String,
      label: String,
      kind: LearningEntryKind,
      originalContent: String,
      content: String
    ) {
      self.id = id
      self.profileName = profileName
      self.label = label
      self.kind = kind
      self.originalContent = originalContent
      self.content = content
    }

    public var isDirty: Bool { content != originalContent }
  }

  public enum Action {
    case task
    case load
    case reloadTapped
    case loadResponse(Scope, LoadResponse)
    case storeFilterChanged(StoreFilter)
    case searchQueryChanged(String)
    case entryTapped(String)
    case detailResponse(EntryIdentity, DetailResponse)
    case detailDismissed
    case editContentChanged(String)
    case saveEditTapped
    case editResponse(EntryIdentity, submittedContent: String, MutationResponse)
    case deleteOrArchiveTapped
    case deleteResponse(EntryIdentity, MutationResponse)
    case closeTapped
    case confirmationDialog(PresentationAction<Dialog>)
    case delegate(Delegate)

    @CasePathable
    public enum Dialog: Equatable, Sendable {
      case discardAndClose
      case discardDetail
      case discardAndReload
      case confirmDeleteOrArchive(EntryIdentity)
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case closed
    }
  }

  @CasePathable
  public enum LoadResponse: Equatable, Sendable {
    case loaded(LearningSnapshot)
    case unsupported(String)
    case failed(String)
  }

  @CasePathable
  public enum DetailResponse: Equatable, Sendable {
    case loaded(LearningEntryDetail)
    case unsupported(String)
    case failed(String)
  }

  @CasePathable
  public enum MutationResponse: Equatable, Sendable {
    case applied(
      LearningMutationResult,
      snapshot: LearningSnapshot?,
      detail: LearningEntryDetail?,
      reloadErrors: [String]
    )
    case rejected(String)
    case unsupported(String)
    case failed(String)
  }

  private enum CancelID {
    case load
    case detail
  }

  @Dependency(\.hermesLearning) var learning

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return .send(.load)

      case .load:
        guard state.isServerDefaultProfile else {
          Self.clearDetail(in: &state)
          state.loadState = .unsupported(Self.customProfileMessage)
          state.errorBanner = nil
          return .merge(
            .cancel(id: CancelID.load),
            .cancel(id: CancelID.detail)
          )
        }
        guard state.loadState != .loading else { return .none }
        state.loadState = .loading
        state.errorBanner = nil
        let scope = state.scope
        return .run { [learning, connection = state.connection] send in
          do {
            await send(.loadResponse(scope, .loaded(try await learning.load(connection))))
          } catch let error as LearningClientError {
            await send(.loadResponse(
              scope,
              error == .unsupported ? .unsupported(error.message) : .failed(error.message)
            ))
          } catch {
            await send(.loadResponse(scope, .failed("Couldn’t load structured memory.")))
          }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)

      case .reloadTapped:
        guard state.isServerDefaultProfile else { return .send(.load) }
        guard !Self.isMutating(state.mutationState) else { return .none }
        if state.isEditDirty {
          state.confirmationDialog = ConfirmationDialogState {
            TextState("Discard this edit and reload?")
          } actions: {
            ButtonState(role: .destructive, action: .discardAndReload) {
              TextState("Discard and Reload")
            }
            ButtonState(role: .cancel) { TextState("Keep Editing") }
          } message: {
            TextState("Your entry edit is local until you save it.")
          }
          return .none
        }
        return .send(.load)

      case let .loadResponse(scope, .loaded(snapshot)):
        guard scope == state.scope, state.isServerDefaultProfile else { return .none }
        let selectedBeforeReload = Self.selectedIdentity(in: state)
        Self.apply(snapshot, to: &state)
        state.loadState = .loaded
        state.errorBanner = nil
        guard !state.isEditDirty,
              let identity = selectedBeforeReload,
              Self.contains(identity, in: state.entries) else {
          if let identity = selectedBeforeReload,
             !Self.contains(identity, in: state.entries) {
            Self.clearDetail(in: &state)
          }
          return .none
        }
        return requestDetail(identity, state: state)

      case let .loadResponse(scope, .unsupported(message)):
        guard scope == state.scope else { return .none }
        Self.clearDetail(in: &state)
        state.loadState = .unsupported(message)
        state.errorBanner = nil
        return .cancel(id: CancelID.detail)

      case let .loadResponse(scope, .failed(message)):
        guard scope == state.scope else { return .none }
        state.loadState = .failed(message)
        state.errorBanner = message
        return .none

      case let .storeFilterChanged(filter):
        state.selectedStore = filter
        return .none

      case let .searchQueryChanged(query):
        state.searchQuery = query
        return .none

      case let .entryTapped(id):
        guard state.isServerDefaultProfile, state.detailSupported != false,
              !Self.isMutating(state.mutationState),
              let entry = state.entries.first(where: { $0.id == id }) else { return .none }
        let identity = EntryIdentity(
          profileName: state.profileName, id: entry.id, kind: entry.kind
        )
        state.selectedEntryID = id
        state.selectedDetail = nil
        state.editDraft = nil
        state.detailLoadState = .loading
        state.mutationState = .idle
        state.errorBanner = nil
        return requestDetail(identity, state: state)

      case let .detailResponse(identity, .loaded(detail)):
        guard identity == Self.selectedIdentity(in: state),
              detail.id == identity.id,
              detail.kind == identity.kind,
              Self.contains(identity, in: state.entries) else { return .none }
        state.selectedDetail = detail
        state.detailSupported = true
        state.editDraft = EditDraft(
          id: detail.id,
          profileName: identity.profileName,
          label: detail.label,
          kind: detail.kind,
          originalContent: detail.content,
          content: detail.content
        )
        state.detailLoadState = .loaded
        state.errorBanner = nil
        return .none

      case let .detailResponse(identity, .unsupported(message)):
        guard identity == Self.selectedIdentity(in: state) else { return .none }
        state.detailLoadState = .unsupported(message)
        state.detailSupported = false
        state.errorBanner = message
        Self.clearDetail(in: &state, preservingLoadState: true)
        return .none

      case let .detailResponse(identity, .failed(message)):
        guard identity == Self.selectedIdentity(in: state) else { return .none }
        state.detailLoadState = .failed(message)
        state.errorBanner = message
        Self.clearDetail(in: &state, preservingLoadState: true)
        return .none

      case .detailDismissed:
        guard !Self.isMutating(state.mutationState) else { return .none }
        guard state.isEditDirty else {
          Self.clearDetail(in: &state)
          return .cancel(id: CancelID.detail)
        }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Discard this unsaved edit?")
        } actions: {
          ButtonState(role: .destructive, action: .discardDetail) {
            TextState("Discard Edit")
          }
          ButtonState(role: .cancel) { TextState("Keep Editing") }
        } message: {
          TextState("Your entry edit is local until you save it.")
        }
        return .none

      case let .editContentChanged(content):
        guard state.editDraft?.profileName == state.profileName else { return .none }
        state.editDraft?.content = content
        if !Self.isMutating(state.mutationState) { state.mutationState = .idle }
        return .none

      case .saveEditTapped:
        guard state.canSaveEdit, let draft = state.editDraft,
              let identity = Self.selectedIdentity(in: state),
              identity.id == draft.id,
              identity.kind == draft.kind else { return .none }
        state.mutationState = .saving
        state.errorBanner = nil
        let request = LearningEditRequest(id: draft.id, content: draft.content)
        return .run { [learning, connection = state.connection] send in
          do {
            let result = try await learning.edit(connection, request)
            guard result.succeeded else {
              await send(.editResponse(
                identity,
                submittedContent: request.content,
                .rejected(Self.nonEmpty(result.message) ?? "Hermes rejected this edit.")
              ))
              return
            }
            guard result.id == identity.id, result.action == .updated else {
              await send(.editResponse(
                identity,
                submittedContent: request.content,
                .failed("Hermes returned an unexpected edit result.")
              ))
              return
            }
            async let snapshotResult = Self.reloadSnapshot(learning, connection: connection)
            async let detailResult = Self.reloadDetail(
              learning, connection: connection, identity: identity
            )
            let (snapshotReload, detailReload) = await (snapshotResult, detailResult)
            var errors: [String] = []
            let snapshot: LearningSnapshot?
            switch snapshotReload {
            case let .success(value): snapshot = value
            case let .failure(message):
              snapshot = nil
              errors.append(message)
            }
            let detail: LearningEntryDetail?
            switch detailReload {
            case let .success(value): detail = value
            case let .failure(message):
              detail = nil
              errors.append(message)
            }
            await send(.editResponse(
              identity,
              submittedContent: request.content,
              .applied(result, snapshot: snapshot, detail: detail, reloadErrors: errors)
            ))
          } catch let error as LearningClientError {
            await send(.editResponse(
              identity,
              submittedContent: request.content,
              error == .unsupported ? .unsupported(error.message) : .failed(error.message)
            ))
          } catch {
            await send(.editResponse(
              identity,
              submittedContent: request.content,
              .failed("Couldn’t save this memory entry.")
            ))
          }
        }

      case let .editResponse(identity, submittedContent, .applied(
        result, snapshot, detail, reloadErrors
      )):
        guard identity == Self.selectedIdentity(in: state) else { return .none }
        guard result.succeeded, result.id == identity.id, result.action == .updated else {
          let message = "Hermes returned an unexpected edit result."
          state.mutationState = .failed(message)
          state.errorBanner = message
          return .none
        }
        state.editSupported = true
        var errors = reloadErrors
        if snapshot == nil, !errors.contains(where: { !$0.isEmpty }) {
          errors.append("The memory list could not be reloaded.")
        }
        if detail == nil, !errors.contains(where: { $0.contains("entry") }) {
          errors.append("The saved memory entry could not be reloaded.")
        }
        if let snapshot {
          Self.apply(snapshot, to: &state)
          state.loadState = .loaded
          if !Self.contains(identity, in: snapshot.entries) {
            errors.append("The edited entry was absent from the refreshed memory list.")
          }
        }
        if let detail, detail.id == identity.id, detail.kind == identity.kind,
           Self.contains(identity, in: state.entries) {
          state.selectedDetail = detail
          state.detailLoadState = .loaded
          if state.editDraft?.content == submittedContent {
            state.editDraft = EditDraft(
              id: detail.id,
              profileName: identity.profileName,
              label: detail.label,
              kind: detail.kind,
              originalContent: detail.content,
              content: detail.content
            )
          } else {
            state.editDraft?.label = detail.label
            state.editDraft?.originalContent = detail.content
          }
        } else if state.editDraft?.content != submittedContent,
                  Self.contains(identity, in: state.entries) {
          // Preserve text entered while Save was in flight. The acknowledged submission is
          // the new baseline, while the failed detail reload stays explicit in the report.
          state.selectedDetail?.content = submittedContent
          state.editDraft?.originalContent = submittedContent
        } else {
          Self.clearDetail(in: &state)
        }
        let report = MutationReport(
          action: result.action, message: result.message, reloadErrors: errors
        )
        state.mutationState = errors.isEmpty ? .succeeded(report) : .partial(report)
        state.errorBanner = errors.first
        return .none

      case let .editResponse(identity, _, .rejected(message)):
        guard identity == Self.selectedIdentity(in: state) else { return .none }
        state.editSupported = true
        state.mutationState = .failed(message)
        state.errorBanner = message
        return .none

      case let .editResponse(identity, _, .failed(message)):
        guard identity == Self.selectedIdentity(in: state) else { return .none }
        state.mutationState = .failed(message)
        state.errorBanner = message
        return .none

      case let .editResponse(identity, _, .unsupported(message)):
        guard identity == Self.selectedIdentity(in: state) else { return .none }
        state.editSupported = false
        state.mutationState = .unsupported(message)
        state.errorBanner = message
        return .none

      case .deleteOrArchiveTapped:
        guard state.canDeleteOrArchive, let identity = Self.selectedIdentity(in: state) else {
          return .none
        }
        let archives = identity.kind == .learnedSkill
        state.confirmationDialog = ConfirmationDialogState {
          TextState(archives ? "Archive this learned skill?" : "Delete this memory entry?")
        } actions: {
          ButtonState(role: .destructive, action: .confirmDeleteOrArchive(identity)) {
            TextState(archives ? "Archive" : "Delete")
          }
          ButtonState(role: .cancel) { TextState("Cancel") }
        } message: {
          TextState(
            archives
              ? "Hermes can restore archived learned skills later."
              : "This permanently removes the selected structured entry."
          )
        }
        return .none

      case let .deleteResponse(identity, response):
        return Self.reduceDeleteResponse(
          state: &state, identity: identity, response: response
        )

      case .closeTapped:
        guard !Self.isMutating(state.mutationState) else { return .none }
        guard state.isEditDirty else { return .send(.delegate(.closed)) }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Discard this edit and close?")
        } actions: {
          ButtonState(role: .destructive, action: .discardAndClose) {
            TextState("Discard and Close")
          }
          ButtonState(role: .cancel) { TextState("Keep Editing") }
        } message: {
          TextState("Your entry edit is local until you save it.")
        }
        return .none

      case .confirmationDialog(.presented(.discardAndClose)):
        return .send(.delegate(.closed))

      case .confirmationDialog(.presented(.discardDetail)):
        Self.clearDetail(in: &state)
        return .cancel(id: CancelID.detail)

      case .confirmationDialog(.presented(.discardAndReload)):
        Self.clearDetail(in: &state)
        return .send(.load)

      case let .confirmationDialog(.presented(.confirmDeleteOrArchive(identity))):
        guard identity == Self.selectedIdentity(in: state),
              Self.contains(identity, in: state.entries),
              state.isServerDefaultProfile,
              !Self.isMutating(state.mutationState) else { return .none }
        state.mutationState = .deleting
        state.errorBanner = nil
        let expectedAction: LearningMutationAction = identity.kind == .learnedSkill
          ? .archived : .deleted
        return .run { [learning, connection = state.connection] send in
          do {
            let result = try await learning.delete(connection, identity.id)
            guard result.succeeded else {
              await send(.deleteResponse(
                identity,
                .rejected(Self.nonEmpty(result.message) ?? "Hermes rejected this operation.")
              ))
              return
            }
            guard result.id == identity.id, result.action == expectedAction else {
              await send(.deleteResponse(
                identity, .failed("Hermes returned an unexpected deletion result.")
              ))
              return
            }
            switch await Self.reloadSnapshot(learning, connection: connection) {
            case let .success(snapshot):
              await send(.deleteResponse(
                identity,
                .applied(result, snapshot: snapshot, detail: nil, reloadErrors: [])
              ))
            case let .failure(message):
              await send(.deleteResponse(
                identity,
                .applied(result, snapshot: nil, detail: nil, reloadErrors: [message])
              ))
            }
          } catch let error as LearningClientError {
            await send(.deleteResponse(
              identity,
              error == .unsupported ? .unsupported(error.message) : .failed(error.message)
            ))
          } catch {
            await send(.deleteResponse(
              identity, .failed("Couldn’t remove this memory entry.")
            ))
          }
        }

      case .confirmationDialog, .delegate:
        return .none
      }
    }
    .ifLet(\.$confirmationDialog, action: \.confirmationDialog)
  }
}

private extension MemoryFeature {
  enum ReloadResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
  }

  func requestDetail(_ identity: EntryIdentity, state: State) -> Effect<Action> {
    guard state.isServerDefaultProfile, identity.profileName == state.profileName else {
      return .none
    }
    let connection = state.connection
    return .run { [learning] send in
      do {
        await send(.detailResponse(
          identity, .loaded(try await learning.detail(connection, identity.id))
        ))
      } catch let error as LearningClientError {
        await send(.detailResponse(
          identity,
          error == .unsupported ? .unsupported(error.message) : .failed(error.message)
        ))
      } catch {
        await send(.detailResponse(identity, .failed("Couldn’t load this memory entry.")))
      }
    }
    .cancellable(id: CancelID.detail, cancelInFlight: true)
  }

  static func reloadSnapshot(
    _ learning: HermesLearningClient,
    connection: ServerConnection
  ) async -> ReloadResult<LearningSnapshot> {
    do {
      return .success(try await learning.load(connection))
    } catch let error as LearningClientError {
      return .failure(error.message)
    } catch {
      return .failure("The memory list could not be reloaded.")
    }
  }

  static func reloadDetail(
    _ learning: HermesLearningClient,
    connection: ServerConnection,
    identity: EntryIdentity
  ) async -> ReloadResult<LearningEntryDetail> {
    do {
      let detail = try await learning.detail(connection, identity.id)
      guard detail.id == identity.id, detail.kind == identity.kind else {
        return .failure("Hermes returned a different entry while reloading.")
      }
      return .success(detail)
    } catch let error as LearningClientError {
      return .failure(error.message)
    } catch {
      return .failure("The saved memory entry could not be reloaded.")
    }
  }

  static func reduceDeleteResponse(
    state: inout State,
    identity: EntryIdentity,
    response: MutationResponse
  ) -> Effect<Action> {
    guard identity == selectedIdentity(in: state) else { return .none }

    switch response {
    case let .applied(result, snapshot, _, reloadErrors):
      let expectedAction: LearningMutationAction = identity.kind == .learnedSkill
        ? .archived : .deleted
      guard result.succeeded, result.id == identity.id, result.action == expectedAction else {
        let message = "Hermes returned an unexpected deletion result."
        state.mutationState = .failed(message)
        state.errorBanner = message
        return .none
      }
      state.deleteSupported = true
      clearDetail(in: &state)
      var errors = reloadErrors
      if snapshot == nil, !errors.contains(where: { !$0.isEmpty }) {
        errors.append("The memory list could not be reloaded.")
      }
      if let snapshot {
        apply(snapshot, to: &state)
        state.loadState = .loaded
        if contains(identity, in: snapshot.entries) {
          errors.append("Hermes still returned the removed entry after reloading.")
        }
      }
      let report = MutationReport(
        action: result.action, message: result.message, reloadErrors: errors
      )
      state.mutationState = errors.isEmpty ? .succeeded(report) : .partial(report)
      state.errorBanner = errors.first
      return .none

    case let .rejected(message):
      state.deleteSupported = true
      state.mutationState = .failed(message)
      state.errorBanner = message
      return .none

    case let .failed(message):
      state.mutationState = .failed(message)
      state.errorBanner = message
      return .none

    case let .unsupported(message):
      state.deleteSupported = false
      state.mutationState = .unsupported(message)
      state.errorBanner = message
      return .none
    }
  }

  static func apply(_ snapshot: LearningSnapshot, to state: inout State) {
    state.entries = snapshot.entries
    state.reportedCount = snapshot.reportedCount
    state.capacity = snapshot.capacity
    state.metadata = snapshot.metadata
  }

  static func selectedIdentity(in state: State) -> EntryIdentity? {
    guard let id = state.selectedEntryID,
          let entry = state.entries.first(where: { $0.id == id }) else { return nil }
    let kind: LearningEntryKind
    if let draft = state.editDraft, draft.id == id {
      kind = draft.kind
    } else if let detail = state.selectedDetail, detail.id == id {
      kind = detail.kind
    } else {
      kind = entry.kind
    }
    return EntryIdentity(profileName: state.profileName, id: entry.id, kind: kind)
  }

  static func contains(_ identity: EntryIdentity, in entries: [LearningEntrySummary]) -> Bool {
    entries.contains { $0.id == identity.id && $0.kind == identity.kind }
  }

  static func clearDetail(in state: inout State, preservingLoadState: Bool = false) {
    state.selectedEntryID = nil
    state.selectedDetail = nil
    state.editDraft = nil
    if !preservingLoadState { state.detailLoadState = .idle }
  }

  static func isMutating(_ state: MutationState) -> Bool {
    switch state {
    case .saving, .deleting: true
    default: false
    }
  }

  static func nonEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : value
  }
}
