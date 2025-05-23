import Cocoa
import IOKit.pwr_mgt  // For sleep prevention

// MARK: - Debugging Utilities
/// A single flag to control debug logging
let enableDebugLogging = true

/// Prints a debug message to the console if debug logging is enabled
/// - Parameters:
///   - message: The message to print
///   - file: The file where the log is called from (default: current file)
///   - line: The line number where the log is called from (default: current line)
func debugLog(_ message: String, file: String = #file, line: Int = #line) {
    #if DEBUG
    if enableDebugLogging {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] [\(fileName):\(line)] \(message)")
    }
    #endif
}

// MARK: - UI State Change Logging
// Track the previous state to avoid redundant logging
var lastLoggedTimerState: TimerState?
var lastLoggedShowTimerState: Bool?

/// Logs UI state changes only when they actually change
/// - Parameters:
///   - timerState: Current timer state
///   - showTimer: Current showTimer preference
///   - force: Force logging even if state hasn't changed
func logUIStateChange(timerState: TimerState, showTimer: Bool, force: Bool = false) {
    if force || timerState != lastLoggedTimerState || showTimer != lastLoggedShowTimerState {
        debugLog("🔄 UI State: Timer=\(timerState), ShowTimer=\(showTimer ? "ON" : "OFF")")
        lastLoggedTimerState = timerState
        lastLoggedShowTimerState = showTimer
    }
}

// MARK: - Modal Window Debugging
/// Prints detailed information about modal windows and application state
/// Call this function at key points in modal window lifecycle (open, close, etc.)
func debugModal(_ message: String, window: NSWindow? = nil, file: String = #file, line: Int = #line) {
    let fileName = URL(fileURLWithPath: file).lastPathComponent
    let location = "\(fileName):\(line)"
    
    print("\n📱 MODAL DEBUG [\(location)] - \(message)")
    
    if let window = window {
        print("  Window: \(type(of: window))")
        print("  - Level: \(window.level.rawValue)")
        print("  - Is Key: \(window.isKeyWindow)")
        print("  - Style Mask: \(window.styleMask.rawValue)")
        print("  - Can Become Key: \(window.canBecomeKey)")
        print("  - Is Modal: \(NSApp.modalWindow === window)")
    }
    
    // Log all visible windows
    print("  VISIBLE WINDOWS:")
    for (index, appWindow) in NSApp.windows.enumerated() where appWindow.isVisible {
        print("  \(index). \(type(of: appWindow)): level \(appWindow.level.rawValue), isKey: \(appWindow.isKeyWindow)")
    }
    
    // Log modal session status
    if let modalWindow = NSApp.modalWindow {
        print("  ⚠️ MODAL SESSION ACTIVE: \(type(of: modalWindow))")
    } else {
        print("  ✓ No modal session active")
    }
    
    print("  Active popup: \((NSApp.delegate as? AppDelegate)?.activePopupDescription ?? "Unknown")")
    print("📱 END DEBUG -----------------------------\n")
}

// MARK: - Sleep Prevention Logic
//
// This app uses IOKit to prevent macOS from entering idle system sleep
// when a focus session is active. This ensures that long focus sessions
// don't get interrupted by automatic sleep.
//
// Assertion Type Used:
// - kIOPMAssertionTypePreventUserIdleSystemSleep
//
// Lifecycle:
// - Assertion is created when the timer starts
// - Assertion is released when the timer is paused, reset, or app quits
// - Failsafe: TimerModel calls disablePreventSleep() in deinit
//
// This prevents the common issue of lingering sleep assertions that
// keep the Mac warm or drain battery after app quit.
//
// See also: debugLog(_:) and enableDebugLogging for related log controls.

// MARK: - Sleep Prevention Globals
var sleepAssertionID: IOPMAssertionID = 0

func enablePreventSleep() -> Bool {
    // Release any existing assertion first to avoid having multiple assertions
    if sleepAssertionID != 0 {
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
        debugLog("💤 Released previous sleep assertion")
    }
    
    let reasonForActivity = "Prevent sleep while FocusON is active" as CFString
    
    // Use a more appropriate assertion type that's less CPU-intensive
    // This prevents the system from sleeping but should be more efficient
    let result = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        reasonForActivity,
        &sleepAssertionID
    )
    
    // Log for debugging with clear sleep assertion state
    let success = result == kIOReturnSuccess
    debugLog("💤 Sleep prevention \(success ? "ENABLED" : "FAILED") (ID: \(sleepAssertionID), Result: \(result))")
    
    return success
}

func disablePreventSleep() {
    if sleepAssertionID != 0 {
        let result = IOPMAssertionRelease(sleepAssertionID)
        debugLog("💤 Sleep prevention DISABLED (ID: \(sleepAssertionID), Result: \(result == kIOReturnSuccess ? "Success" : "Failed"))")
        sleepAssertionID = 0
    } else {
        debugLog("💤 No sleep assertion to release")
    }
}

// MARK: - Helper: Extract Editable Focus Text
/// If the label is "FOCUS XXX!", returns "XXX"; otherwise returns the whole string.
func extractEditableFocusText(from fullText: String) -> String {
    let prefix = "FOCUS "
    let suffix = "!"
    if fullText.hasPrefix(prefix) && fullText.hasSuffix(suffix) {
        let start = fullText.index(fullText.startIndex, offsetBy: prefix.count)
        let end = fullText.index(fullText.endIndex, offsetBy: -suffix.count)
        return String(fullText[start..<end])
    }
    return fullText
}

// MARK: - Confirmation Alert
func showConfirmationAlert(title: String, message: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Confirm")
    alert.addButton(withTitle: "Cancel")
    
    // NSAlert's window property isn't immediately available
    // We can set modalPanel level when we run the alert
    
    // The window is created when we call runModal, so debug after
    // The NSAlert window property isn't available until the alert is shown
    let response = alert.runModal()
    debugModal("Confirmation alert ended", window: alert.window)
    
    return (response == .alertFirstButtonReturn)
}

// MARK: - Utility: Create a status bar image
func createStatusBarImage(text: String,
                          backgroundColor: NSColor,
                          textColor: NSColor) -> NSImage {
    let barHeight = NSStatusBar.system.thickness - 6
    let font = NSFont.systemFont(ofSize: 12)
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let textSize = (text as NSString).size(withAttributes: attributes)
    let imageWidth = textSize.width + 12
    let imageHeight = barHeight
    let size = NSSize(width: imageWidth, height: imageHeight)
    
    let image = NSImage(size: size)
    image.lockFocus()
    
    let rect = NSRect(origin: .zero, size: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
    backgroundColor.setFill()
    path.fill()
    
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center
    
    let textAttrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: textColor,
        .font: font,
        .paragraphStyle: paragraphStyle
    ]
    let attrString = NSAttributedString(string: text, attributes: textAttrs)
    let textRect = NSRect(x: 6,
                          y: (imageHeight - textSize.height)/2,
                          width: textSize.width,
                          height: textSize.height)
    attrString.draw(in: textRect)
    
    image.unlockFocus()
    image.isTemplate = false
    return image
} 
