import Cocoa

// MARK: - PhaseType
enum PhaseType {
    case focus
    case relax
}

// MARK: - Phase
struct Phase {
    let duration: Int
    let backgroundColor: NSColor
    let label: String
    let type: PhaseType
}

// MARK: - TimerState
enum TimerState {
    case notStarted
    case running
    case paused
}

// MARK: - TimerModel
class TimerModel {
    var phases: [Phase]
    var currentPhaseIndex: Int = 0
    var countdownSeconds: Int = 0
    var timerState: TimerState = .notStarted
    private var timer: Timer?
    
    // Called every second or whenever a state changes
    var updateCallback: (() -> Void)?
    // Called at the end of each phase
    var phaseTransitionCallback: (() -> Void)?
    
    init(phases: [Phase]) {
        self.phases = phases
    }
    
    func start() {
        currentPhaseIndex = 0
        countdownSeconds = phases[currentPhaseIndex].duration
        timerState = .running
        scheduleTimer()
        updateCallback?()
    }
    
    func pause() {
        timer?.invalidate()
        timer = nil
        timerState = .paused
        updateCallback?()
    }
    
    func resume() {
        timerState = .running
        scheduleTimer()
        updateCallback?()
    }
    
    func reset() {
        timer?.invalidate()
        timer = nil
        timerState = .notStarted
        countdownSeconds = 0
        currentPhaseIndex = 0
        updateCallback?()
    }
    
    @objc func tick() {
        countdownSeconds -= 1
        if countdownSeconds <= 0 {
            nextPhase()
        }
        updateCallback?()
    }
    
    func nextPhase() {
        currentPhaseIndex = (currentPhaseIndex + 1) % phases.count
        countdownSeconds = phases[currentPhaseIndex].duration
        phaseTransitionCallback?()
        updateCallback?()
    }
    
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