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
    /// `const`/`let`/`var` statement declaring plain names (`const a = 1, b = await f()`) declares
    /// them as global `var`s instead, so later input can use them.
    /// - Returns: The rewritten script, or nil if `source` doesn't need (or can't be fixed by) rewriting
    static func rewriteConsoleInput(_ source: String, in context: JSContext) -> String? {
        guard needsRewriting(source, in: context) else { return nil }

        // Without any trailing comment or final semicolon, so it can be wrapped in brackets
        let chars = Array(source)
        let outline = Outline(chars)
        var end = outline.codeEnd
        if outline.semicolons.last == end - 1 {
            end -= 1
        }
        let code = chars[..<end]

        var candidates: [String] = []
        if let declaration = globalDeclaration(code, outline: outline) {
            candidates.append(declaration)
        }
        candidates.append("(async () => (\n\(String(code))\n))")
        candidates.append("(async () => {\n\(source)\n})")
        return candidates.first { isValid($0, in: context) }
    }

    /// `const a = 1, b = await f()` as `var a, b; (async () => { a = (1); b = (await f()); })`, or nil
    /// if `code` isn't a single declaration of plain names (destructuring isn't supported)
    private static func globalDeclaration(_ code: ArraySlice<Character>, outline: Outline) -> String? {
        guard !outline.semicolons.contains(where: { $0 < code.endIndex }) else { return nil }
        let text = String(code)
        guard let keyword = text.firstMatch(of: #/^\s*(?:const|let|var)\s+/#) else { return nil }
        let start = code.startIndex + text[..<keyword.range.upperBound].count

        var names: [String] = []
        var assignments: [String] = []
        let separators = [start - 1] + outline.commas.filter { $0 >= start && $0 < code.endIndex } + [code.endIndex]
        for (from, to) in zip(separators, separators.dropFirst()) {
            let part = String(code[(from + 1)..<to])
            guard let match = part.wholeMatch(of: #/\s*([A-Za-z_$][\w$]*)\s*(?:=(?!=)([\s\S]*))?/#) else {
                return nil
            }
            names.append(String(match.1))
            if let value = match.2 {
                // The newlines keep a // comment in the value from swallowing the closing bracket
                assignments.append("\(match.1) = (\n\(value)\n);")
            }
        }
        return "var \(names.joined(separator: ", ")); (async () => { \(assignments.joined(separator: " ")) })"
    }

    /// Where a script's commas and semicolons outside brackets, strings and comments are, and where
    /// its code ends, before any trailing comments and whitespace. Regex literals aren't recognised,
    /// so one containing quotes or brackets can mislead this. The rewrite then fails to parse, or
    /// isn't as helpful, but the script still runs.
    private struct Outline {
        var commas: [Int] = []
        var semicolons: [Int] = []
        var codeEnd = 0

        init(_ chars: [Character]) {
            var depth = 0
            // The bracket depth at which each enclosing template literal's ${ was opened
            var templateDepths: [Int] = []
            var i = 0

            // Moves i to the closing backtick of the template literal i is in, or to the { of its
            // next ${, which is then entered
            func skipTemplateText() {
                while i < chars.count && chars[i] != "`" {
                    if chars[i] == "\\" {
                        i += 1
                    } else if chars[i] == "$" && i + 1 < chars.count && chars[i + 1] == "{" {
                        i += 1
                        templateDepths.append(depth)
                        depth += 1
                        return
                    }
                    i += 1
                }
            }

            while i < chars.count {
                let char = chars[i]
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                switch char {
                case "/" where next == "/":
                    while i < chars.count && !chars[i].isNewline { i += 1 }
                    continue
                case "/" where next == "*":
                    i += 2
                    while i < chars.count && !(chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/") { i += 1 }
                    i += 2
                    continue
                case "\"", "'":
                    // Leaves i at the closing quote
                    i += 1
                    while i < chars.count && chars[i] != char {
                        if chars[i] == "\\" { i += 1 }
                        i += 1
                    }
                case "`":
                    i += 1
                    skipTemplateText()
                case "}" where templateDepths.last == depth - 1:
                    // The end of a ${...}, back into its template literal's text
                    depth -= 1
                    templateDepths.removeLast()
                    i += 1
                    skipTemplateText()
                case "(", "[", "{": depth += 1
                case ")", "]", "}": depth -= 1
                case "," where depth == 0: commas.append(i)
                case ";" where depth == 0: semicolons.append(i)
                default: break
                }
                if !char.isWhitespace {
                    codeEnd = min(i + 1, chars.count)
                }
                i += 1
            }
        }
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
