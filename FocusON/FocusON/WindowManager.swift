import AppKit

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var controllers: [String: NSWindowController] = [:]

    /// Show or bring to front the window identified by `key`.
    func showWindow(key: String, controllerFactory: () -> NSWindowController) {
        let controller = controllers[key] ?? {
            let c = controllerFactory()
            controllers[key] = c
            return c
        }()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Present a standard alert with buttons and return the chosen response.
    func showAlert(key: String,
                   title: String,
                   message: String,
                   style: NSAlert.Style = .informational,
                   buttons: [String] = ["OK"],
                   defaultButtonIndex: Int = 0,
                   destructiveButtonIndex: Int? = nil,
                   completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        
        // Add buttons and configure their styling
        for (index, buttonTitle) in buttons.enumerated() {
            let button = alert.addButton(withTitle: buttonTitle)
            
            // Set default button (blue)
            if index == defaultButtonIndex {
                button.hasDestructiveAction = false
                button.keyEquivalent = "\r"  // Make it respond to Return key
            }
            
            // Set destructive styling if specified
            if index == destructiveButtonIndex {
                button.hasDestructiveAction = true
            }
        }
        
        let response = alert.runModal()
        completion?(response)
    }

    /// Present a text-input alert (with defaultText) and return the entered string or nil.
    func showTextInputAlert(key: String,
                            title: String,
                            message: String,
                            defaultText: String,
                            completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        inputField.stringValue = defaultText
        alert.accessoryView = inputField
        let response = alert.runModal()
        let result = (response == .alertFirstButtonReturn) ? inputField.stringValue : nil
        completion(result)
    }

    /// Overload to accept a defaultValue and validator, forwarding to the defaultText version.
    func showTextInputAlert(key: String,
                            title: String,
                            message: String,
                            defaultValue: String,
                            validator: ((String) -> Bool)?,
                            completion: @escaping (String?) -> Void) {
        showTextInputAlert(key: key,
                           title: title,
                           message: message,
                           defaultText: defaultValue) { input in
            guard let input = input, validator?(input) ?? true else {
                completion(nil)
                return
            }
            completion(input)
        }
    }

    /// Present the onboarding window.
    func showOnboardingWindow() {
        showWindow(key: "onboarding") {
            NSWindowController(windowNibName: "OnboardingWindow")
        }
    }

    /// Update the status-item title to reflect the current phase.
    func updateFocusPhaseLabel(_ label: String) {
        if let button = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength).button {
            button.title = label
        }
    }

    /// Close and remove the window for `key`.
    func closeWindow(key: String) {
        controllers[key]?.close()
        controllers.removeValue(forKey: key)
    }
} 