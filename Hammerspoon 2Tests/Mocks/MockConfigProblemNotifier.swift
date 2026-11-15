//
//  MockConfigProblemNotifier.swift
//  Hammerspoon 2Tests
//
//  Created by Claude on 15/11/2026.
//

import Foundation
@testable import Hammerspoon_2

/// Mock implementation of ConfigProblemNotifierProtocol for testing, which records calls instead of posting notifications
class MockConfigProblemNotifier: ConfigProblemNotifierProtocol {
    enum Call: Equatable {
        case notify(ConfigProblem)
        case withdraw
    }

    var calls: [Call] = []

    /// The problems notified about, in order
    var notifiedProblems: [ConfigProblem] {
        calls.compactMap { call in
            if case .notify(let problem) = call { return problem }
            return nil
        }
    }

    func notify(_ problem: ConfigProblem) {
        calls.append(.notify(problem))
    }

    func withdraw() {
        calls.append(.withdraw)
    }
}
