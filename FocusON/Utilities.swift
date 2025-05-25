import Cocoa

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
