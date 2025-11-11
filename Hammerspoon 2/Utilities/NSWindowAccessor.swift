//
//  NSWindowAccessor.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 08/06/2025.
//

import SwiftUI

@MainActor
protocol WindowAccessorDelegate {
    var window: NSWindow? { get set }
}

struct NSWindowAccessor: NSViewRepresentable {
    @State var delegate: WindowAccessorDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            print(unsafe "Attaching NSWindow for '\(view.window?.title ?? "nil")' to WindowAccessorDelegate")
            delegate.window = unsafe view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
