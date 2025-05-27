import Foundation
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    /// Current app timer state (notStarted, running, paused)
    @Published var timerState: TimerState = .notStarted
    
    /// Whether to show the floating timer UI
    @Published var showTimer: Bool = true
    
    /// Persisted user preference: prevent sleep during focus sessions
    @AppStorage("preventSleepEnabled") var preventSleepEnabled: Bool = false
} 