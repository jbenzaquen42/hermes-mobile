import SnapshotTesting
import SwiftUI
import XCTest

@testable import HermesMobile

final class MemoryManagementSnapshotTests: SnapshotTestCase {
  func testMemoryList_loadedAllStores() {
    assertSnapshot(
      of: listView(
        presentation: listPresentation(entries: Self.entries),
        selectedStore: .all
      ),
      as: deviceImage()
    )
  }

  func testMemoryList_nearCapacity() {
    assertSnapshot(
      of: listView(
        presentation: listPresentation(
          entries: Self.entries.filter { $0.store == .agentMemory },
          capacities: [
            .init(
              title: "MEMORY",
              used: 15_200,
              limit: 16_000,
              entryCount: 28,
              unitLabel: "characters"
            )
          ]
        ),
        selectedStore: .agentMemory
      ),
      as: deviceImage()
    )
  }

  func testMemoryList_userSearchFilter() {
    assertSnapshot(
      of: listView(
        presentation: listPresentation(entries: [Self.entries[0]]),
        selectedStore: .userProfile,
        searchText: "release"
      ),
      as: deviceImage()
    )
  }

  func testMemoryList_staleError() {
    assertSnapshot(
      of: listView(
        presentation: listPresentation(
          loadState: .failed("The server disconnected while refreshing structured memory."),
          entries: Self.entries
        ),
        selectedStore: .all
      ),
      as: deviceImage()
    )
  }

  func testMemoryList_customProfileUnsupported() {
    let presentation = MemoryListPresentation(
      profileName: "ios-release",
      scopeLabel: "ios-release is a custom profile",
      loadState: .unsupported(
        "Hermes only exposes structured memory for the server's default profile. "
          + "No memory was read for ios-release."
      ),
      entries: [],
      totalCount: 0,
      capacities: [],
      capacityMessage: nil,
      mutationState: .idle,
      errorBanner: nil,
      sessionSnapshotExplanation: Self.snapshotExplanation
    )

    assertSnapshot(
      of: listView(presentation: presentation, selectedStore: .all),
      as: deviceImage()
    )
  }

  func testMemoryDetail_cleanEntry() {
    assertSnapshot(
      of: detailView(
        presentation: detailPresentation(entry: Self.entries[0])
      ),
      as: deviceImage()
    )
  }

  func testMemoryDetail_learnedSkillArchive() {
    assertSnapshot(
      of: detailView(
        presentation: detailPresentation(entry: Self.entries[2])
      ),
      as: deviceImage()
    )
  }

  func testMemoryDetail_dirtyEditFailure() {
    assertSnapshot(
      of: detailView(
        presentation: detailPresentation(
          entry: Self.entries[1],
          mutationState: .failed("The server rejected this edit. Your draft is still here."),
          isDirty: true
        ),
        draft: "Prefer small, reversible release steps with explicit verification."
      ),
      as: deviceImage()
    )
  }

  func testMemoryDetail_partialReload() {
    assertSnapshot(
      of: detailView(
        presentation: detailPresentation(
          entry: Self.entries[1],
          mutationState: .partial(
            "The entry was saved, but Hermes couldn't reload its authoritative detail."
          )
        )
      ),
      as: deviceImage()
    )
  }

  func testMemoryList_accessibilityDynamicType() {
    assertSnapshot(
      of: listView(
        presentation: listPresentation(entries: Self.entries),
        selectedStore: .all
      )
      .dynamicTypeSize(.accessibility2),
      as: deviceImage()
    )
  }

  func testMemoryDetail_accessibilityDynamicType() {
    assertSnapshot(
      of: detailView(
        presentation: detailPresentation(entry: Self.entries[0], isDirty: true),
        draft: "Prefers concise status, exact commands, and direct verification of results."
      )
      .dynamicTypeSize(.accessibility2),
      as: deviceImage()
    )
  }

  func testMemoryList_capacityNotReported() {
    assertSnapshot(
      of: listView(
        presentation: listPresentation(entries: Self.entries, capacities: []),
        selectedStore: .all
      ),
      as: deviceImage()
    )
  }

