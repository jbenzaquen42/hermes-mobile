import ComposableArchitecture
import HermesKit
import SwiftUI

/// Settings-owned profile list and native detail navigation.
///
/// `SettingsFeature` keeps the server-authoritative list and presentation children. This
/// adapter converts those typed values into snapshot-friendly presentation models only.
struct ProfileAdministrationView: View {
  @Bindable var store: StoreOf<SettingsFeature>

  var body: some View {
    ProfileAdministrationList(
      profiles: store.profiles.map { ProfileSummaryPresentation($0) },
      loadState: loadPresentation,
      onReload: { store.send(.loadProfiles) },
      onAdd: { store.send(.addProfileTapped) },
      onSelect: { selected in
        guard let profile = store.profiles[id: selected.id] else { return }
        store.send(.profileTapped(profile))
      },
      onManageCapabilities: { selected in
        guard let profile = store.profiles[id: selected.id] else { return }
        store.send(.manageCapabilitiesTapped(profile))
      },
      onManageMemory: { selected in
        guard let profile = store.profiles[id: selected.id] else { return }
        store.send(.manageMemoryTapped(profile))
      }
    )
    .navigationDestination(
      item: $store.scope(state: \.profileEditor, action: \.profileEditor)
    ) { editorStore in
      ProfileEditorView(store: editorStore)
    }
    .navigationDestination(
      item: $store.scope(state: \.capabilityManagement, action: \.capabilityManagement)
    ) { capabilityStore in
      CapabilityManagementView(store: capabilityStore)
    }
    .navigationDestination(
      item: $store.scope(state: \.memory, action: \.memory)
    ) { memoryStore in
      MemoryManagementView(store: memoryStore)
    }
    .sheet(item: $store.scope(state: \.addProfile, action: \.addProfile)) { addProfileStore in
      NavigationStack {
        AddProfileView(store: addProfileStore)
      }
    }
  }

  private var loadPresentation: ProfileAdministrationLoadPresentation {
    switch store.profileLoadState {
    case .idle, .loading:
      .loading
    case .loaded:
      .loaded
    case let .failed(message):
      .failed(message)
    case let .unsupported(message):
      .unsupported(message)
    }
  }
}

private extension ProfileSummaryPresentation {
  init(_ profile: ProfileAdminSummary) {
    self.init(
      name: profile.name,
      isDefault: profile.isDefault,
      description: profile.profileDescription,
      model: profile.model,
      provider: profile.provider,
      skillCount: profile.skillCount
    )
  }
}
