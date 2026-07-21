import SwiftUI
import AppKit

/// A single entry in the custom (non-native) terminal tab bar.
struct TerminalTabItem: Identifiable, Equatable {
    /// Stable identity of the internal tab, used to route selection/close.
    let id: Int

    /// 1-based position shown to the user.
    let index: Int

    /// The tab title.
    let title: String

    /// Whether this is the selected tab.
    let isActive: Bool

    /// Optional user-assigned tab color, used as an accent on the tab.
    let tabColor: Color?
}

/// The custom terminal tab bar. A thin bar pinned to the bottom of the window
/// whose colors are derived from the terminal color scheme. The visual style is
/// selectable via the `custom-tab-style` config (see `Ghostty.Config`):
///
///   * `.boxed` - minimal rounded, bordered chips (default).
///   * `.powerline` - Kitty-inspired solid slanted blocks, active inverted.
///   * `.emacs` - Emacs tab-line: flat text tabs, bars between, active underline.
///
/// Across all styles: tabs are fixed-width and un-animated so the strip never
/// shifts when switching tabs or when a title's length changes.
struct TerminalTabBarView: View {
    let tabs: [TerminalTabItem]
    let backgroundColor: Color
    let foregroundColor: Color
    let style: Ghostty.Config.CustomTabStyle

    /// Invoked with a tab's `id` when the user activates it.
    let onSelect: (Int) -> Void
    /// Invoked with a tab's `id` when the user requests it be closed.
    let onClose: (Int) -> Void
    /// Invoked when the user requests a new tab via the "+" button.
    let onNewTab: () -> Void

    private var barHeight: CGFloat {
        switch style {
        case .emacs, .minimal, .underline: return 26
        case .boxed, .powerline: return 30
        }
    }
    private var interTabSpacing: CGFloat {
        switch style {
        case .boxed: return 5
        case .powerline, .emacs: return 0
        case .minimal, .underline: return 2
        }
    }

    var body: some View {
        let palette = TerminalTabPalette(
            background: backgroundColor,
            foreground: foregroundColor)

        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: interTabSpacing) {
                    ForEach(tabs) { tab in
                        tabView(tab, palette)
                    }
                }
                .padding(.horizontal, style == .boxed ? 8 : 0)
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
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .background(palette.barBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.separator)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func tabView(_ tab: TerminalTabItem, _ palette: TerminalTabPalette) -> some View {
        switch style {
        case .boxed:
            BoxedTab(tab: tab, palette: palette,
                     onSelect: { onSelect(tab.id) }, onClose: { onClose(tab.id) })
        case .powerline:
            PowerlineTab(tab: tab, palette: palette,
                         onSelect: { onSelect(tab.id) }, onClose: { onClose(tab.id) })
        case .emacs:
            EmacsTab(tab: tab, palette: palette,
                     onSelect: { onSelect(tab.id) }, onClose: { onClose(tab.id) })
        case .minimal:
            MinimalTab(tab: tab, palette: palette, underline: false,
                       onSelect: { onSelect(tab.id) }, onClose: { onClose(tab.id) })
        case .underline:
            MinimalTab(tab: tab, palette: palette, underline: true,
                       onSelect: { onSelect(tab.id) }, onClose: { onClose(tab.id) })
        }
    }
}

// MARK: - Boxed style (default)

/// A single boxed tab "chip": rounded, bordered, fixed width.
private struct BoxedTab: View {
    let tab: TerminalTabItem
    let palette: TerminalTabPalette
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    private static let tabWidth: CGFloat = 150

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
                .frame(maxWidth: .infinity, alignment: .leading)

            CloseButton(hovering: hovering,
                        color: palette.textColor(active: tab.isActive),
                        action: onClose)
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(width: Self.tabWidth, height: 22, alignment: .leading)
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
    }
}

// MARK: - Powerline style (Kitty-inspired)

/// A flat, solid block. The active tab is filled with an accent and uses
/// inverted (high-contrast) text so the strip reads like a TUI status line.
/// Blocks abut and are delineated by a thin trailing separator.
private struct PowerlineTab: View {
    let tab: TerminalTabItem
    let palette: TerminalTabPalette
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    private static let tabWidth: CGFloat = 160

