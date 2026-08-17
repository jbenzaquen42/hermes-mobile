import ComposableArchitecture
import Foundation

/// Rich cron job administration.
///
/// This feature is intentionally independent from the Chats session list's compact Cron
/// Jobs section. It uses the same verified `GET /api/cron/jobs` contract, but adds
/// detail/history/upcoming, run-now/pause/resume, and create/edit/delete behind the
/// writable fields that the current Hermes REST API exposes. Readable jobs remain
/// available even when a write endpoint is absent or transiently fails.
@Reducer
public struct AutomationsFeature {
  @ObservableState
  public struct State: Equatable {
    public var connection: ServerConnection
    /// Scoped profile name; `nil` means the server default (omits `?profile=`).
    public var profileName: String?
    public var jobs: IdentifiedArrayOf<CronJob>
    public var deliveryTargets: [CronDeliveryTarget]
    public var listSupported: Bool?
    public var writeSupported: Bool?
    public var listLoadState: LoadState
    public var selectedJobID: String?
    public var detail: CronJob?
    public var runs: [Session]
    public var detailLoadState: LoadState
    public var runsLoadState: LoadState
    public var errorBanner: String?
    public var actionInFlightIDs: Set<String>
    public var editor: EditorState?
    public var isVisible: Bool
    public var isRefreshing: Bool
    @Presents public var confirmationDialog: ConfirmationDialogState<Action.Dialog>?

    public init(
      connection: ServerConnection,
      profileName: String?,
      jobs: IdentifiedArrayOf<CronJob> = [],
      deliveryTargets: [CronDeliveryTarget] = [],
      listSupported: Bool? = nil,
      writeSupported: Bool? = nil,
      listLoadState: LoadState = .idle,
      selectedJobID: String? = nil,
      detail: CronJob? = nil,
      runs: [Session] = [],
      detailLoadState: LoadState = .idle,
      runsLoadState: LoadState = .idle,
      errorBanner: String? = nil,
      actionInFlightIDs: Set<String> = [],
      editor: EditorState? = nil,
      isVisible: Bool = false,
      isRefreshing: Bool = false,
      confirmationDialog: ConfirmationDialogState<Action.Dialog>? = nil
    ) {
      self.connection = connection
      self.profileName = profileName
      self.jobs = jobs
      self.deliveryTargets = deliveryTargets
      self.listSupported = listSupported
      self.writeSupported = writeSupported
      self.listLoadState = listLoadState
      self.selectedJobID = selectedJobID
      self.detail = detail
      self.runs = runs
      self.detailLoadState = detailLoadState
      self.runsLoadState = runsLoadState
      self.errorBanner = errorBanner
      self.actionInFlightIDs = actionInFlightIDs
      self.editor = editor
      self.isVisible = isVisible
      self.isRefreshing = isRefreshing
      self.confirmationDialog = confirmationDialog
    }

    public var selectedJob: CronJob? {
      guard let selectedJobID else { return nil }
      return jobs[id: selectedJobID]
    }

    public var hasLoadedJobs: Bool {
      jobs.isEmpty == false || listLoadState == .loaded
    }

    public var canCreateOrEdit: Bool {
      guard listLoadState == .loaded, writeSupported != false else { return false }
      if editor?.isSaving == true { return false }
      return true
    }
  }

