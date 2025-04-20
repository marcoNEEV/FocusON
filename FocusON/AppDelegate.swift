import Cocoa
import IOKit.pwr_mgt  // For sleep prevention
#if os(macOS) && canImport(ServiceManagement)
import ServiceManagement  // For login item persistence on macOS 13.0+
#endif

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

// MARK: - "Row View" for a uniform grid approach
/// A row in the menu with left-aligned text. Optionally clickable, optionally closes menu.
class MenuRowView: NSView {
    private weak var target: AnyObject?
    private let action: Selector?
    private let closesMenu: Bool
    private let isEnabled: Bool
    private let textProvider: () -> String
    
    private var label: NSTextField!
    
    init(isEnabled: Bool,
         closesMenu: Bool,
         target: AnyObject?,
         action: Selector?,
         textProvider: @escaping () -> String) {
        
        self.isEnabled = isEnabled
        self.closesMenu = closesMenu
        self.target = target
        self.action = action
        self.textProvider = textProvider
        
        // Menu item dimensions
        let _: CGFloat = 1.618
        let width: CGFloat = 200
        let height: CGFloat = 22  // Standard menu item height
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        
        // Label with fixed width to prevent shifting
        label = NSTextField(frame: NSRect(x: 8, y: 1, width: width - 10, height: height - 2))
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        
        updateLabel()
        addSubview(label)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }

        // 1) If this row should close the menu, do so first
        if closesMenu {
            if let menu = self.enclosingMenuItem?.menu {
                menu.cancelTracking()
            }
        }

        // 2) Now perform the action (show the alert, etc.)
        if let action = action, let tgt = target {
            tgt.performSelector(onMainThread: action, with: nil, waitUntilDone: true)
        }

        // 3) Update the label text
        updateLabel()
    }
    
    private func updateLabel() {
        let text = textProvider()
        let color: NSColor
        
        if !isEnabled {
            color = .gray
        } else {
            color = .labelColor
        }
        
        let attr = NSAttributedString(string: text, attributes: [.foregroundColor: color])
        label.attributedStringValue = attr
    }
}

