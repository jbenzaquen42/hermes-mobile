import SnapshotTesting
import SwiftUI
import XCTest

@testable import HermesMobile

final class CapabilityManagementSnapshotTests: SnapshotTestCase {
  func testSkillsCatalog_dirtyWarning() {
    assertSnapshot(
      of: catalogView(
        segment: .skills,
        items: skillItems,
        isDirty: true,
        warning: "One catalog entry changed on the server. Reload before saving if you did not expect it."
      ),
      as: deviceImage()
    )
  }

  func testToolsetsCatalog_partialSave() {
    assertSnapshot(
      of: catalogView(
        segment: .toolsets,
        items: toolsetItems,
        isDirty: true,
        saveState: .partial(
          saved: ["Skills"],
          failed: ["Toolsets"],
          notes: ["The refreshed MCP catalog could not be loaded."]
        )
      ),
      as: deviceImage()
    )
  }

  func testToolsetsCatalog_activeWorkflowWarning() {
    assertSnapshot(
      of: catalogView(
        segment: .toolsets,
        items: toolsetItems,
        isDirty: true,
        warning: "Disabling Coding may affect work currently running with ios-release. Saving will not stop that work."
      ),
      as: deviceImage()
    )
  }

  func testMCPServersCatalog_safeMetadata() {
    assertSnapshot(
      of: catalogView(segment: .mcpServers, items: mcpItems),
      as: deviceImage()
    )
  }

  func testCatalog_saveError() {
    assertSnapshot(
      of: catalogView(
        segment: .skills,
        items: skillItems,
        isDirty: true,
        saveState: .failed("Hermes rejected the capability update. Your choices are still here.")
      ),
      as: deviceImage()
    )
  }

  func testCatalog_searchNoResults() {
    assertSnapshot(
      of: catalogView(segment: .skills, items: [], searchText: "calendar"),
      as: deviceImage()
    )
  }

  func testCatalog_unsupported() {
    assertSnapshot(
      of: catalogView(
        segment: .skills,
        items: [],
        loadState: .unsupported(
          "This Hermes server does not expose the capability catalog methods."
        )
      ),
      as: deviceImage()
    )
  }

  func testMCPDetail_accessibilityDynamicType() {
    let view = NavigationStack {
      CapabilityDetailView(item: mcpItems[0], onSetEnabled: { _ in })
    }
    .dynamicTypeSize(.accessibility2)

    assertSnapshot(of: view, as: deviceImage())
  }

  func testSkillDetail_documentationAndSource() {
    let view = NavigationStack {
      CapabilityDetailView(item: skillItems[0], onSetEnabled: { _ in })
    }

    assertSnapshot(of: view, as: deviceImage())
  }

  private func catalogView(
    segment: CapabilitySegmentPresentation,
    items: [CapabilityItemPresentation],
    searchText: String = "",
    loadState: CapabilityCatalogLoadPresentation = .loaded,
    isDirty: Bool = false,
    warning: String? = nil,
    saveState: CapabilityCatalogSavePresentation = .idle
  ) -> some View {
    NavigationStack {
      CapabilityManagementContent(
        presentation: CapabilityCatalogPresentation(
          profileName: "ios-release",
          loadState: loadState,
          saveState: saveState,
          visibleItems: items,
          totalCount: items.count,
          isDirty: isDirty,
          canSave: isDirty,
          canLoadMore: segment == .skills && !items.isEmpty,
          isLoadingMore: false,
          warningBanner: warning,
          errorBanner: nil
        ),
        bindings: CapabilityCatalogBindings(
          segment: .constant(segment),
          searchText: .constant(searchText)
        ),
        actions: CapabilityCatalogActions(
          onClose: {},
          onReload: {},
          onSave: {},
          onLoadMore: {},
          onSelect: { _ in },
          onSetEnabled: { _, _ in }
        )
      )
    }
  }

  private var skillItems: [CapabilityItemPresentation] {
    [
      CapabilityItemPresentation(
        id: "openai-docs",
        segment: .skills,
        name: "OpenAI Docs",
        summary: "Source-backed help for Codex and the OpenAI API.",
        details: "Searches official OpenAI documentation and returns direct references.",
        source: "Bundled",
        category: "Documentation",
        documentation: "See the [OpenAI API documentation](https://platform.openai.com/docs).",
        toolCount: nil,
        toolNames: [],
        transport: nil,
        health: nil,
        warning: nil,
        isEnabled: true
      ),
      CapabilityItemPresentation(
        id: "release-notes",
        segment: .skills,
        name: "Release Notes",
        summary: "Drafts concise App Store and TestFlight release notes.",
        details: "Uses the current branch diff and validation evidence.",
        source: "Workspace",
        category: "Delivery",
        documentation: nil,
        toolCount: nil,
        toolNames: [],
        transport: nil,
        health: nil,
        warning: nil,
        isEnabled: false
      ),
    ]
  }

  private var toolsetItems: [CapabilityItemPresentation] {
    [
      CapabilityItemPresentation(
        id: "coding",
        segment: .toolsets,
        name: "Coding",
        summary: "Read, edit, test, and inspect repository files.",
        details: "The standard repository-development toolset.",
        source: "Hermes",
        category: "Development",
        documentation: nil,
        toolCount: 12,
        toolNames: ["read_file", "apply_patch", "exec_command"],
        transport: nil,
        health: nil,
        warning: nil,
        isEnabled: true
      ),
      CapabilityItemPresentation(
        id: "browser",
        segment: .toolsets,
        name: "Browser",
        summary: "Navigate and inspect interactive websites.",
        details: "Browser automation tools for visible pages and local testing.",
        source: "Hermes",
        category: "Web",
        documentation: nil,
        toolCount: 8,
        toolNames: [],
        transport: nil,
        health: nil,
        warning: nil,
        isEnabled: false
      ),
    ]
  }

  private var mcpItems: [CapabilityItemPresentation] {
    [
      CapabilityItemPresentation(
        id: "github",
        segment: .mcpServers,
        name: "GitHub",
        summary: "Repository, pull request, issue, and review tools.",
        details: "Safe catalog metadata reported by Hermes. Secrets and environment values are never shown.",
        source: "Server catalog",
        category: "Developer tools",
        documentation: nil,
        toolCount: 4,
        toolNames: ["get_pull_request", "list_issues", "create_review", "merge_pull_request"],
        transport: "http",
        health: .healthy("Connected"),
        warning: nil,
        isEnabled: true
      ),
      CapabilityItemPresentation(
        id: "sentry",
        segment: .mcpServers,
        name: "Sentry",
        summary: "Production issue and trace inspection.",
        details: "Only server-reported safe metadata is available on mobile.",
        source: "Server catalog",
        category: "Observability",
        documentation: nil,
        toolCount: 3,
        toolNames: ["search_issues", "get_trace", "list_projects"],
        transport: "stdio",
        health: .warning("Needs attention"),
        warning: "Hermes reported that this server is configured but not currently reachable.",
        isEnabled: false
      ),
    ]
  }
}
