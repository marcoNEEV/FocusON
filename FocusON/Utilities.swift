import Cocoa
import IOKit.pwr_mgt  // For sleep prevention

// MARK: - Sleep Prevention Globals
var sleepAssertionID: IOPMAssertionID = 0

func enablePreventSleep() -> Bool {
    let reasonForActivity = "Prevent sleep while FocusON is active" as CFString
    let result = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                             IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             reasonForActivity,
                                             &sleepAssertionID)
    return (result == kIOReturnSuccess)
}

func disablePreventSleep() {
    IOPMAssertionRelease(sleepAssertionID)
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