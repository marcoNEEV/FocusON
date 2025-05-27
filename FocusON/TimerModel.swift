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
    // MARK: - Thread-safe, high-precision timer
    private var timerSource: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.yourcompany.FocusON.timer")
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
        timerSource?.cancel()
        timerSource = nil
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
        timerSource?.cancel()
        timerSource = nil
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
    
    /// Creates and schedules the timer on a dedicated queue
    private func scheduleTimer() {
        // Cancel any existing source
        timerSource?.cancel()
        timerSource = DispatchSource.makeTimerSource(queue: timerQueue)
        // Fire every second
        timerSource?.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timerSource?.setEventHandler { [weak self] in
            DispatchQueue.main.async { self?.tick() }
        }
        timerSource?.resume()
    }
    
    deinit {
        // Cancel any active timer source
        timerSource?.cancel()
        timerSource = nil
        
        // Ensure sleep prevention is disabled when TimerModel deallocates
        if let appDelegate = NSApp.delegate as? AppDelegate, appDelegate.preventSleepEnabled {
            print("⚠️ TimerModel deinit - disabling sleep prevention")
            sleepGuard.end()
        }
    }
} 