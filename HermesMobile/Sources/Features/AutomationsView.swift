import ComposableArchitecture
import HermesKit
import SwiftUI

/// Thin SwiftUI shell for the rich Automations tab. All polling, capability gating,
/// profile scoping, validation, and server-authoritative reloads live in
/// `AutomationsFeature`; this view only renders state and forwards user actions.
struct AutomationsView: View {
  @Bindable var store: StoreOf<AutomationsFeature>

  var body: some View {
    List {
      switch store.listLoadState {
      case .unsupported(let message):
        ContentUnavailableView {
          Label("Automations aren't available", systemImage: "calendar.badge.exclamationmark")
        } description: {
          Text(message)
        }
      case .failed(let message) where store.jobs.isEmpty:
        ContentUnavailableView {
          Label("Couldn't load automations", systemImage: "exclamationmark.triangle")
        } description: {
          Text(message)
        }
        .listRowBackground(Color.clear)
      default:
        jobsSection
      }
    }
    .navigationTitle("Automations")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          store.send(.createTapped)
        } label: {
          Label("New automation", systemImage: "plus")
        }
        .disabled(!store.canCreateOrEdit)
      }
      ToolbarItem(placement: .secondaryAction) {
        Button {
          store.send(.refreshTapped)
        } label: {
          Label("Refresh automations", systemImage: "arrow.clockwise")
        }
      }
    }
    .refreshable { store.send(.refreshTapped) }
    .task { store.send(.task) }
    .onDisappear { store.send(.onDisappear) }
    .confirmationDialog(
      $store.scope(state: \.confirmationDialog, action: \.confirmationDialog)
    )
    .navigationDestination(isPresented: detailIsPresented) {
      if let job = store.detail ?? store.selectedJob {
        AutomationDetailView(job: job, store: store)
      } else {
        ProgressView("Loading automation…")
      }
    }
    .sheet(isPresented: editorIsPresented) {
      AutomationEditorView(store: store)
    }
  }

  private var jobsSection: some View {
    Section {
      if store.jobs.isEmpty {
        if store.listLoadState == .loading {
          ProgressView("Loading automations…")
            .frame(maxWidth: .infinity)
        } else {
          ContentUnavailableView(
            "No automations",
            systemImage: "calendar",
            description: Text("Create a scheduled job to get started.")
          )
          .listRowBackground(Color.clear)
        }
      } else {
        ForEach(store.jobs) { job in
          Button {
            store.send(.jobTapped(job.id))
          } label: {
            AutomationRowView(job: job)
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button {
              store.send(.triggerTapped(job.id))
            } label: {
              Label("Run now", systemImage: "play.fill")
            }
            if job.isPaused {
              Button {
                store.send(.resumeTapped(job.id))
              } label: {
                Label("Resume", systemImage: "play.circle")
              }
            } else {
              Button {
                store.send(.pauseTapped(job.id))
              } label: {
                Label("Pause", systemImage: "pause.circle")
              }
            }
            if store.writeSupported != false {
              Button {
                store.send(.editTapped(job.id))
              } label: {
                Label("Edit", systemImage: "pencil")
              }
              Button(role: .destructive) {
                store.send(.deleteTapped(job.id))
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
          .disabled(store.actionInFlightIDs.contains(job.id))
        }
      }
    } header: {
      if let profile = store.profileName {
        Text("Profile · \(profile)")
      } else {
        Text("Server default profile")
      }
    } footer: {
      if let error = store.errorBanner {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
      } else if store.isRefreshing {
        Label("Refreshing…", systemImage: "arrow.clockwise")
      }
    }
  }

  private var detailIsPresented: Binding<Bool> {
    Binding(
      get: { store.selectedJobID != nil },
      set: { isPresented in
        if !isPresented { store.send(.detailDismissed) }
      }
    )
  }

  private var editorIsPresented: Binding<Bool> {
    Binding(
      get: { store.editor != nil },
      set: { isPresented in
        if !isPresented { store.send(.editorDismissed) }
      }
    )
  }
}

private struct AutomationRowView: View {
  let job: CronJob

  var body: some View {
    HStack(spacing: 12) {
      Circle()
        .fill(stateColor)
        .frame(width: 10, height: 10)
      VStack(alignment: .leading, spacing: 4) {
        Text(job.title)
          .font(.headline)
          .lineLimit(1)
        Text(job.scheduleText.isEmpty ? "Schedule unavailable" : job.scheduleText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let lastError = job.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastError.isEmpty {
          Label(lastError, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }
      Spacer()
      if job.isPaused {
        Text("Paused")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .padding(.vertical, 2)
  }

  private var stateColor: Color {
    switch job.effectiveState {
    case "running", "scheduled", "enabled": .green
    case "paused", "disabled": .orange
    case "error": .red
    default: .gray
    }
  }
}

private struct AutomationDetailView: View {
  let job: CronJob
  let store: StoreOf<AutomationsFeature>

  var body: some View {
    List {
      Section("Schedule") {
        LabeledContent("Name", value: job.title)
        if !job.scheduleText.isEmpty {
          LabeledContent("Schedule", value: job.scheduleText)
        }
        if let nextRunAt = job.nextRunAt {
          LabeledContent("Next run", value: nextRunAt.formatted(date: .abbreviated, time: .shortened))
        }
        if let lastRunAt = job.lastRunAt {
          LabeledContent("Last run", value: lastRunAt.formatted(date: .abbreviated, time: .shortened))
        }
        if let repeatLabel = job.repeatLabel {
          LabeledContent("Repeat", value: repeatLabel)
        }
      }

      Section("Configuration") {
        if let prompt = job.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
          Text(prompt)
        }
        if let deliver = job.deliver {
          LabeledContent("Delivery", value: deliver)
        }
        if let model = job.model, !model.isEmpty {
          LabeledContent("Model", value: model)
        }
        if let provider = job.provider, !provider.isEmpty {
          LabeledContent("Provider", value: provider)
        }
        if !job.skills.isEmpty {
          LabeledContent("Skills", value: job.skills.joined(separator: ", "))
        }
      }

      if let lastError = job.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
         !lastError.isEmpty {
        Section("Last error") {
          Label(lastError, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }

      Section("Recent runs") {
        switch store.runsLoadState {
        case .loading:
          ProgressView("Loading runs…")
        case let .failed(message):
          Label(message, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        case .loaded where store.runs.isEmpty:
          Text("No runs yet")
            .foregroundStyle(.secondary)
        default:
          ForEach(store.runs.prefix(20)) { run in
            Label {
              Text(run.title ?? run.id)
                .lineLimit(1)
            } icon: {
              Image(systemName: "terminal")
            }
          }
        }
      }

      Section {
        Button {
          store.send(.triggerTapped(job.id))
        } label: {
          Label("Run now", systemImage: "play.fill")
        }
        .disabled(store.actionInFlightIDs.contains(job.id))
        if job.isPaused {
          Button {
            store.send(.resumeTapped(job.id))
          } label: {
            Label("Resume", systemImage: "play.circle")
          }
          .disabled(store.actionInFlightIDs.contains(job.id))
        } else {
          Button {
            store.send(.pauseTapped(job.id))
          } label: {
            Label("Pause", systemImage: "pause.circle")
          }
          .disabled(store.actionInFlightIDs.contains(job.id))
        }
        if store.writeSupported != false {
          Button(role: .destructive) {
            store.send(.deleteTapped(job.id))
          } label: {
            Label("Delete automation", systemImage: "trash")
          }
          .disabled(store.actionInFlightIDs.contains(job.id))
        }
      }
    }
    .navigationTitle(job.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct AutomationEditorView: View {
  let store: StoreOf<AutomationsFeature>

  var body: some View {
    if store.editor != nil {
      editorContent
    }
  }

  private var editor: AutomationsFeature.EditorState {
    store.editor ?? .init(mode: .create)
  }

  private var editorContent: some View {
    NavigationStack {
      Form {
        Section("Basics") {
          TextField("Name", text: nameBinding)
          TextField("Schedule (cron)", text: scheduleBinding)
            .keyboardType(.numbersAndPunctuation)
          TextField("Prompt", text: promptBinding, axis: .vertical)
            .lineLimit(3...6)
          TextField("Skills (comma separated)", text: skillsBinding)
            .keyboardType(.numbersAndPunctuation)
        }

        Section("Delivery and model") {
          Picker("Delivery", selection: deliveryBinding) {
            if !store.deliveryTargets.contains(where: { $0.id == "local" }) {
              Text("Local").tag("local")
            }
            ForEach(store.deliveryTargets.filter { $0.id != "local" }, id: \.id) { target in
              Text(target.name).tag(target.id)
            }
          }
          TextField("Model override", text: modelBinding)
            .keyboardType(.URL)
          TextField("Provider override", text: providerBinding)
            .keyboardType(.URL)
        }

        if let message = editor.validationMessage {
          Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle(editor.editingJobID == nil ? "New automation" : "Edit automation")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { store.send(.editorDismissed) }
            .disabled(editor.isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { store.send(.saveEditorTapped) }
            .disabled(editor.isSaving)
        }
      }
      .interactiveDismissDisabled(editor.isSaving)
    }
  }

  private var nameBinding: Binding<String> {
    Binding(
      get: { editor.name },
      set: { store.send(.editorNameChanged($0)) }
    )
  }

  private var promptBinding: Binding<String> {
    Binding(
      get: { editor.prompt },
      set: { store.send(.editorPromptChanged($0)) }
    )
  }

  private var scheduleBinding: Binding<String> {
    Binding(
      get: { editor.schedule },
      set: { store.send(.editorScheduleChanged($0)) }
    )
  }

  private var deliveryBinding: Binding<String> {
    Binding(
      get: { editor.deliver },
      set: { store.send(.editorDeliverChanged($0)) }
    )
  }

  private var modelBinding: Binding<String> {
    Binding(
      get: { editor.model },
      set: { store.send(.editorModelChanged($0)) }
    )
  }

  private var providerBinding: Binding<String> {
    Binding(
      get: { editor.provider },
      set: { store.send(.editorProviderChanged($0)) }
    )
  }

  private var skillsBinding: Binding<String> {
    Binding(
      get: { editor.skillsText },
      set: { store.send(.editorSkillsChanged($0)) }
    )
  }
}
