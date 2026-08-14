import SnapshotTesting
import SwiftUI
import XCTest

@testable import HermesMobile

final class ProfileAdministrationSnapshotTests: SnapshotTestCase {
  private let profiles = [
    ProfileSummaryPresentation(
      name: "default",
      isDefault: true,
      description: "General-purpose Hermes profile",
      model: "claude-sonnet-4-6",
      provider: "anthropic",
      skillCount: 12
    ),
    ProfileSummaryPresentation(
      name: "ios-release",
      isDefault: false,
      description: "Ships Hermes Control and watches TestFlight feedback.",
      model: "gpt-5.6-codex",
      provider: "openai",
      skillCount: 7
    ),
    ProfileSummaryPresentation(
      name: "research",
      isDefault: false,
      description: "Source-first research with a conservative tool policy.",
      model: nil,
      provider: nil,
      skillCount: 4
    ),
  ]

  func testProfileList_loaded() {
    let view = NavigationStack {
      ProfileAdministrationList(
        profiles: profiles,
        loadState: .loaded,
        onReload: {},
        onAdd: {},
        onSelect: { _ in },
        onManageCapabilities: { _ in }
      )
    }

    assertSnapshot(of: view, as: deviceImage())
  }

  func testProfileList_staleError() {
    let view = NavigationStack {
      ProfileAdministrationList(
        profiles: profiles,
        loadState: .failed("The server disconnected while refreshing."),
        onReload: {},
        onAdd: {},
        onSelect: { _ in },
        onManageCapabilities: { _ in }
      )
    }

    assertSnapshot(of: view, as: deviceImage())
  }

  func testProfileEditor_dirtySoulEdit() {
    assertSnapshot(
      of: editorView(
        presentation: editorPresentation(isDirty: true),
        mode: .edit,
        soul: Self.soulMarkdown
      ),
      as: deviceImage()
    )
  }

  func testProfileEditor_soulPreview() {
    assertSnapshot(
      of: editorView(
        presentation: editorPresentation(isDirty: true),
        mode: .preview,
        soul: Self.soulMarkdown
      ),
      as: deviceImage()
    )
  }

  func testProfileEditor_partialSave() {
    assertSnapshot(
      of: editorView(
        presentation: editorPresentation(
          isDirty: true,
          saveState: .partial(
            saved: ["Model", "Skills"],
            failed: ["SOUL.md", "MCP servers"]
          )
        ),
        mode: .edit,
        soul: Self.soulMarkdown
      ),
      as: deviceImage()
    )
  }

  /// The form must wrap its status actions and field labels instead of clipping them at an
  /// accessibility content size. A whole-device snapshot pins both axes of this scroll view.
  func testProfileEditor_accessibilityDynamicType() {
    assertSnapshot(
      of: editorView(
        presentation: editorPresentation(
          isDirty: true,
          recoveredDraft: ProfileRecoveredDraftPresentation(
            message: "A local draft from 12 minutes ago differs from the server version."
          )
        ),
        mode: .edit,
        soul: Self.soulMarkdown
      )
      .dynamicTypeSize(.accessibility2),
      as: deviceImage()
    )
  }

  private func editorPresentation(
    isDirty: Bool,
    saveState: ProfileEditorSavePresentation = .idle,
    recoveredDraft: ProfileRecoveredDraftPresentation? = nil
  ) -> ProfileEditorPresentation {
    ProfileEditorPresentation(
      profileName: "ios-release",
      isDefault: false,
      loadState: .loaded,
      isDirty: isDirty,
      canSave: isDirty,
      canRename: false,
      isRenaming: false,
      isDeleting: false,
      nameError: nil,
      characterCount: Self.soulMarkdown.count,
      estimatedTokenCount: 73,
      errorBanner: nil,
      saveState: saveState,
      recoveredDraft: recoveredDraft,
      capabilities: [
        ProfileCapabilitySummaryPresentation(
          kind: .skill,
          title: "Skills",
          systemImage: "sparkles",
          options: [
            .init(name: "github", detail: nil, isEnabled: true),
            .init(name: "openai-docs", detail: nil, isEnabled: true),
            .init(name: "swift-testing", detail: nil, isEnabled: true),
            .init(name: "browser", detail: nil, isEnabled: false),
          ]
        ),
        ProfileCapabilitySummaryPresentation(
          kind: .toolset,
          title: "Toolsets",
          systemImage: "wrench.and.screwdriver",
          options: [
            .init(name: "coding", detail: "12 tools", isEnabled: true),
            .init(name: "web", detail: "Search and page reading", isEnabled: true),
            .init(name: "media", detail: "Image and audio tools", isEnabled: false),
          ]
        ),
        ProfileCapabilitySummaryPresentation(
          kind: .mcpServer,
          title: "MCP servers",
          systemImage: "server.rack",
          options: [
            .init(name: "github", detail: "stdio", isEnabled: true),
            .init(name: "sentry", detail: "http", isEnabled: true),
            .init(name: "production-db", detail: "http", isEnabled: false),
          ]
        ),
      ],
      reasoningOptions: ["", "low", "medium", "high"]
    )
  }

  private func editorView(
    presentation: ProfileEditorPresentation,
    mode: ProfileSoulModePresentation,
    soul: String
  ) -> some View {
    NavigationStack {
      ProfileEditorContent(
        presentation: presentation,
        bindings: ProfileEditorBindings(
          name: .constant("ios-release"),
          description: .constant("Ships Hermes Control and watches TestFlight feedback."),
          model: .constant("gpt-5.6-codex"),
          provider: .constant("openai"),
          reasoningEffort: .constant("high"),
          soul: .constant(soul),
          soulMode: .constant(mode)
        ),
        actions: ProfileEditorActions(
          onClose: {},
          onReload: {},
          onSave: {},
          onRestoreDraft: {},
          onDiscardRecoveredDraft: {},
          onSetCapabilityEnabled: { _, _, _ in },
          onRename: {},
          onDelete: {}
        )
      )
    }
  }

  private static let soulMarkdown = """
    # iOS Release Partner

    Keep releases **small, reversible, and observable**.

    - Check reducer behavior before view polish.
    - Preserve user drafts through every failure.
    - Report partial saves field by field.

    > Never claim a TestFlight build passed without executed evidence.
    """
}
