//
//  ConsoleView.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 07/10/2025.
//

import SwiftUI

struct ConsoleView: View {
    @State var logs = HammerspoonLog.shared

    @State var evalString: String = ""
    @State var evalHistory: [String] = []
    @State var evalIndex: Int = -1

    @State var selectedRows = Set<HammerspoonLogEntry.ID>()
    @State var searchString: String = ""
    @State var searchPresented: Bool = false

    @Environment(\.dismissWindow) var dismissWindow

    @AppStorage("minimumLogLevel") var minimumLogLevel: HammerspoonLogType = .Trace

    func styleForLogType(_ logType: HammerspoonLogType) -> any ShapeStyle {
        switch logType {
        case .Error: return .red
        case .Warning: return .orange
        default: return .primary
        }
    }

    var body: some View {
        VStack {
//            Table(logs.entries.filter {
//                if $0.logType.rawValue < minimumLogLevel.rawValue { return false }
//                if searchString == "" {
//                    return true
//                } else {
//                    return $0.msg.contains(searchString)
//                }
//            }, selection: $selectedRows) {
//                TableColumn("Date", value: \.date.description)
//                    .width(ideal: 150, max: 250)
//                TableColumn("Level") { item in
//                    Text(item.logType.asString)
//                        .foregroundStyle(styleForLogType(item.logType))
//                }
//                    .width(ideal: 100, max: 150)
//                TableColumn("Message") { item in
//                    Text(item.msg)
//                }
//            }
//            .alternatingRowBackgrounds(.disabled)
//            .listRowSeparator(.hidden)
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(logs.entries.filter {
                        if $0.logType.rawValue < minimumLogLevel.rawValue { return false }
                        if searchString == "" {
                            return true
                        } else {
                            return $0.msg.contains(searchString)
                        }
                    }) { entry in
                        Text("\(entry.date.description) - \(entry.logType.asString): \(entry.msg)")
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
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
