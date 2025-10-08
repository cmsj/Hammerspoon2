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
            Table(logs.entries.filter {
                if $0.logType.rawValue < minimumLogLevel.rawValue { return false }
                if searchString == "" {
                    return true
                } else {
                    return $0.msg.contains(searchString)
                }
            }, selection: $selectedRows) {
                TableColumn("Date", value: \.date.description)
                    .width(ideal: 150, max: 250)
                TableColumn("Level") { item in
                    Text(item.logType.asString)
                        .foregroundStyle(styleForLogType(item.logType))
                }
                    .width(ideal: 100, max: 150)
                TableColumn("Message", value: \.msg)
            }
            .alternatingRowBackgrounds(.disabled)

            TextField(">", text: $evalString, prompt: Text("Javascript: >"))
                .padding()
                .onSubmit {
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
