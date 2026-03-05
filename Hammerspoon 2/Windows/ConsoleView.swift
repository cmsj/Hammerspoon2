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

    @State var searchString: String = ""
    @State var searchPresented: Bool = false

    @State var saveError: String?
    @State var showSaveError: Bool = false

    @Environment(\.dismissWindow) var dismissWindow

    @AppStorage("minimumLogLevel") var minimumLogLevel: HammerspoonLogType = .Trace

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

            TextField(">", text: $evalString, prompt: Text("Javascript: >"))
                .padding()
                .onKeyPress(keys: [.upArrow], phases: .up, action: { _ in
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
                    return .handled
                })
                .onKeyPress(keys: [.downArrow], phases: .up, action: { _ in
                    switch (evalIndex) {
                    case -1:
                        // We're not in history yet, pressing down here has no effect
                        return .ignored
                    case evalHistory.count - 1:
                        // We've reached the end of history, return to emptiness
                        evalString = ""
                        evalIndex = -1
                        return .handled
                    default:
                        evalIndex = evalIndex + 1
                    }
                    evalString = evalHistory[evalIndex]
                    return .handled
                })
                .onSubmit {
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
        }
        .toolbar(id: "console-toolbar") {
            ToolbarItem(id: "minimumLogLevel") {
                Picker("Minimum log level", selection: $minimumLogLevel) {
                    ForEach(HammerspoonLogType.allCases) { item in
                        Text(item.asString)
                    }
                }
            }
            ToolbarItem(id: "saveLogs") {
                Button("Save to File") {
                    let savePanel = NSSavePanel()
                    savePanel.allowedContentTypes = [.plainText]
                    savePanel.nameFieldStringValue = "hammerspoon-console-\(Date().timeIntervalSince1970).txt"
                    savePanel.begin { response in
                        if response == .OK, let url = savePanel.url {
                            let logText = logs.entries
                                .filter { $0.logType.rawValue >= minimumLogLevel.rawValue }
                                .map { formatEntry($0) }
                                .joined(separator: "\n")

                            do {
                                try logText.write(to: url, atomically: true, encoding: .utf8)
                            } catch {
                                saveError = error.localizedDescription
                                showSaveError = true
                            }
                        }
                    }
                }
            }
            ToolbarItem(id: "clearLogs") {
                Button("Clear Logs") {
                    HammerspoonLog.shared.clearLog()
                }
            }
        }
        .alert("Save Failed", isPresented: $showSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveError ?? "Unknown error")
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
