import Foundation
import Testing
@testable import Hammerspoon_2

@Suite("File evaluation exceptions", .serialized)
@MainActor
struct JSEngineEvaluationTests {
    @Test func partialExecutionSurvivesAndLaterEvaluationRecovers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hs-evaluation-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("init.js")
        let engine = JSEngine()
        try engine.resetContext()
        defer { engine.shutdown() }
        try "globalThis.beforeFailure = 42; throw new Error('expected failure');".write(to: file, atomically: true, encoding: .utf8)
        do {
            try engine.evalFromURL(file)
            Issue.record("File evaluation should throw")
        } catch {
            #expect(error.localizedDescription.contains(file.path))
            #expect(error.localizedDescription.contains("expected failure"))
        }
        #expect(engine.hasContext())
        #expect(engine.eval("beforeFailure") as? Int == 42)
        try "globalThis.recovered = true;".write(to: file, atomically: true, encoding: .utf8)
        try engine.evalFromURL(file)
        #expect(engine.eval("recovered") as? Bool == true)
    }

    @Test func syntaxErrorThrowsWithoutExecuting() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hs-syntax-\(UUID()).js")
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = JSEngine()
        try engine.resetContext()
        defer { engine.shutdown() }
        try "globalThis.shouldNotExecute = true; {{{ syntax !!!".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try engine.evalFromURL(file) }
        #expect(engine.eval("typeof shouldNotExecute === 'undefined'") as? Bool == true)
    }
}
