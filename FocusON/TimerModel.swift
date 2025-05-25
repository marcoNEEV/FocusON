import Foundation
import AppKit

// MARK: - TimerState
enum TimerState {
    case notStarted
    case running
    case paused
}

// MARK: - TimerModel
class TimerModel {
    var phases: [Phase]
    private(set) var currentPhaseIndex: Int = 0
    private(set) var countdownSeconds: Int = 0
    private(set) var timerState: TimerState = .notStarted
    private var timer: Timer?
    // Add sleep-guard instance
    let sleepGuard = SleepGuard()
    
    // Called every second or whenever a state changes
    var updateCallback: (() -> Void)?
    // Called at the end of each phase
    var phaseTransitionCallback: (() -> Void)?
    
    init(phases: [Phase]) {
        self.phases = phases
    }
    
    /// Starts the timer from the beginning of the first phase
    func start() {
        currentPhaseIndex = 0
        countdownSeconds = phases[currentPhaseIndex].duration
        timerState = .running
        AppState.shared.updateTimerState(.running)
        if AppState.shared.preventSleep {
            sleepGuard.begin(reason: "Pomodoro focus session")
        }
        scheduleTimer()
        updateCallback?()
    }
    
    /// Pauses the current timer without resetting it
    func pause() {
        timer?.invalidate()
        timer = nil
        timerState = .paused
        AppState.shared.updateTimerState(.paused)
        sleepGuard.end()
        updateCallback?()
    }
    
    /// Resumes the timer from its paused state
    func resume() {
        timerState = .running
        AppState.shared.updateTimerState(.running)
        scheduleTimer()
        updateCallback?()
    }
    
    /// Resets the timer to initial state
    func reset() {
        timer?.invalidate()
        timer = nil
        timerState = .notStarted
        AppState.shared.updateTimerState(.notStarted)
        countdownSeconds = 0
        currentPhaseIndex = 0
        sleepGuard.end()
        updateCallback?()
    }
    
    /// Called every second by the timer to update countdown
    @objc func tick() {
        countdownSeconds -= 1
        if countdownSeconds <= 0 {
            nextPhase()
        }
        updateCallback?()
    }
    
    /// Advances to the next phase in the cycle
    func nextPhase() {
        currentPhaseIndex = (currentPhaseIndex + 1) % phases.count
        countdownSeconds = phases[currentPhaseIndex].duration
        phaseTransitionCallback?()
        updateCallback?()
    }
    
    /// Creates and schedules the timer on the main thread
    private func scheduleTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            // Make sure the timer fires even when scrolling or during other UI interactions
            RunLoop.main.add(self.timer!, forMode: .common)

        }
    }
} 