  private func listPresentation(
    loadState: MemoryLoadPresentation = .loaded,
    entries: [MemoryEntryPresentation],
    capacities: [MemoryCapacityPresentation] = [
      .init(
        title: "USER",
        used: 3_420,
        limit: 12_000,
        entryCount: 9,
        unitLabel: "characters"
      ),
      .init(
        title: "MEMORY",
        used: 8_750,
        limit: 16_000,
        entryCount: 28,
        unitLabel: "characters"
      ),
    ]
  ) -> MemoryListPresentation {
    MemoryListPresentation(
      profileName: "default",
      scopeLabel: "Server default profile · default",
      loadState: loadState,
      entries: entries,
      totalCount: Self.entries.count,
      capacities: capacities,
      capacityMessage: capacities.isEmpty
        ? "This server does not report live character usage or configured limits."
        : nil,
      mutationState: .idle,
      errorBanner: nil,
      sessionSnapshotExplanation: Self.snapshotExplanation
    )
  }

  private func listView(
    presentation: MemoryListPresentation,
    selectedStore: MemoryStorePresentation,
    searchText: String = ""
  ) -> some View {
    NavigationStack {
      MemoryManagementContent(
        presentation: presentation,
        bindings: MemoryListBindings(
          store: .constant(selectedStore),
          searchText: .constant(searchText)
        ),
        actions: MemoryListActions(
          onClose: {},
          onReload: {},
          onSelect: { _ in }
        )
      )
    }
  }

  private func detailPresentation(
    entry: MemoryEntryPresentation,
    mutationState: MemoryMutationPresentation = .idle,
    isDirty: Bool = false
  ) -> MemoryDetailPresentation {
    MemoryDetailPresentation(
      entry: entry,
      loadState: .loaded,
      mutationState: mutationState,
      isDirty: isDirty,
      canSave: isDirty,
      canDeleteOrArchive: true,
      errorBanner: nil,
      sessionSnapshotExplanation: Self.snapshotExplanation
    )
  }

  private func detailView(
    presentation: MemoryDetailPresentation,
    draft: String? = nil
  ) -> some View {
    NavigationStack {
      MemoryDetailContent(
        presentation: presentation,
        bindings: MemoryEditBindings(content: .constant(draft ?? presentation.entry.content)),
        actions: MemoryDetailActions(
          onClose: {},
          onReload: {},
          onSave: {},
          onDeleteOrArchive: {}
        )
      )
    }
  }

  private static let snapshotExplanation =
    "Changes persist immediately. A fresh session captures the latest memory snapshot; "
    + "the current session may keep the snapshot it started with."

  private static let entries = [
    MemoryEntryPresentation(
      id: "user-1",
      store: .userProfile,
      title: "Release communication preference",
      summary: "",
      content: "Prefers concise status with exact commands and direct verification.",
      category: "USER",
      tags: [],
      source: "Server default profile",
      createdLabel: nil,
      updatedLabel: nil,
      isArchived: false,
      operationLabel: "Delete entry",
      operationIsDestructive: true
    ),
    MemoryEntryPresentation(
      id: "memory-1",
      store: .agentMemory,
      title: "iOS release guardrail",
      summary: "",
      content: "Keep releases small, reversible, and observable.",
      category: "MEMORY",
      tags: [],
      source: "Server default profile",
      createdLabel: nil,
      updatedLabel: nil,
      isArchived: false,
      operationLabel: "Delete entry",
      operationIsDestructive: true
    ),
    MemoryEntryPresentation(
      id: "skill-1",
      store: .learnedSkill,
      title: "Swift snapshot review",
      summary: "",
      content: "Checks native layouts at standard and accessibility content sizes.",
      category: "SKILLS",
      tags: [],
      source: "Server default profile",
      createdLabel: nil,
      updatedLabel: nil,
      isArchived: false,
      operationLabel: "Archive learned skill",
      operationIsDestructive: false
    ),
  ]
}
