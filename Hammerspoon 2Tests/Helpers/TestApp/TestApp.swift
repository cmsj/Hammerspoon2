//
//  TestApp.swift
//  Hammerspoon 2 Test App
//
//  The app the integration tests launch, hide, quit and open windows in, instead of Finder or
//  Chess: it starts fast, shows nothing personal, and its window says which test is running.
//
//  A single AppKit file, so `swiftc` builds it without an Xcode target (build-test-app.sh, next to
//  this file). The tests drive it through `TestAppControl`.
//
//  This folder belongs to the test target, which compiles every Swift file in it. TEST_APP is
//  only set by build-test-app.sh, so the test bundle gets nothing from this file.
//

#if TEST_APP

import AppKit

/// Tests send commands as a distributed notification with this name. `userInfo`:
/// `command` is `show` (with `test` and `detail`), `newWindow`, `fullScreenWindow`, `closeWindows` or
/// `revertMainOnActivate` (with `title`); `pid` is the copy it is meant for, since several can run at once.
let commandNotification = Notification.Name("net.tenshu.Hammerspoon-2.TestApp.command")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private let testLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var extraWindows: [NSWindow] = []
    /// Title of the window to put back in front each time the app becomes active, if any.
    private var revertTitle: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        mainWindow = makeMainWindow()

        // Launch arguments: -test "name" -detail "what it checks"
        let arguments = UserDefaults.standard
        show(test: arguments.string(forKey: "test"), detail: arguments.string(forKey: "detail"))

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleCommand(_:)), name: commandNotification, object: nil,
            suspensionBehavior: .deliverImmediately)
    }

    /// Like Google Chrome (#356): shortly after becoming active, put a window of the app's own
    /// choosing back in front, in place of the one the activation brought forward.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard let revertTitle else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            NSApp.windows.first { $0.title == revertTitle }?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func handleCommand(_ notification: Notification) {
        let info = notification.userInfo
        guard info?["pid"] as? String == String(ProcessInfo.processInfo.processIdentifier) else { return }
        switch info?["command"] as? String {
        case "show": show(test: info?["test"] as? String, detail: info?["detail"] as? String)
        case "newWindow": newWindow(nil)
        case "fullScreenWindow": fullScreenWindow()
        case "closeWindows": closeExtraWindows()
        case "revertMainOnActivate": revertTitle = info?["title"] as? String
        default: break
        }
    }

    private func show(test: String?, detail: String?) {
        testLabel.stringValue = test ?? "No test running"
        detailLabel.stringValue = detail ?? ""
    }

    @objc func newWindow(_ sender: Any?) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Test window \(extraWindows.count + 1)"
        window.isReleasedWhenClosed = false

        let heading = NSTextField(labelWithString: "Window \(extraWindows.count + 1), opened for the test:")
        heading.font = .systemFont(ofSize: 15)
        heading.textColor = .secondaryLabelColor
        let test = NSTextField(wrappingLabelWithString: testLabel.stringValue)
        test.font = .systemFont(ofSize: 22, weight: .bold)
        window.contentView = padded([heading, test], spacing: 10, inset: 24)
        if let frame = mainWindow?.frame {
            let offset = CGFloat(extraWindows.count * 24)
            window.setFrameTopLeftPoint(NSPoint(x: frame.minX + 24 + offset, y: frame.minY - 12 - offset))
        }
        window.orderFrontRegardless()
        extraWindows.append(window)
    }

    /// Opens a window and puts it in native fullscreen, which moves it to a Space of its own.
    private func fullScreenWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 150),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Fullscreen test window"
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        let test = NSTextField(wrappingLabelWithString: testLabel.stringValue)
        test.font = .systemFont(ofSize: 32, weight: .bold)
        window.contentView = padded([test], spacing: 10, inset: 30)
        extraWindows.append(window)

        // Only the active app's key window can enter fullscreen.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    private func closeExtraWindows() {
        extraWindows.forEach { $0.close() }
        extraWindows.removeAll()
    }

    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Hammerspoon 2 Test App"
        window.isReleasedWhenClosed = false

        let heading = NSTextField(labelWithString: "Hammerspoon 2 integration test running:")
        heading.font = .systemFont(ofSize: 15)
        heading.textColor = .secondaryLabelColor
        testLabel.font = .systemFont(ofSize: 32, weight: .bold)
        detailLabel.font = .systemFont(ofSize: 18)
        detailLabel.textColor = .secondaryLabelColor

        window.contentView = padded([heading, testLabel, detailLabel], spacing: 14, inset: 30)
        window.center()
        window.orderFrontRegardless()
        return window
    }

    /// The views stacked top to bottom, with a margin around them.
    private func padded(_ views: [NSView], spacing: CGFloat, inset: CGFloat) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        return content
    }

    /// Fixed English titles, whatever the system language, so tests can look menu items up by name.
    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Hammerspoon 2 Test App", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        return main
    }
}

@main
enum TestApp {
    static func main() {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
}

#endif
