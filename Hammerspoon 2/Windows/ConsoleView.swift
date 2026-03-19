//
//  ConsoleView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 07/10/2025.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@_documentation(visibility: private)
struct ConsoleView: View {
    @State var logs = HammerspoonLog.shared

    @State var evalString: String = ""
    @State var evalHistory: [String] = []
    @State var evalIndex: Int = -1

    /// Non-nil while a completion session is active (user keeps pressing Tab).
    @State var activeCompletion: ConsoleCompletionEngine.Result? = nil
    @State var completionCycleIndex: Int = 0
    @State var textSelection: TextSelection? = nil

    @State var searchString: String = ""
    @State var searchPresented: Bool = false

    @State var saveError: String?
    @State var showSaveError: Bool = false

    @Environment(\.dismissWindow) var dismissWindow

    @AppStorage("minimumLogLevel") var minimumLogLevel: HammerspoonLogType = .Trace

    private var filteredEntries: [HammerspoonLogEntry] {
        logs.entries.filter {
            $0.logType.rawValue >= minimumLogLevel.rawValue &&
            (searchString.isEmpty || $0.msg.localizedStandardContains(searchString))
        }
    }

    private func formatEntry(_ entry: HammerspoonLogEntry) -> String {
        let date = entry.date.formatted(
            .verbatim(
                "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
                locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent, calendar: .autoupdatingCurrent
            )
        )
        return "\(date) - \(entry.logType.asString): \(entry.msg)"
    }

    private func colorForLogType(_ logType: HammerspoonLogType) -> Color {
        switch logType {
        case .Error: return .red
        case .Warning: return .orange
        default: return .primary
        }
    }

    fileprivate func handleUpArrow() -> KeyPress.Result {
        switch (evalIndex) {
        case -1:
            // Start walking up the history
            evalIndex = evalHistory.count - 1
        case 0:
            // We can go no further, evalIndex has taken us to the start of history
            return .ignored
        default:
            evalIndex = evalIndex - 1
        }
        evalString = evalHistory[evalIndex]
        // The system's default up-arrow action (move cursor to start) fires before this
        // handler runs. Override it by explicitly placing the cursor at the end.
        textSelection = TextSelection(range: evalString.endIndex..<evalString.endIndex)
        return .handled
    }

    fileprivate func handleDownArrow() -> KeyPress.Result {
        switch (evalIndex) {
        case -1:
            // We're not in history yet, pressing down here has no effect
            return .ignored
        case evalHistory.count - 1:
            // We've reached the end of history, return to emptiness
            evalString = ""
            evalIndex = -1
            textSelection = nil
            return .handled
        default:
            evalIndex = evalIndex + 1
        }
        evalString = evalHistory[evalIndex]
        textSelection = TextSelection(range: evalString.endIndex..<evalString.endIndex)
        return .handled
    }

    /// If `evalString` contains a call with parameters starting at `completionOffset`,
    /// selects the first parameter so the user can immediately type its value.
    /// Always writes to `textSelection` — sets nil when there is no parameter to select,
    /// which causes the cursor to move to the end of the new text.
    private func selectFirstParam(completionOffset: Int) {
        let s = evalString
        guard completionOffset < s.count,
              let openParen = s[s.index(s.startIndex, offsetBy: completionOffset)...].firstIndex(of: "(")
        else { textSelection = nil; return }
        let afterOpen = s.index(after: openParen)
        // Empty parens — nothing to select, move cursor to end.
        guard afterOpen < s.endIndex, s[afterOpen] != ")" else { textSelection = nil; return }
        let end = s[afterOpen...].firstIndex(where: { $0 == "," || $0 == ")" }) ?? s.endIndex
        textSelection = TextSelection(range: afterOpen..<end)
    }