  public enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
    case unsupported(String)
  }

  public struct EditorState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
      case create
      case edit(CronJob)
    }

    public var mode: Mode
    public var name: String
    public var prompt: String
    public var schedule: String
    public var deliver: String
    public var model: String
    public var provider: String
    public var skillsText: String
    public var isSaving: Bool
    public var validationMessage: String?

    public init(mode: Mode, job: CronJob? = nil) {
      self.mode = mode
      name = job?.name ?? ""
      prompt = job?.prompt ?? ""
      schedule = job?.scheduleText ?? ""
      deliver = job?.deliver ?? "local"
      model = job?.model ?? ""
      provider = job?.provider ?? ""
      skillsText = (job?.skills ?? []).joined(separator: ", ")
      isSaving = false
      validationMessage = nil
    }

    public var editingJobID: String? {
      if case let .edit(job) = mode { return job.id }
      return nil
    }

    public var draft: CronJobDraft {
      CronJobDraft(
        name: name,
        prompt: prompt,
        schedule: schedule,
        deliver: deliver,
        model: model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : model,
        provider: provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? nil : provider,
        skills: skillsText
          .split(whereSeparator: { $0 == "," || $0 == "\n" })
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      )
    }

    public var validationError: String? {
      if draft.trimmedSchedule.isEmpty {
        return "Schedule is required."
      }
      if draft.trimmedPrompt.isEmpty && draft.trimmedSkills.isEmpty {
        return "Prompt is required (or add at least one skill)."
      }
      return nil
    }
  }

  public enum Action {
    case task
    case onDisappear
    case foreground
    case pollTick
    case refreshTapped
    case loadResponse(Result<[CronJob], RESTError>)
    case deliveryTargetsResponse(Result<[CronDeliveryTarget], RESTError>)
    case jobTapped(String)
    case detailResponse(Result<CronJob, RESTError>)
    case runsResponse(Result<[Session], RESTError>)
    case detailDismissed
    case createTapped
    case editTapped(String)
    case editorDismissed
    case editorNameChanged(String)
    case editorPromptChanged(String)
    case editorScheduleChanged(String)
    case editorDeliverChanged(String)
    case editorModelChanged(String)
    case editorProviderChanged(String)
    case editorSkillsChanged(String)
    case saveEditorTapped
    case saveEditorResponse(Result<Void, RESTError>)
    case triggerTapped(String)
    case pauseTapped(String)
    case resumeTapped(String)
    case jobActionFinished(id: String, error: RESTError?)
    case deleteTapped(String)
    case deleteResponse(id: String, error: RESTError?)
    case errorBannerDismissed
    case confirmationDialog(PresentationAction<Dialog>)
    case delegate(Delegate)

    @CasePathable
    public enum Dialog: Equatable, Sendable {
      case confirmDelete(String)
    }

    @CasePathable
    public enum Delegate: Equatable, Sendable {
      case openSession(Session.ID)
      case openCreatedJob(String)
    }
  }

  private enum CancelID: Hashable {
    case poll
    case load
    case detail
    case runs
  }

  @Dependency(\.hermesREST) var rest
  @Dependency(\.continuousClock) var clock

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        guard !state.isVisible else { return .none }
        state.isVisible = true
        state.listLoadState = .loading
        state.errorBanner = nil
        return .merge(
          refresh(&state),
          .run { [clock] send in
            while true {
              try await clock.sleep(for: .seconds(30))
              await send(.pollTick)
            }
          }
          .cancellable(id: CancelID.poll, cancelInFlight: true)
        )

      case .onDisappear:
        state.isVisible = false
        state.isRefreshing = false
        return .merge(
          .cancel(id: CancelID.poll),
          .cancel(id: CancelID.load),
          .cancel(id: CancelID.detail),
          .cancel(id: CancelID.runs)
        )

      case .foreground:
        guard state.isVisible else { return .none }
        return refresh(&state)

      case .pollTick:
        guard state.isVisible, !state.isRefreshing else { return .none }
        return refresh(&state)

      case .refreshTapped:
        return refresh(&state)

      case let .loadResponse(.success(jobs)):
        state.listSupported = true
        state.writeSupported = state.writeSupported ?? true
        state.jobs = IdentifiedArray(jobs, uniquingIDsWith: { first, _ in first })
        state.listLoadState = .loaded
        state.isRefreshing = false
        state.errorBanner = nil
        if let selectedJobID = state.selectedJobID, state.jobs[id: selectedJobID] == nil {
          state.selectedJobID = nil
          state.detail = nil
          state.runs = []
          state.detailLoadState = .idle
          state.runsLoadState = .idle
        }
        return .none

      case let .loadResponse(.failure(error)):
        state.isRefreshing = false
        if error == .notFound {
          state.listSupported = false
          state.writeSupported = false
          state.jobs = []
          state.selectedJobID = nil
          state.detail = nil
          state.runs = []
          state.listLoadState = .unsupported("Automations are not available on this server.")
          state.errorBanner = nil
        } else if state.jobs.isEmpty {
          state.listLoadState = .failed(error.message)
          state.errorBanner = error.message
        } else {
          // Transient failure: keep the previous authoritative list and surface the error.
          state.errorBanner = error.message
        }
        return .none

      case let .deliveryTargetsResponse(.success(targets)):
        state.deliveryTargets = targets
        return .none

      case .deliveryTargetsResponse(.failure):
        // Delivery targets are a convenience for the editor; a failure must not make
        // readable cron data disappear or turn a transient outage into "unsupported".
        state.deliveryTargets = []
        return .none

      case let .jobTapped(id):
        guard state.jobs[id: id] != nil else { return .none }
        state.selectedJobID = id
        state.detail = nil
        state.runs = []
        state.detailLoadState = .loading
        state.runsLoadState = .loading
        state.errorBanner = nil
        return .merge(
          loadDetail(id, state: state),
          loadRuns(id, state: state)
        )

      case let .detailResponse(.success(job)):
        guard state.selectedJobID == job.id else { return .none }
        state.detail = job
        state.detailLoadState = .loaded
        // The detail may carry a newer state than the list row; update the list row too.
        state.jobs[id: job.id] = job
        return .none

      case let .detailResponse(.failure(error)):
        guard state.selectedJobID != nil else { return .none }
        state.detailLoadState = .failed(error.message)
        state.errorBanner = error.message
        return .none

      case let .runsResponse(.success(runs)):
        guard state.selectedJobID != nil else { return .none }
        state.runs = runs
        state.runsLoadState = .loaded
        return .none

      case let .runsResponse(.failure(error)):
        guard state.selectedJobID != nil else { return .none }
        state.runsLoadState = .failed(error.message)
        state.errorBanner = error.message
        return .none

      case .detailDismissed:
        guard state.editor?.isSaving != true else { return .none }
        state.selectedJobID = nil
        state.detail = nil
        state.runs = []
        state.detailLoadState = .idle
        state.runsLoadState = .idle
        return .merge(.cancel(id: CancelID.detail), .cancel(id: CancelID.runs))

      case .createTapped:
        guard state.canCreateOrEdit else { return .none }
        state.editor = EditorState(mode: .create)
        return .none

      case let .editTapped(id):
        guard state.canCreateOrEdit, let job = state.jobs[id: id] else { return .none }
        state.editor = EditorState(mode: .edit(job), job: job)
        return .none

      case .editorDismissed:
        guard state.editor?.isSaving != true else { return .none }
        state.editor = nil
        return .none

      case let .editorNameChanged(value):
        state.editor?.name = value
        state.editor?.validationMessage = nil
        return .none

      case let .editorPromptChanged(value):
        state.editor?.prompt = value
        state.editor?.validationMessage = nil
        return .none

      case let .editorScheduleChanged(value):
        state.editor?.schedule = value
        state.editor?.validationMessage = nil
        return .none

      case let .editorDeliverChanged(value):
        state.editor?.deliver = value
        return .none

      case let .editorModelChanged(value):
        state.editor?.model = value
        return .none

      case let .editorProviderChanged(value):
        state.editor?.provider = value
        return .none

      case let .editorSkillsChanged(value):
        state.editor?.skillsText = value
        state.editor?.validationMessage = nil
        return .none

      case .saveEditorTapped:
        guard let editor = state.editor, !editor.isSaving else { return .none }
        if let validationError = editor.validationError {
          state.editor?.validationMessage = validationError
          return .none
        }
        state.editor?.isSaving = true
        state.editor?.validationMessage = nil
        let draft = editor.draft
        let connection = state.connection
        let profileName = state.profileName
        let editingID = editor.editingJobID
        return .run { [rest] send in
          do {
            if let editingID {
              try await rest.updateCronJob(connection, editingID, draft, profileName)
            } else {
              try await rest.createCronJob(connection, draft, profileName)
            }
            await send(.saveEditorResponse(.success(())))
          } catch {
            await send(.saveEditorResponse(.failure(asRESTError(error))))
          }
        }

      case let .saveEditorResponse(.success):
        let selectedJobID = state.selectedJobID
        state.editor = nil
        state.errorBanner = nil
        if let selectedJobID, state.jobs[id: selectedJobID] != nil {
          state.detailLoadState = .loading
          state.runsLoadState = .loading
          return .merge(
            refresh(&state),
            loadDetail(selectedJobID, state: state),
            loadRuns(selectedJobID, state: state)
          )
        }
        return refresh(&state)

      case let .saveEditorResponse(.failure(error)):
        state.editor?.isSaving = false
        state.editor?.validationMessage = error.message
        if error == .notFound {
          state.writeSupported = false
        }
        return .none

      case let .triggerTapped(id):
        guard state.jobs[id: id] != nil, !state.actionInFlightIDs.contains(id) else { return .none }
        state.actionInFlightIDs.insert(id)
        return runJobAction(id, action: "trigger", state: state)

      case let .pauseTapped(id):
        guard state.jobs[id: id] != nil, !state.actionInFlightIDs.contains(id) else { return .none }
        state.actionInFlightIDs.insert(id)
        return runJobAction(id, action: "pause", state: state)

      case let .resumeTapped(id):
        guard state.jobs[id: id] != nil, !state.actionInFlightIDs.contains(id) else { return .none }
        state.actionInFlightIDs.insert(id)
        return runJobAction(id, action: "resume", state: state)

      case let .jobActionFinished(id, error):
        state.actionInFlightIDs.remove(id)
        if let error {
          state.errorBanner = error.message
          return .none
        }
        if state.selectedJobID == id {
          state.detailLoadState = .loading
          state.runsLoadState = .loading
          return .merge(
            refresh(&state),
            loadDetail(id, state: state),
            loadRuns(id, state: state)
          )
        }
        return refresh(&state)

      case let .deleteTapped(id):
        guard state.writeSupported != false,
              state.jobs[id: id] != nil,
              !state.actionInFlightIDs.contains(id) else { return .none }
        state.confirmationDialog = ConfirmationDialogState {
          TextState("Delete automation?")
        } actions: {
          ButtonState(role: .destructive, action: .confirmDelete(id)) {
            TextState("Delete")
          }
          ButtonState(role: .cancel) {
            TextState("Cancel")
          }
        } message: {
          TextState("This permanently deletes the job and its schedule on the server.")
        }
        return .none

      case let .confirmationDialog(.presented(.confirmDelete(id))):
        state.confirmationDialog = nil
        guard state.jobs[id: id] != nil, !state.actionInFlightIDs.contains(id) else { return .none }
        state.actionInFlightIDs.insert(id)
        let connection = state.connection
        let profileName = state.profileName
        return .run { [rest] send in
          do {
            try await rest.deleteCronJob(connection, id, profileName)
            await send(.deleteResponse(id: id, error: nil))
          } catch {
            await send(.deleteResponse(id: id, error: asRESTError(error)))
          }
        }

      case let .deleteResponse(id, error):
        state.actionInFlightIDs.remove(id)
        if let error {
          state.errorBanner = error.message
          return .none
        }
        if state.selectedJobID == id {
          state.selectedJobID = nil
          state.detail = nil
          state.runs = []
          state.detailLoadState = .idle
          state.runsLoadState = .idle
        }
        return refresh(&state)

      case .errorBannerDismissed:
        state.errorBanner = nil
        return .none

      case .confirmationDialog:
        return .none

      case .delegate:
        return .none
      }
    }
  }

  private func refresh(_ state: inout State) -> Effect<Action> {
    state.isRefreshing = true
    state.listLoadState = state.jobs.isEmpty ? .loading : state.listLoadState
    state.errorBanner = nil
    let connection = state.connection
    let profileName = state.profileName
    return .merge(
      .run { [rest] send in
        do {
          let jobs = try await rest.cronJobs(connection, profileName)
          await send(.loadResponse(.success(jobs)))
        } catch {
          await send(.loadResponse(.failure(asRESTError(error))))
        }
      }
      .cancellable(id: CancelID.load, cancelInFlight: true),
      .run { [rest] send in
        do {
          let targets = try await rest.cronDeliveryTargets(connection)
          await send(.deliveryTargetsResponse(.success(targets)))
        } catch {
          await send(.deliveryTargetsResponse(.failure(asRESTError(error))))
        }
      }
    )
  }

  private func runJobAction(_ id: String, action: String, state: State) -> Effect<Action> {
    let connection = state.connection
    let profileName = state.profileName
    return .run { [rest] send in
      do {
        switch action {
        case "trigger": try await rest.triggerCronJob(connection, id, profileName)
        case "pause": try await rest.pauseCronJob(connection, id, profileName)
        default: try await rest.resumeCronJob(connection, id, profileName)
        }
        await send(.jobActionFinished(id: id, error: nil))
      } catch {
        await send(.jobActionFinished(id: id, error: asRESTError(error)))
      }
    }
  }

  private func loadDetail(_ id: String, state: State) -> Effect<Action> {
    let connection = state.connection
    let profileName = state.profileName
    return .run { [rest] send in
      do {
        let job = try await rest.cronJobDetail(connection, id, profileName)
        await send(.detailResponse(.success(job)))
      } catch {
        await send(.detailResponse(.failure(asRESTError(error))))
      }
    }
    .cancellable(id: CancelID.detail, cancelInFlight: true)
  }

  private func loadRuns(_ id: String, state: State) -> Effect<Action> {
    let connection = state.connection
    let profileName = state.profileName
    return .run { [rest] send in
      do {
        let runs = try await rest.cronJobRuns(connection, id, profileName, 20)
        await send(.runsResponse(.success(runs)))
      } catch {
        await send(.runsResponse(.failure(asRESTError(error))))
      }
    }
    .cancellable(id: CancelID.runs, cancelInFlight: true)
  }
}
