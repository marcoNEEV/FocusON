import AppKit
import Cocoa
import CoreText
import IOKit.pwr_mgt  // For sleep prevention
#if os(macOS) && canImport(ServiceManagement)
import ServiceManagement  // For login item persistence on macOS 13.0+
#endif

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    @objc func showInfo() {
        WindowManager.shared.showOnboardingWindow()
    }

    func showPhaseNameInput() {
        WindowManager.shared.showTextInputAlert(
            key: "phaseNameInput",
            title: "Phase Name",
            message: "Enter a name for the phase (max 6 characters)",
            defaultValue: "",
            validator: { text in text.count <= 6 },
            completion: { newText in
                if let newText = newText {
                    WindowManager.shared.updateFocusPhaseLabel(newText)
                }
            })
    }

    func showPhaseTimesInput() {
        WindowManager.shared.showAlert(
            key: "phaseTimesInput",
            title: "Timer Settings",
            message: "Configure your timer settings",
            style: .informational,
            buttons: ["OK", "Cancel"]) { response in
                if response == .alertFirstButtonReturn {
                    // Handle OK button
                }
            }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WindowManager.shared.showAlert(
            key: "terminate",
            title: "Confirm Termination",
            message: "Are you sure you want to quit?",
            style: .warning,
            buttons: ["OK", "Cancel"]) { response in
                if response == .alertFirstButtonReturn {
                    NSApplication.shared.reply(toApplicationShouldTerminate: true)
                } else {
                    NSApplication.shared.reply(toApplicationShouldTerminate: false)
                }
            }
        return .terminateLater
    }
} 