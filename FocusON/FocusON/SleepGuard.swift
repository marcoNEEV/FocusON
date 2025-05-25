import Foundation
import os

private let logger = Logger(subsystem: "com.yourcompany.FocusON", category: "Power")

/// Manages a power assertion to prevent idle-system and display sleep.
final class SleepGuard {
    private var token: NSObjectProtocol?

    /// Begin preventing sleep (call at start of a focus session).
    func begin(reason: String) {
        guard token == nil else { return }
        let options: ProcessInfo.ActivityOptions = [
            .userInitiated,
            .idleSystemSleepDisabled,
            .idleDisplaySleepDisabled
        ]
        token = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
        #if DEBUG
        logger.debug("Preventing idle sleep: \(reason)")
        #endif
    }

    /// End preventing sleep (call at pause, break, or session end).
    func end() {
        guard let t = token else { return }
        ProcessInfo.processInfo.endActivity(t)
        token = nil
        #if DEBUG
        logger.debug("Ended sleep prevention")
        #endif
    }
} 