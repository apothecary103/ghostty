import AppKit
import SwiftUI
import GhosttyKit

/// Content for a background (inactive) internal tab. These are kept mounted in
/// the window (hidden behind the active tab) so their terminal surfaces stay
/// alive and rendering across tab switches — surfaces that leave the window
/// entirely get their renderer paused with no clean resume.
struct InactiveTabContent: Identifiable {
    let id: Int
    let tree: SplitTree<Ghostty.SurfaceView>
}

/// Internal (non-native) tab support for `TerminalController`.
///
/// Instead of using AppKit's `NSWindowTabGroup` (where each tab is a separate
/// window), we manage all tabs inside a single window. Each tab owns its own
/// `SplitTree` of surfaces. The *active* tab's tree is always the controller's
/// `surfaceTree` (so all the existing code that operates on `surfaceTree` keeps
/// working on the active tab); switching tabs snapshots the current tree into
/// the active tab and loads the target tab's tree.
extension TerminalController {
    /// A single internal tab: its own split tree of surfaces plus a title.
    final class Tab: Identifiable {
        let id: Int
        var tree: SplitTree<Ghostty.SurfaceView>
        var title: String

        init(id: Int, tree: SplitTree<Ghostty.SurfaceView>, title: String) {
            self.id = id
            self.tree = tree
            self.title = title
        }
    }

    /// Seed the tabs array with the initial surface tree. Call this once the
    /// controller's initial `surfaceTree` is set (e.g. in windowDidLoad).
    func seedInitialTabIfNeeded() {
        guard tabs.isEmpty else { return }
        let tab = Tab(id: nextTabID(), tree: surfaceTree, title: window?.title ?? "👻")
        tabs = [tab]
        selectedTabID = tab.id
        rebuildTabBarModel()
    }

    /// True if this controller currently has more than one internal tab.
    var hasMultipleTabs: Bool { tabs.count > 1 }

    /// Add a new internal tab with a fresh surface and select it.
    @discardableResult
    func addInternalTab(withBaseConfig base: Ghostty.SurfaceConfiguration? = nil) -> Bool {
        guard let ghostty_app = ghostty.app else { return false }
        seedInitialTabIfNeeded()

        // Snapshot the current active tab's tree before we replace surfaceTree.
        snapshotActiveTab()

        let newTree = SplitTree<Ghostty.SurfaceView>(
            view: Ghostty.SurfaceView(ghostty_app, baseConfig: base))
        let tab = Tab(id: nextTabID(), tree: newTree, title: "👻")

        // Insert after the active tab, or at the end.
        if let idx = activeTabIndex {
            tabs.insert(tab, at: idx + 1)
        } else {
            tabs.append(tab)
        }

        selectedTabID = tab.id
        surfaceTree = newTree
        focusActiveTab()
        rebuildTabBarModel()
        return true
    }

    /// Switch to the internal tab with the given id.
    func selectInternalTab(id: Int) {
        guard id != selectedTabID,
              tabs.contains(where: { $0.id == id }) else { return }
        snapshotActiveTab()
        selectedTabID = id
        if let tab = tabs.first(where: { $0.id == id }) {
            surfaceTree = tab.tree
        }
        focusActiveTab()
        rebuildTabBarModel()
    }

    /// Select the tab at a relative offset from the current one (wraps).
    func selectInternalTab(relative offset: Int) {
        guard !tabs.isEmpty, let idx = activeTabIndex else { return }
        let count = tabs.count
        let next = ((idx + offset) % count + count) % count
        selectInternalTab(id: tabs[next].id)
    }

    /// Select the tab at an absolute 1-based position (as used by goto_tab:N).
    func selectInternalTab(absolute position: Int) {
        guard position >= 1, position <= tabs.count else { return }
        selectInternalTab(id: tabs[position - 1].id)
    }