    fileprivate func handleTab() -> KeyPress.Result {
        if let active = activeCompletion {
            // Subsequent Tab presses cycle through the candidate list.
            completionCycleIndex = (completionCycleIndex + 1) % active.candidates.count
            evalString = active.inputPrefix + active.prefix + active.candidates[completionCycleIndex].completion
            selectFirstParam(completionOffset: active.inputPrefix.count + active.prefix.count)
            return .handled
        }

        guard let result = ConsoleCompletionEngine.complete(input: evalString) else {
            return .ignored
        }

        if result.isUnique {
            evalString = result.inputPrefix + result.prefix + result.candidates[0].completion
            selectFirstParam(completionOffset: result.inputPrefix.count + result.prefix.count)
            // No cycling state needed for a unique match.
            return .handled
        }

        // Multiple candidates: fill to the longest common prefix and print all options.
        let lcp = result.longestCommonPrefix
        evalString = result.inputPrefix + result.prefix + lcp
        textSelection = nil   // move cursor to end

        AKConsole(result.displayString)

        // Enter cycling state so the next Tab cycles through candidates.
        activeCompletion = result
        completionCycleIndex = -1
        return .handled
    }

    fileprivate func handleSubmit() {
        // Echo the command
        AKInfo("> \(evalString)")

        evalHistory.append(evalString)
        evalIndex = -1
        if let result = JSEngine.shared.eval(evalString) {
            // FIXME: This is a disgusting hack, there must be a better way to detect if result is a Bool type of NSNumber?
            let typeString = "\(type(of: result))"
            if typeString == "__NSCFBoolean" {
                let boolResult = result as! NSNumber
                AKConsole("\(boolResult.boolValue)")
            } else {
                AKConsole(String(describing: result))
            }
        }
        evalString = ""
    }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    let filteredEntries = logs.entries.filter {
                        if $0.logType.rawValue < minimumLogLevel.rawValue { return false }
                        if searchString == "" {
                            return true
                        } else {
                            return $0.msg.contains(searchString)
                        }
                    }

                    let logText: AttributedString = {
                        var result = AttributedString()
                        for (index, entry) in filteredEntries.enumerated() {
                            var part = AttributedString(formatEntry(entry))
                            part.foregroundColor = colorForLogType(entry.logType)
                            result.append(part)
                            if index < filteredEntries.count - 1 {
                                result.append(AttributedString("\n"))
                            }
                        }
                        return result
                    }()

                    Text(logText)
                        .multilineTextAlignment(.leading)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()

                    Color.clear
                        .frame(height: 0)
                        .id("logBottom")
                }
                .onChange(of: logs.entries) {
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }

            TextField(">", text: $evalString, selection: $textSelection, prompt: Text("Javascript: >"))
                .padding()
                .onKeyPress(keys: [.upArrow], phases: .up, action: { _ in
                    activeCompletion = nil
                    return handleUpArrow()
                })
                .onKeyPress(keys: [.downArrow], phases: .up, action: { _ in
                    activeCompletion = nil
                    return handleDownArrow()
                })
                .onKeyPress(keys: [.tab], phases: .down, action: { _ in
                    return handleTab()
                })
                .onChange(of: evalString) { _, newValue in
                    // Any edit that isn't a completion or the LCP fill cancels the cycling session.
                    if let active = activeCompletion {
                        let isCandidate = active.candidates.contains(where: {
                            active.inputPrefix + active.prefix + $0.completion == newValue
                        })
                        let isLCP = newValue == active.inputPrefix + active.prefix + active.longestCommonPrefix
                        if !isCandidate && !isLCP {
                            activeCompletion = nil
                        }
                    }
                }
                .onSubmit {
                    activeCompletion = nil
                    handleSubmit()
                }
        }
        .toolbar(id: "console-toolbar") {
            ToolbarItem(id: "minimumLogLevel") {
                Picker("Minimum log level", selection: $minimumLogLevel) {
                    ForEach(HammerspoonLogType.allCases) { item in
                        Text(item.asString)
                    }
                }
            }
            ToolbarItem(id: "clearLogs") {
                Button("Clear Logs") {
                    HammerspoonLog.shared.clearLog()
                }
            }
        }
        .searchable(text: $searchString, isPresented: $searchPresented)
        .handlesExternalEvents(preferring: ["closeConsole"], allowing: [])
        .onOpenURL { url in
            if let command = url.host(percentEncoded: false) {
                switch command {
                case "openConsole":
                    // This is handled by SwiftUI for us
                    break
                case "closeConsole":
                    AKTrace("Handling closeConsole")
                    Task { @MainActor in
                        dismissWindow(id: "console")
                    }
                default:
                    AKError("Unknown command: \(command)")
                }
            } else {
                AKError("Unknown console event: \(url)")
            }
        }
    }
}

#Preview {
    ConsoleView()
}
