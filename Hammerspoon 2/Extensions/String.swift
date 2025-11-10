//
//  String.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 10/11/2025.
//

import Foundation

extension String {
    func deletingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }
    func loweringFirstLetter() -> String {
        return prefix(1).lowercased() + self.dropFirst()
    }

    mutating func lowerFirstLetter() {
        self = self.loweringFirstLetter()
    }
}