    /// Close the internal tab with the given id. If it was the last tab, the
    /// window is closed.
    func closeInternalTab(id: Int) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }

        // If this is the last tab, close the whole window.
        if tabs.count <= 1 {
            self.window?.close()
            return
        }

        let wasActive = (id == selectedTabID)
        tabs.remove(at: idx)

        if wasActive {
            // Select a neighbor (prefer the one that shifted into this slot).
            let newIdx = min(idx, tabs.count - 1)
            let tab = tabs[newIdx]
            selectedTabID = tab.id
            surfaceTree = tab.tree
            focusActiveTab()
        }
        rebuildTabBarModel()
    }

    /// Close the currently active internal tab.
    func closeActiveInternalTab() {
        guard let id = selectedTabID else { return }
        closeInternalTab(id: id)
    }

    // MARK: Internal helpers

    private var activeTabIndex: Int? {
        guard let id = selectedTabID else { return nil }
        return tabs.firstIndex(where: { $0.id == id })
    }

    /// Save the current `surfaceTree` (which is the live active tab) back into
    /// its Tab object so it isn't lost when we swap trees.
    private func snapshotActiveTab() {
        guard let idx = activeTabIndex else { return }
        tabs[idx].tree = surfaceTree
        tabs[idx].title = window?.title ?? "👻"
    }

    private func nextTabID() -> Int {
        let id = tabIDCounter
        tabIDCounter += 1
        return id
    }

    /// Pause the renderers of background (inactive) tabs and resume the active
    /// one. Background tabs stay mounted (so their surfaces stay alive), but we
    /// mark them occluded so Ghostty stops drawing them — otherwise every tab
    /// renders every frame, which is a real performance drain.
    func updateTabOcclusion() {
        let windowVisible = window?.occlusionState.contains(.visible) ?? true

        // The active tab uses the live surfaceTree (it may have splits added
        // since it was last snapshotted); inactive tabs use their stored tree.
        setOcclusion(for: surfaceTree, visible: windowVisible)
        for tab in tabs where tab.id != selectedTabID {
            setOcclusion(for: tab.tree, visible: false)
        }
    }

    private func setOcclusion(for tree: SplitTree<Ghostty.SurfaceView>, visible: Bool) {
        for view in tree {
            guard let surface = view.surface, view.isWindowVisible != visible else { continue }
            ghostty_surface_set_occlusion(surface, visible)
            view.isWindowVisible = visible
        }
    }

    /// Move keyboard focus to the active tab's surface after a tab swap. The
    /// SwiftUI focus chain doesn't follow a surfaceTree replacement on its own.
    private func focusActiveTab() {
        // Prefer the tree's currently-zoomed or first leaf surface.
        guard let target = surfaceTree.first else { return }
        let previous = focusedSurface
        focusedSurface = target
        DispatchQueue.main.async {
            Ghostty.moveFocus(to: target, from: previous)
        }
    }

    /// Rebuild the `tabBarTabs` model that drives the SwiftUI tab strip, and
    /// refresh the theme colors. The strip is hidden when there's a single tab.
    func rebuildTabBarModel() {
        // Keep the active tab's title fresh from the window title.
        if let idx = activeTabIndex {
            tabs[idx].title = window?.title ?? "👻"
        }

        // Publish the background tabs so the view can keep them mounted (hidden
        // behind the active tab) and their surfaces stay alive across switches.
        inactiveTabContents = tabs
            .filter { $0.id != selectedTabID }
            .map { InactiveTabContent(id: $0.id, tree: $0.tree) }

        // Pause background tabs' renderers so they don't draw every frame.
        updateTabOcclusion()

        guard tabs.count > 1 else {
            if !tabBarTabs.isEmpty { tabBarTabs = [] }
            return
        }

        tabBarTabs = tabs.enumerated().map { index, tab in
            TerminalTabItem(
                id: tab.id,
                index: index + 1,
                title: tab.title,
                isActive: tab.id == selectedTabID,
                tabColor: nil)
        }

        tabBarBackgroundColor = focusedSurface?.derivedConfig.backgroundColor
            ?? ghostty.config.backgroundColor
        tabBarForegroundColor = ghostty.config.foregroundColor
    }
}
