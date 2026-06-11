//
//  ChooserWindow.swift
//  Hammerspoon 2
//

import AppKit
import SwiftUI

/// An NSPanel subclass that hosts the ChooserView and behaves like a Spotlight panel:
/// floating, non-activating, keyboard-accepting, transparent background.
@MainActor
final class ChooserPanel: NSPanel {

    private var hostingView: NSHostingView<ChooserView>?

    init(
        screen: NSScreen?,
        width: CGFloat,
        viewModel: ChooserViewModel,
        queryBinding: Binding<String>,
        onSelect: @escaping (Int?) -> Void,
        onRightClick: @escaping (Int) -> Void
    ) {
        let s = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = ChooserPanel.initialFrame(on: s, width: width, height: ChooserViewModel.searchBarHeight)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isFloatingPanel = true
        self.level = .floating
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.animationBehavior = .utilityWindow

        let view = ChooserView(
            viewModel: viewModel,
            queryBinding: queryBinding,
            onSelect: onSelect,
            onRightClick: onRightClick
        )
        let hosting = NSHostingView(rootView: view)
        // Disable automatic window-resizing driven by SwiftUI content size.
        // A LazyVStack inside a ScrollView reports its full content height as the
        // fitting size, which would make the window expand to show every row.
        // We manage the window frame exclusively via setHeight(_:).
        hosting.sizingOptions = []
        self.contentView = hosting
        self.hostingView = hosting
    }

    override var canBecomeKey: Bool { isVisible }
    override var canBecomeMain: Bool { false }

    /// Position: horizontally centered on the screen, 25 % down from the top.
    static func initialFrame(on screen: NSScreen, width: CGFloat, height: CGFloat) -> CGRect {
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - width / 2
        let y = screenFrame.maxY - screenFrame.height * 0.25 - height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Resize the window, keeping the top-left corner pinned.
    func setHeight(_ height: CGFloat, animated: Bool = false) {
        var frame = self.frame
        let deltaY = frame.height - height
        frame.origin.y += deltaY
        frame.size.height = height
        setFrame(frame, display: true, animate: animated)
    }
}
