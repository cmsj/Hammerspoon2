//
//  Timer.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 24/09/2025.
//

import Foundation
import JavaScriptCore

@objc protocol HSTimerAPI: JSExport {
    @objc(every::)
    func every(_ interval: Double, block: JSValue) -> Timer
    @objc func clear()
}

@_documentation(visibility: private)
@objc class HSTimer: NSObject, HSModuleAPI, HSTimerAPI {
    var timers: [Timer:JSValue] = [:]

    var name = "hs.timer"

    override required init() { super.init() }
    func shutdown() {
        clear()
    }
    deinit {
        print("Deinit of \(name)")
    }

    @objc func every(_ interval: Double, block: JSValue) -> Timer {
        let timer = Timer.scheduledTimer(timeInterval: interval,
                                         target: self,
                                         selector: #selector(timerDidFire(_:)),
                                         userInfo: nil,
                                         repeats: true)
        timers[timer] = block
        RunLoop.current.add(timer, forMode: .common)
        return timer
    }

    @objc private func timerDidFire(_ someTimer: Timer) {
        print("*** scheduledTimer block fired")
        if let block = timers[someTimer] {
            block.call(withArguments: [])
        }
    }

    @objc func clear() {
        timers.forEach { $0.0.invalidate() }
        timers = [:]
    }
}