// MARK: - Make a custom row item
func makeMenuRowItem(isEnabled: Bool,
                     closesMenu: Bool,
                     target: AnyObject?,
                     action: Selector?,
                     textProvider: @escaping () -> String) -> NSMenuItem {
    
    let item = NSMenuItem()
    let row = MenuRowView(isEnabled: isEnabled,
                          closesMenu: closesMenu,
                          target: target,
                          action: action,
                          textProvider: textProvider)
    item.view = row
    return item
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

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSWindowDelegate {
    
    var statusItem: NSStatusItem?
    var timerModel: TimerModel!
    var preventSleepEnabled = false
    var showTimerEnabled = false
    private var onboardingController: OnboardingWindowController?
    
    let initialBackgroundColor = NSColor(calibratedRed: 173/255.0,
                                         green: 216/255.0,
                                         blue: 230/255.0,
                                         alpha: 1.0)
    
    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setting up app persistence is optional - don't let it interfere with app startup
        if #available(macOS 13.0, *) {
            // Only try to set up auto-launch on macOS 13.0+
            DispatchQueue.global(qos: .background).async { [weak self] in
                self?.addAppToLoginItems()
            }
        }
        
        // Initialize status item - this is the core functionality
        setupStatusItem()
    }
    
    // Set up the status bar item and timer model
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else {
            print("ERROR: No status bar button.")
            return
        }
        
        timerModel = TimerModel(phases: buildPhases())
        timerModel.updateCallback = { [weak self] in
            self?.updateUI()
        }
        timerModel.phaseTransitionCallback = { [weak self] in
            self?.playGongSound()
        }
        
        // Initial standby
        button.image = createStatusBarImage(text: "FOCUS·ON",
                                            backgroundColor: initialBackgroundColor,
                                            textColor: .darkGray)
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    // MARK: - Build Phases
    func buildPhases() -> [Phase] {
        let focusDuration = 25 * 60
        let shortBreak    = 5  * 60
        let longBreak     = 21 * 60
        
        var list = [Phase]()
        for i in 0..<4 {
            list.append(Phase(duration: focusDuration,
                              backgroundColor: .red,
                              label: "FOCUS ON!",
                              type: .focus))
            if i < 3 {
                list.append(Phase(duration: shortBreak,
                                  backgroundColor: .systemPink,
                                  label: "RELAX",
                                  type: .relax))
            } else {
                list.append(Phase(duration: longBreak,
                                  backgroundColor: .systemPink,
                                  label: "RELAX!",
                                  type: .relax))
            }
        }
        return list
    }
    
    // MARK: - Status Item Click
    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Show custom "grid" menu
            let menu = buildCustomMenu()
            
            // Get screen location of status item
            if let button = statusItem?.button, let window = button.window {
                // Calculate the screen position of the status item button
                let locationInWindow = button.convert(NSPoint(x: 0, y: 0), to: nil)
                let locationInScreen = window.convertPoint(toScreen: locationInWindow)
                
                // Position directly below the status item
                // Use 0 on the y-axis for bottom alignment
                let menuOrigin = NSPoint(x: locationInScreen.x, y: locationInScreen.y)
                
                // This uses a direct positioning approach which works on macOS
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
            }
            return
        }
        
        // Left-click: start, pause, resume
        switch timerModel.timerState {
        case .notStarted:
            timerModel.start()
        case .running:
            timerModel.pause()
            updateUI()
        case .paused:
            timerModel.resume()
        }
    }
    
    // MARK: - Build the "Grid" Menu
    func buildCustomMenu() -> NSMenu {
        let menu = NSMenu()
        
        // NSMenu doesn't have a window property that can be accessed directly
        // Semi-transparency will be handled by system appearance
        
        let isInActiveState = (timerModel.timerState == .running || timerModel.timerState == .paused)
        
        // 1) Terminate App - always white/active
        menu.addItem(makeMenuRowItem(isEnabled: true,
                                     closesMenu: true,
                                     target: self,
                                     action: #selector(terminateApp),
                                     textProvider: { "Terminate App" }))
        
        // 2) Edit Focus Time - white in standby, gray in running/pause
        menu.addItem(makeMenuRowItem(isEnabled: !isInActiveState,
                                     closesMenu: true,
                                     target: self,
                                     action: #selector(showPhaseTimesInput),
                                     textProvider: { "Edit Focus Time" }))
        
        // 3) Edit Focus Text - gray in standby, white in running/pause
        let currentPhase = timerModel.phases[timerModel.currentPhaseIndex]
        let isFocusPhase = currentPhase.type == .focus
        menu.addItem(makeMenuRowItem(isEnabled: isInActiveState && isFocusPhase,
                                     closesMenu: true,
                                     target: self,
                                     action: #selector(showFocusTextInput),
                                     textProvider: { "Edit Focus Text" }))
        
        // 4) Show Timer - gray in standby, white in running/pause
        menu.addItem(makeMenuRowItem(isEnabled: isInActiveState,
                                     closesMenu: false,
                                     target: self,
                                     action: #selector(toggleShowTimer),
                                     textProvider: {
            // Fixed width text using a constant-width format
            return String(format: "Show Timer %@", self.showTimerEnabled ? "(ON) " : "(OFF)")
        }))
        
        // 5) Prevent Sleep - gray in standby, white in running/pause
        menu.addItem(makeMenuRowItem(isEnabled: isInActiveState,
                                     closesMenu: false,
                                     target: self,
                                     action: #selector(togglePreventSleep),
                                     textProvider: {
            // Fixed width text using a constant-width format
            return String(format: "Prevent Sleep %@", self.preventSleepEnabled ? "(ON) " : "(OFF)")
        }))
        
        // 6) Focus Phase X/4 - always gray/inactive
        menu.addItem(makeMenuRowItem(isEnabled: false,
                                     closesMenu: false,
                                     target: nil,
                                     action: nil,
                                     textProvider: { self.currentCycleLabel() }))
        
        // 7) Reset App - gray in standby, white in running/pause
        menu.addItem(makeMenuRowItem(isEnabled: isInActiveState,
                                     closesMenu: true,
                                     target: self,
                                     action: #selector(resetPhases),
                                     textProvider: { "Reset App" }))
        
        // 8) Info - always white/active
        menu.addItem(makeMenuRowItem(isEnabled: true,
                                     closesMenu: true,
                                     target: self,
                                     action: #selector(showInfo),
                                     textProvider: { "Info" }))
        
        return menu
    }
    
    // MARK: - UI Update
    func updateUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }
            let phase = self.timerModel.phases[self.timerModel.currentPhaseIndex]
            
            switch self.timerModel.timerState {
            case .running:
                let mins = Int(ceil(Double(self.timerModel.countdownSeconds)/60.0))
                let text = self.showTimerEnabled ? "\(mins): \(phase.label)" : phase.label
                button.image = createStatusBarImage(text: text,
                                                    backgroundColor: phase.backgroundColor,
                                                    textColor: .white)
            case .paused:
                let text = self.showTimerEnabled ? "II: \(phase.label)" : phase.label
                button.image = createStatusBarImage(text: text,
                                                    backgroundColor: .darkGray,
                                                    textColor: .white)
            case .notStarted:
                button.image = createStatusBarImage(text: "FOCUS·ON",
                                                    backgroundColor: self.initialBackgroundColor,
                                                    textColor: .darkGray)
            }
        }
    }
    
    // MARK: - Current Cycle Label
    func currentCycleLabel() -> String {
        // In standby mode, show "x/4"
        if timerModel.timerState == .notStarted {
            return "Focus Phase x/4"
        }
        
        let focusIndices: [Int] = [0,2,4,6]
        let breakIndices: [Int] = [1,3,5,7]
        let i = timerModel.currentPhaseIndex
        
        if let fPos = focusIndices.firstIndex(of: i) {
            return "Focus Phase \(fPos + 1)/4"
        } else if let bPos = breakIndices.firstIndex(of: i) {
            return "Break Phase \(bPos + 1)/4"
        }
        return "Cycle ???"
    }
    
    // MARK: - Show Focus Text Input
    @objc func showFocusTextInput() {
        NSApp.activate(ignoringOtherApps: true)
        
        let focusPhase = timerModel.phases.first { $0.type == .focus }?.label ?? "FOCUS ON!"
        let editable = extractEditableFocusText(from: focusPhase)
        
        let (alert, inputField) = buildFocusTextAlert(currentText: editable)
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            updateFocusPhaseLabel(with: inputField.stringValue)
        }
    }
    
    private func buildFocusTextAlert(currentText: String) -> (NSAlert, NSTextField) {
        let alert = NSAlert()
        alert.messageText = "Edit the focus text"
        alert.informativeText = "You can edit the 'ON' in the text (max 6 chars)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let inputField = NSTextField(frame: NSRect(x:0, y:0, width:200, height:24))
        inputField.delegate = self
        inputField.stringValue = currentText
        inputField.tag = 2001
        alert.accessoryView = inputField
        
        return (alert, inputField)
    }
    
    func updateFocusPhaseLabel(with newText: String) {
        for (i, ph) in timerModel.phases.enumerated() {
            if ph.type == .focus {
                let updatedLabel = "FOCUS \(newText)!"
                timerModel.phases[i] = Phase(duration: ph.duration,
                                             backgroundColor: ph.backgroundColor,
                                             label: updatedLabel,
                                             type: .focus)
            }
        }
        updateUI()
    }
    
    // MARK: - Show Phase Times
    @objc func showPhaseTimesInput() {
        NSApp.activate(ignoringOtherApps: true)
        
        let cFocus = timerModel.phases[0].duration / 60
        let cShort = timerModel.phases[1].duration / 60
        let cLong  = timerModel.phases[7].duration / 60
        
        let (alert, fields) = buildPhaseTimesAlert(currentFocus: cFocus,
                                                   currentShort: cShort,
                                                   currentLong: cLong)
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            guard fields.count == 3 else { return }
            let fField = fields[0]
            let sField = fields[1]
            let lField = fields[2]
            
            let fTime = Int(fField.stringValue) ?? cFocus
            let sTime = Int(sField.stringValue) ?? cShort
            let lTime = Int(lField.stringValue) ?? cLong
            
            let newFocus = fTime * 60
            let newShort = sTime * 60
            let newLong  = lTime * 60
            
            for (i, ph) in timerModel.phases.enumerated() {
                switch ph.type {
                case .focus:
                    timerModel.phases[i] = Phase(duration: newFocus,
                                                 backgroundColor: .red,
                                                 label: "FOCUS ON!",
                                                 type: .focus)
                case .relax:
                    let updatedDur = (i == 7) ? newLong : newShort
                    let updatedLbl = (i == 7) ? "RELAX!" : "RELAX"
                    timerModel.phases[i] = Phase(duration: updatedDur,
                                                 backgroundColor: .systemPink,
                                                 label: updatedLbl,
                                                 type: .relax)
                }
            }
            updateUI()
        }
    }
    
    private func buildPhaseTimesAlert(currentFocus: Int,
                                      currentShort: Int,
                                      currentLong: Int) -> (NSAlert, [NSTextField]) {
        let alert = NSAlert()
        alert.messageText = "Timer Settings"
        alert.informativeText = "Set the duration (in minutes) for each phase."
        alert.alertStyle = .informational
        
        // Create a blue "Confirm" button
        let confirmButton = alert.addButton(withTitle: "Confirm")
        confirmButton.keyEquivalent = "\r" // Return key
        let buttonCell = confirmButton.cell as? NSButtonCell
        buttonCell?.backgroundColor = NSColor.systemBlue
        
        alert.addButton(withTitle: "Cancel")
        
        // Golden ratio for landscape container (1.618:1)
        let containerWidth: CGFloat = 380
        let containerHeight: CGFloat = 160
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        
        // Field parameters
        let fieldWidth: CGFloat = 80
        let fieldHeight: CGFloat = 30
        let spacing: CGFloat = 60
        let totalWidth = 3 * fieldWidth + 2 * spacing
        let marginX = (containerWidth - totalWidth) / 2
        let marginY: CGFloat = 35
        
        // Labels
        let labelWidth: CGFloat = 90
        let labelHeight: CGFloat = 20
        
        // Focus label and field
        let focusLabel = NSTextField(frame: NSRect(x: marginX + (fieldWidth - labelWidth)/2, y: containerHeight - marginY - labelHeight, 
                                                  width: labelWidth, height: labelHeight))
        focusLabel.isEditable = false
        focusLabel.isBordered = false
        focusLabel.drawsBackground = false
        focusLabel.stringValue = "Focus"
        focusLabel.alignment = .center
        focusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        container.addSubview(focusLabel)
        
        let fField = NSTextField(frame: NSRect(x: marginX, y: containerHeight - marginY - labelHeight - fieldHeight - 5, 
                                              width: fieldWidth, height: fieldHeight))
        fField.alignment = .center
        fField.delegate = self
        fField.tag = 1001
        fField.stringValue = "\(currentFocus)"
        fField.font = NSFont.systemFont(ofSize: 14)
        container.addSubview(fField)
        
        // Short Break label and field
        let shortLabel = NSTextField(frame: NSRect(x: marginX + fieldWidth + spacing + (fieldWidth - labelWidth)/2, 
                                                  y: containerHeight - marginY - labelHeight, 
                                                  width: labelWidth, height: labelHeight))
        shortLabel.isEditable = false
        shortLabel.isBordered = false
        shortLabel.drawsBackground = false
        shortLabel.stringValue = "Short Break"
        shortLabel.alignment = .center
        shortLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        container.addSubview(shortLabel)
        
        let sField = NSTextField(frame: NSRect(x: marginX + fieldWidth + spacing, 
                                              y: containerHeight - marginY - labelHeight - fieldHeight - 5, 
                                              width: fieldWidth, height: fieldHeight))
        sField.alignment = .center
        sField.delegate = self
        sField.tag = 1001
        sField.stringValue = "\(currentShort)"
        sField.font = NSFont.systemFont(ofSize: 14)
        container.addSubview(sField)
        
        // Long Break label and field
        let longLabel = NSTextField(frame: NSRect(x: marginX + 2 * (fieldWidth + spacing) + (fieldWidth - labelWidth)/2, 
                                                 y: containerHeight - marginY - labelHeight, 
                                                 width: labelWidth, height: labelHeight))
        longLabel.isEditable = false
        longLabel.isBordered = false
        longLabel.drawsBackground = false
        longLabel.stringValue = "Long Break"
        longLabel.alignment = .center
        longLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        container.addSubview(longLabel)
        
        let lField = NSTextField(frame: NSRect(x: marginX + 2 * (fieldWidth + spacing), 
                                              y: containerHeight - marginY - labelHeight - fieldHeight - 5, 
                                              width: fieldWidth, height: fieldHeight))
        lField.alignment = .center
        lField.delegate = self
        lField.tag = 1001
        lField.stringValue = "\(currentLong)"
        lField.font = NSFont.systemFont(ofSize: 14)
        container.addSubview(lField)
        
        alert.accessoryView = container
        return (alert, [fField, sField, lField])
    }
    
    // MARK: - Sound
    func playGongSound() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let gongURL = Bundle.main.url(forResource: "tibetan_Gong", withExtension: "wav") else {
                print("ERROR: Could not find tibetan_Gong.wav.")
                return
            }
            
            DispatchQueue.main.async {
                if let gongSound = NSSound(contentsOf: gongURL, byReference: false) {
                    gongSound.play()
                } else {
                    print("ERROR: Could not load tibetan_Gong.wav sound.")
                }
            }
        }
    }
    
    // MARK: - Sleep Toggle
    @objc func togglePreventSleep() {
        preventSleepEnabled.toggle()
        if preventSleepEnabled {
            if !enablePreventSleep() {
                print("Failed to enable Prevent Sleep")
                preventSleepEnabled = false
            }
        } else {
            disablePreventSleep()
        }
    }
    
    // MARK: - Show Timer Toggle
    @objc func toggleShowTimer() {
        showTimerEnabled.toggle()
        updateUI()
    }
    
    // MARK: - Reset / Terminate
    @objc func resetPhases() {
        timerModel.reset()
    }
    
    @objc func terminateApp() {
        NSApp.activate(ignoringOtherApps: true)
        let confirmed = showConfirmationAlert(title: "Confirm Termination", message: "")
        if confirmed {
            NSApp.terminate(nil)
        }
    }
    
    // MARK: - NSTextFieldDelegate
    // Add a property in AppDelegate:
    var originalTextFieldValues = [ObjectIdentifier: String]()
    
    // Store the original value when editing begins:
    func controlTextDidBeginEditing(_ notification: Notification) {
        if let tf = notification.object as? NSTextField {
            originalTextFieldValues[ObjectIdentifier(tf)] = tf.stringValue
        }
    }
    
    // Remove the stored value when editing ends:
    func controlTextDidEndEditing(_ notification: Notification) {
        if let tf = notification.object as? NSTextField {
            originalTextFieldValues.removeValue(forKey: ObjectIdentifier(tf))
        }
    }
    
    func controlTextDidChange(_ notification: Notification) {
        guard let tf = notification.object as? NSTextField else { return }
        if tf.tag == 1001 {
            var newText = tf.stringValue.filter { $0.isNumber }
            if newText.count > 2 {
                newText = String(newText.prefix(2))
            }
            if let n = Int(newText), n >= 1 && n <= 99 {
                tf.stringValue = newText
            } else {
                // Revert immediately to the original value if input is invalid.
                if let original = originalTextFieldValues[ObjectIdentifier(tf)] {
                    tf.stringValue = original
                } else {
                    tf.stringValue = ""
                }
            }
        } else if tf.tag == 2001 {
            if tf.stringValue.count > 6 {
                tf.stringValue = String(tf.stringValue.prefix(6))
            }
        }
    }
    
    // MARK: - App Persistence
    func addAppToLoginItems() {
        #if os(macOS)
        if #available(macOS 13.0, *) {
            // For macOS 13.0+ (Ventura and newer)
            do {
                try SMAppService.mainApp.register()
                print("App registered as login item using SMAppService")
            } catch {
                print("Failed to register app as login item: \(error.localizedDescription)")
            }
        } else {
            // For macOS 12.0 (Monterey)
            // Skip auto-launch functionality for older macOS versions
            // This could be implemented with AppleScript or other alternatives if needed
            print("Auto-launch at login not implemented for macOS 12.0")
            
            // Note: For older macOS versions, users can manually add the app 
            // to login items through System Preferences > Users & Groups > Login Items
        }
        #endif
    }
    
    // MARK: - Show Info
    @objc func showInfo() {
        NSApp.activate(ignoringOtherApps: true)
        
        // Check if onboarding window is already open
        if onboardingController != nil {
            if let window = onboardingController?.window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            return
        }
        
        // Create and show the onboarding window
        onboardingController = OnboardingWindowController.create()
        onboardingController?.window?.delegate = self
        
        // Center the window on screen
        if let window = onboardingController?.window {
            window.center()
            
            // Position it in the middle of the screen, accounting for the menu bar
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let windowRect = window.frame
                let newOrigin = NSPoint(
                    x: screenRect.midX - windowRect.width / 2,
                    y: screenRect.midY - windowRect.height / 2
                )
                window.setFrameOrigin(newOrigin)
            }
            
            // Make the window visible
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        
        onboardingController?.showWindow(nil)
    }
    
    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        // Clean up reference when window closes
        if notification.object as? NSWindow == onboardingController?.window {
            onboardingController = nil
        }
    }
}

