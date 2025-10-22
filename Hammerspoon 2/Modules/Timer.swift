//
//  Timer.swift
//  Hammerspoon 2
//
//  Created by Chris Jones on 24/09/2025.
//

import Foundation
import JavaScriptCore

//// MARK: - Exported API
//
//@objc protocol TimerManagerExports: JSExport {
//    @objc(every::)
//    func every(_ interval: Double, block: JSValue) -> HammerTimer
//    @objc func clear()
//    @objc var description: String { get }
//}
//
//@objc protocol HammerTimerExports: JSExport {
//    @objc var description: String { get }
//    @objc func start()
//    @objc func stop()
//}
//
//// MARK: - HammerTimer
//@objc extension Timer: @retroactive JSExport {}
//@objc extension Timer: @MainActor HammerTimerExports {
//    @objc nonisolated open override var description: String {
//        "lol"
//    }
//    @objc func start() {}
//    @objc func stop() {}
//}
//
//@objc class HammerTimer: NSObject, HammerTimerExports {
//    let id: UUID = UUID()
//    var timer: Timer?
//    let every: Double
//    let block: (Timer) -> Void
//
//    @objc nonisolated override var description: String {
//        "HammerTimer(\(id)): every \(every) seconds"
//    }
//
//    init(every: Double, block: @escaping (Timer) -> Void) {
//        print("*** HAMMERTIMER INIT: \(every) seconds ***")
//        self.every = every
//        self.block = block
//        super.init()
//    }
//
//    @objc func start() {
//        if timer != nil { stop() }
//
//        print("*** STARTING HAMMERTIMER: \(self) ***")
//        timer = Timer.scheduledTimer(timeInterval: every,
//                                     target: self,
//                                     selector: #selector(timerDidFire(_:)),
//                                     userInfo: nil,
//                                     repeats: true)
//        if let timer {
//            RunLoop.current.add(timer, forMode: .common)
//        }
//    }
//
//    @objc private func timerDidFire(_ someTimer: Timer) {
//        print("*** scheduledTimer block fired")
//        block(someTimer)
//    }
//
//    @objc func stop() {
//        print("*** STOPPING HAMMERTIMER: \(self) ***")
//        timer?.invalidate()
//        timer = nil
//    }
//}
//
//// MARK: - HammerTimerManager
//
//@objc class HammerTimerManager: NSObject, TimerManagerExports {
//    let id: UUID = UUID()
//    var timers: [HammerTimer] = []
//
//    @objc nonisolated override var description: String {
//        "HammerTimerManager: \(id)"
//    }
//
//    func new(every: Double, block: @escaping (Timer) -> Void) -> HammerTimer {
//        print("*** HAMMERTIMERMANAGER CREATING NEW TIMER: \(every) seconds ***")
//        let timer = HammerTimer(every: every, block: block)
//        timers.append(timer)
//        return timer
//    }
//
//    @objc func clear() {
//        timers.forEach { $0.stop() }
//        timers = []
//    }
//
//    @objc func every(_ interval: Double, block: JSValue) -> HammerTimer {
//        print("*** HAMMERTIMERMANAGER JS CALLED every for: \(interval) seconds ***")
//        let timer = self.new(every: interval) { t in
//            print("*** IN HAMMERTIMER BLOCK! (\(t.description))***")
//            // call back into JS with the timer object
//            block.call(withArguments: [t])
//        }
//        timer.start()
//        return timer
//    }
//}

@objc protocol HSTimerAPI: JSExport {
    @objc(every::)
    func every(_ interval: Double, block: JSValue) -> Timer
    @objc func clear()
}

@_documentation(visibility: private)
@objc class HSTimer: NSObject, HSModuleAPI, HSTimerAPI {
    var timers: [Timer:JSValue] = [:]

    var name = "hs.timer"

    override required init() {}
    func shutdown() {}
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