    var body: some View {
        let fill = palette.powerlineFill(active: tab.isActive, hovering: hovering)
        let text = palette.powerlineText(active: tab.isActive)

        HStack(spacing: 7) {
            Text("\(tab.index)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(text.opacity(0.75))

            Text(tab.title.isEmpty ? "…" : tab.title)
                .font(.system(size: 12, weight: tab.isActive ? .semibold : .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(text)
                .frame(maxWidth: .infinity, alignment: .leading)

            CloseButton(hovering: hovering, color: text, action: onClose)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(width: Self.tabWidth, height: 30, alignment: .leading)
        .background(fill)
        .overlay(alignment: .trailing) {
            // Thin separator between abutting blocks.
            Rectangle().fill(palette.separator).frame(width: 1)
        }
        .overlay(alignment: .leading) {
            // A left accent bar on the active tab, like a status-line marker.
            if tab.isActive, let accent = tab.tabColor {
                Rectangle().fill(accent).frame(width: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

// MARK: - Emacs style (tab-line)

/// A flat text tab in the Emacs `tab-line` spirit: minimal, separated by thin
/// vertical bars, with an accent underline on the active tab.
private struct EmacsTab: View {
    let tab: TerminalTabItem
    let palette: TerminalTabPalette
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    private static let tabWidth: CGFloat = 140

    var body: some View {
        HStack(spacing: 0) {
            // Leading vertical separator bar between tabs.
            Rectangle()
                .fill(palette.separator)
                .frame(width: 1, height: 14)

            HStack(spacing: 6) {
                Text("\(tab.index):")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(palette.indexColor(active: tab.isActive))

                Text(tab.title.isEmpty ? "…" : tab.title)
                    .font(.system(size: 12, weight: tab.isActive ? .semibold : .regular, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(palette.textColor(active: tab.isActive))
                    .frame(maxWidth: .infinity, alignment: .leading)

                CloseButton(hovering: hovering,
                            color: palette.textColor(active: tab.isActive),
                            action: onClose)
            }
            .padding(.horizontal, 8)
            .frame(width: Self.tabWidth, height: 26, alignment: .leading)
            .background(tab.isActive ? palette.tabFill(active: true, hovering: false) : .clear)
            .overlay(alignment: .bottom) {
                // Emacs tab-line marks the current tab with an accent underline.
                if tab.isActive {
                    Rectangle()
                        .fill(tab.tabColor ?? palette.accent)
                        .frame(height: 2)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

// MARK: - Minimal / Underline styles

/// The most minimal look: just text (index + title), no fills, borders, or
/// separators. The active tab is brighter and bolder; inactive tabs are dimmed.
/// When `underline` is true, the active tab also gets a thin accent underline.
private struct MinimalTab: View {
    let tab: TerminalTabItem
    let palette: TerminalTabPalette
    let underline: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    private static let tabWidth: CGFloat = 132

    var body: some View {
        HStack(spacing: 6) {
            Text("\(tab.index)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(palette.indexColor(active: tab.isActive))

            Text(tab.title.isEmpty ? "…" : tab.title)
                .font(.system(size: 12, weight: tab.isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(palette.textColor(active: tab.isActive))
                .frame(maxWidth: .infinity, alignment: .leading)

            CloseButton(hovering: hovering,
                        color: palette.textColor(active: tab.isActive),
                        action: onClose)
        }
        .padding(.horizontal, 8)
        .frame(width: Self.tabWidth, height: 24, alignment: .leading)
        .overlay(alignment: .bottom) {
            if underline && tab.isActive {
                Rectangle()
                    .fill(tab.tabColor ?? palette.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

// MARK: - Shared

/// A close button whose slot is always reserved (fixed size); only its
/// visibility toggles on hover, so hovering never changes a tab's width.
private struct CloseButton: View {
    let hovering: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(color.opacity(0.85))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
                .opacity(hovering ? 1 : 0)
        }
        .buttonStyle(.plain)
        .help("Close Tab")
        .allowsHitTesting(hovering)
    }
}

/// Derives a small set of theme-following colors for the tab bar from the
/// terminal background and foreground colors.
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

    /// A theme accent (foreground-leaning) used for active markers.
    var accent: Color {
        Color(nsColor: blend(background, into: foreground, fraction: 0.65))
    }

    func tabFill(active: Bool, hovering: Bool) -> Color {
        if active {
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

    // MARK: Powerline

    /// The active tab is filled near the foreground so text inverts to the
    /// background color — a high-contrast TUI look. Inactive tabs stay near the
    /// background with a slight lift on hover.
    func powerlineFill(active: Bool, hovering: Bool) -> Color {
        if active {
            return Color(nsColor: blend(background, into: foreground, fraction: isLight ? 0.82 : 0.70))
        }
        if hovering {
            return Color(nsColor: blend(background, into: foreground, fraction: 0.12))
        }
        return Color(nsColor: blend(background, into: foreground, fraction: 0.05))
    }

    func powerlineText(active: Bool) -> Color {
        if active {
            // Invert: use the background color for text on the bright fill.
            return Color(nsColor: background)
        }
        return Color(nsColor: foreground.withAlphaComponent(0.6))
    }

    private func blend(_ base: NSColor, into other: NSColor, fraction: CGFloat) -> NSColor {
        base.blended(withFraction: fraction, of: other) ?? base
    }
}