// MARK: - OnboardingWindowController
class OnboardingWindowController: NSWindowController {
    private var currentImageIndex = 0
    private var onboardingImages: [NSImage] = []
    private var imageView: NSImageView!
    private var leftButton: NSButton!
    private var rightButton: NSButton!
    
    // Convenience initializer
    static func create() -> OnboardingWindowController {
        // Size window to 3/5 of previous size (now roughly 1/3 of typical laptop screen)
        let width: CGFloat = 920
        let height: CGFloat = 575
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FocusON Onboarding"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.isMovableByWindowBackground = true
        
        let controller = OnboardingWindowController(window: window)
        // Load content immediately to fix empty window issue
        controller.loadContent()
        return controller
    }
    
    // New method to load content before window is shown
    private func loadContent() {
        // Load onboarding images
        loadOnboardingImages()
        
        guard let window = window, let contentView = window.contentView else { return }
        
        // Configure the window and setup views
        setupViews(in: contentView)
        
        // Update with first image
        updateUI()
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        // Window is already loaded in create() method
    }
    
    private func loadOnboardingImages() {
        // Placeholder - in a real app, you'd bundle actual onboarding images
        // For now, we'll create colored rectangles as placeholders
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange]
        
        for (index, color) in colors.enumerated() {
            let image = NSImage(size: NSSize(width: 800, height: 500))
            image.lockFocus()
            
            // Draw colored background
            color.setFill()
            NSRect(x: 0, y: 0, width: 800, height: 500).fill()
            
            // Draw text
            let text = "Onboarding Screen \(index + 1)"
            let font = NSFont.systemFont(ofSize: 36, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: font
            ]
            
            let textSize = (text as NSString).size(withAttributes: attributes)
            let textPoint = NSPoint(
                x: (800 - textSize.width) / 2,
                y: (500 - textSize.height) / 2
            )
            
            (text as NSString).draw(at: textPoint, withAttributes: attributes)
            
            image.unlockFocus()
            onboardingImages.append(image)
        }
    }
    
    private func setupViews(in contentView: NSView) {
        // Clear any existing subviews
        contentView.subviews.forEach { $0.removeFromSuperview() }
        
        // Apply background color
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // Create image view
        imageView = NSImageView(frame: contentView.bounds)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        
        // Create left arrow button
        leftButton = NSButton(frame: NSRect(x: 20, y: contentView.bounds.height / 2 - 25, width: 50, height: 50))
        leftButton.bezelStyle = .shadowlessSquare
        leftButton.isBordered = false
        leftButton.title = "◀"
        leftButton.font = NSFont.systemFont(ofSize: 24, weight: .medium)
        leftButton.contentTintColor = .white
        leftButton.target = self
        leftButton.action = #selector(previousImage(_:))
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        leftButton.wantsLayer = true
        leftButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        leftButton.layer?.cornerRadius = 25
        contentView.addSubview(leftButton)
        
        // Create right arrow button
        rightButton = NSButton(frame: NSRect(x: contentView.bounds.width - 70, y: contentView.bounds.height / 2 - 25, width: 50, height: 50))
        rightButton.bezelStyle = .shadowlessSquare
        rightButton.isBordered = false
        rightButton.title = "▶"
        rightButton.font = NSFont.systemFont(ofSize: 24, weight: .medium)
        rightButton.contentTintColor = .white
        rightButton.target = self
        rightButton.action = #selector(nextImage(_:))
        rightButton.translatesAutoresizingMaskIntoConstraints = false
        rightButton.wantsLayer = true
        rightButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        rightButton.layer?.cornerRadius = 25
        contentView.addSubview(rightButton)
        
        // Create close button
        let closeButton = NSButton(frame: NSRect(x: contentView.bounds.width - 70, y: contentView.bounds.height - 70, width: 40, height: 40))
        closeButton.bezelStyle = .shadowlessSquare
        closeButton.isBordered = false
        closeButton.title = "✕"
        closeButton.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(close(_:))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        closeButton.layer?.cornerRadius = 20
        contentView.addSubview(closeButton)
        
        // Add page indicator
        let pageIndicator = NSTextField(frame: .zero)
        pageIndicator.isEditable = false
        pageIndicator.isBordered = false
        pageIndicator.drawsBackground = false
        pageIndicator.textColor = .white
        pageIndicator.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        pageIndicator.stringValue = "1 / \(onboardingImages.count)"
        pageIndicator.translatesAutoresizingMaskIntoConstraints = false
        pageIndicator.tag = 100 // For identifying and updating later
        pageIndicator.alignment = .center
        pageIndicator.backgroundColor = NSColor.black.withAlphaComponent(0.3)
        pageIndicator.wantsLayer = true
        pageIndicator.layer?.cornerRadius = 10
        contentView.addSubview(pageIndicator)
        
        // Set constraints
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            leftButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            leftButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leftButton.widthAnchor.constraint(equalToConstant: 50),
            leftButton.heightAnchor.constraint(equalToConstant: 50),
            
            rightButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rightButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            rightButton.widthAnchor.constraint(equalToConstant: 50),
            rightButton.heightAnchor.constraint(equalToConstant: 50),
            
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            
            pageIndicator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            pageIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pageIndicator.widthAnchor.constraint(equalToConstant: 100),
            pageIndicator.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    private func updateUI() {
        if !onboardingImages.isEmpty {
            imageView.image = onboardingImages[currentImageIndex]
            
            // Update page indicator
            if let pageIndicator = window?.contentView?.viewWithTag(100) as? NSTextField {
                pageIndicator.stringValue = "\(currentImageIndex + 1) / \(onboardingImages.count)"
            }
        }
        
        // For first slide, make left button wrap to last slide
        if currentImageIndex == 0 {
            leftButton.isEnabled = true
            leftButton.action = #selector(wrapToLastImage(_:))
        } else {
            leftButton.isEnabled = true
            leftButton.action = #selector(previousImage(_:))
        }
        
        rightButton.isEnabled = currentImageIndex < onboardingImages.count - 1
    }
    
    @objc func previousImage(_ sender: NSButton) {
        if currentImageIndex > 0 {
            currentImageIndex -= 1
            updateUI()
        }
    }
    
    @objc func nextImage(_ sender: NSButton) {
        if currentImageIndex < onboardingImages.count - 1 {
            currentImageIndex += 1
            updateUI()
        }
    }
    
    @objc func close(_ sender: NSButton) {
        window?.close()
        
        // Notify any delegate about the closure 
        if let delegate = window?.delegate {
            let notification = Notification(name: NSWindow.willCloseNotification, object: window, userInfo: nil)
            delegate.windowWillClose?(notification)
        }
    }
    
    @objc func wrapToLastImage(_ sender: NSButton) {
        currentImageIndex = onboardingImages.count - 1
        updateUI()
    }
}
