import SwiftUI
import AppKit

/// A single entry in the custom (non-native) terminal tab bar.
///
/// Each Ghostty tab is backed by its own `NSWindow` in an AppKit tab group, so
/// one of these mirrors a single window in `window.tabbedWindows`. The bar is
/// rebuilt whenever the tab group changes (see
/// `TerminalController.updateTabBarModel()`).
struct TerminalTabItem: Identifiable, Equatable {
    /// Stable identity of the backing window (its `windowNumber`), used to
    /// route selection/close actions back to the correct window.
    let id: Int

    /// 1-based position shown to the user.
    let index: Int

    /// The window/tab title.
    let title: String

    /// Whether this is the selected tab in the group.
    let isActive: Bool

    /// Optional user-assigned tab color, used as an accent on the tab.
    let tabColor: Color?
}

/// The custom terminal tab bar. This is a minimal, "terminal-native" tab strip
/// drawing inspiration from Kitty and Emacs: a thin bar pinned to the bottom of
/// the window with small boxed tabs whose colors are derived from the terminal
/// color scheme (background/foreground) rather than the system chrome.
struct TerminalTabBarView: View {
    let tabs: [TerminalTabItem]
    let backgroundColor: Color
    let foregroundColor: Color

    /// Invoked with a tab's `id` when the user activates it.
    let onSelect: (Int) -> Void
    /// Invoked with a tab's `id` when the user requests it be closed.
    let onClose: (Int) -> Void
    /// Invoked when the user requests a new tab via the "+" button.
    let onNewTab: () -> Void

    var body: some View {
        let palette = TerminalTabPalette(
            background: backgroundColor,
            foreground: foregroundColor)

        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(tabs) { tab in
                        TerminalTabButton(
                            tab: tab,
                            palette: palette,
                            onSelect: { onSelect(tab.id) },
                            onClose: { onClose(tab.id) })
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(palette.textColor(active: false))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
            .padding(.trailing, 6)
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(palette.barBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.separator)
                .frame(height: 1)
        }
    }
}

/// A single boxed tab button.
private struct TerminalTabButton: View {
    let tab: TerminalTabItem
    let palette: TerminalTabPalette
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text("\(tab.index)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(palette.indexColor(active: tab.isActive))

            Text(tab.title.isEmpty ? "…" : tab.title)
                .font(.system(size: 12, weight: tab.isActive ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(palette.textColor(active: tab.isActive))

            // The close button only appears on hover to keep the resting state
            // minimal (Kitty/Emacs-like).
            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(palette.textColor(active: tab.isActive).opacity(0.85))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close Tab")
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, hovering ? 5 : 9)
        .frame(height: 22)
        .frame(minWidth: 46, maxWidth: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(palette.tabFill(active: tab.isActive, hovering: hovering)))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(
                    tab.tabColor ?? palette.tabBorder(active: tab.isActive),
                    lineWidth: tab.isActive ? 1 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
    }
}

/// Derives a small set of theme-following colors for the tab bar from the
/// terminal background and foreground colors. Active tabs get a slightly
/// "lifted" background and full-strength text; inactive tabs are dimmed.
private struct TerminalTabPalette {
    private let background: NSColor
    private let foreground: NSColor
    private let isLight: Bool

    init(background: Color, foreground: Color) {
        let bg = NSColor(background).usingColorSpace(.sRGB) ?? .windowBackgroundColor
        let fg = NSColor(foreground).usingColorSpace(.sRGB) ?? .labelColor
        self.background = bg
        self.foreground = fg
        self.isLight = bg.isLightColor
    }

    var barBackground: Color { Color(nsColor: background) }

    var separator: Color {
        Color(nsColor: foreground.withAlphaComponent(0.12))
    }

    func tabFill(active: Bool, hovering: Bool) -> Color {
        if active {
            // Lift the background toward the foreground so the active tab reads
            // as raised regardless of light/dark scheme.
            return Color(nsColor: blend(background, into: foreground, fraction: isLight ? 0.10 : 0.16))
        }
        if hovering {
            return Color(nsColor: blend(background, into: foreground, fraction: 0.06))
        }
        return .clear
    }

    func tabBorder(active: Bool) -> Color {
        Color(nsColor: foreground.withAlphaComponent(active ? 0.28 : 0.10))
    }

    func textColor(active: Bool) -> Color {
        Color(nsColor: foreground.withAlphaComponent(active ? 1.0 : 0.55))
    }

    func indexColor(active: Bool) -> Color {
        Color(nsColor: foreground.withAlphaComponent(active ? 0.7 : 0.4))
    }

    private func blend(_ base: NSColor, into other: NSColor, fraction: CGFloat) -> NSColor {
        base.blended(withFraction: fraction, of: other) ?? base
    }
}
