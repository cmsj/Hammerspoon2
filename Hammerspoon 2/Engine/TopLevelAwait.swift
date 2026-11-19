//
//  TopLevelAwait.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

/// JavaScriptCore only allows `await` inside async functions, so a script such as
/// `await hs.spaces.gotoSpace(3)` is a SyntaxError. These rewrite a script like that into an async
/// function that runs it, as Node's REPL does. A script that's already valid is never rewritten,
/// so its behaviour doesn't change.
///
/// The rewritten script doesn't call the function, so that `JSEngine` can attach handlers to the
/// Promise it returns before JavaScriptCore runs any microtasks. Otherwise a rejection would also be
/// reported as unhandled.
enum TopLevelAwait {
    /// Rewrites a line typed into the Console if it only parses inside an async function.
    ///
    /// The rewritten script evaluates to an async function (which it doesn't call) that returns
    /// the input's value when it's a single expression, or `undefined` otherwise. A single
    /// `const`/`let`/`var` declaration becomes a global `var`, so later input can use it.
    /// - Returns: The rewritten script, or nil if `source` doesn't need (or can't be fixed by) rewriting
    static func rewriteConsoleInput(_ source: String, in context: JSContext) -> String? {
        guard needsRewriting(source, in: context) else { return nil }

        var trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(";") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var candidates: [String] = []
        if let match = trimmed.wholeMatch(of: #/(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=(?!=)([\s\S]*)/#) {
            let (name, value) = (match.1, match.2)
            candidates.append("var \(name); (async () => { \(name) = (\n\(value)\n); })")
        }
        // The newlines keep a trailing // comment from swallowing the closing brackets
        candidates.append("(async () => (\n\(trimmed)\n))")
        candidates.append("(async () => {\n\(source)\n})")
        return candidates.first { isValid($0, in: context) }
    }

    /// Rewrites a whole script file if it only parses inside an async function, keeping its line
    /// numbers. Its top-level declarations are then local to that function, so other scripts and
    /// the Console can't see them.
    /// - Returns: The rewritten script, which evaluates to an async function (which it doesn't
    ///   call) that runs the script, or nil if `source` doesn't need (or can't be fixed by) rewriting
    static func rewriteFile(_ source: String, in context: JSContext) -> String? {
        guard needsRewriting(source, in: context) else { return nil }
        // The opening brace is on the first line so line numbers match the file's
        let wrapped = "(async function(){" + source + "\n})"
        return isValid(wrapped, in: context) ? wrapped : nil
    }

    private static func needsRewriting(_ source: String, in context: JSContext) -> Bool {
        source.contains("await") && !isValid(source, in: context)
    }

    /// Whether `script` parses, without running it or reporting a SyntaxError
    private static func isValid(_ script: String, in context: JSContext) -> Bool {
        let string = unsafe JSStringCreateWithCFString(script as CFString)
        defer { unsafe JSStringRelease(string) }
        return unsafe JSCheckScriptSyntax(context.jsGlobalContextRef, string, nil, 1, nil)
    }
}
