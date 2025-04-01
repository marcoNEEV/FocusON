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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
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
    let response = alert.runModal()
    return (response == .alertFirstButtonReturn)
}

// MARK: - "Row View" for a uniform grid approach
/// A row in the menu, always 200×22, with left-aligned text. Optionally clickable, optionally closes menu.
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
        
        // Force a uniform row size
        let width: CGFloat = 200
        let height: CGFloat = 22
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        
        // Label
        label = NSTextField(frame: NSRect(x: 8, y: 1, width: width - 10, height: height - 2))
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: 13)
        label.alignment = .left
        
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
class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    
    var statusItem: NSStatusItem?
    var timerModel: TimerModel!
    var preventSleepEnabled = false
    
    let initialBackgroundColor = NSColor(calibratedRed: 173/255.0,
                                         green: 216/255.0,
                                         blue: 230/255.0,
                                         alpha: 1.0)
    
    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
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
            if let button = statusItem?.button {
                let location = button.window?.convertPoint(fromScreen: NSEvent.mouseLocation) ?? NSEvent.mouseLocation
                menu.popUp(positioning: nil, at: location, in: button)
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
        
        // 1) Terminate App
        menu.addItem(makeMenuRowItem(isEnabled: true,
                                     closesMenu: true,
                                     target: self,
                                     action: #selector(terminateApp),
                                     textProvider: { "Terminate App" }))
        
        // If running or paused
        switch timerModel.timerState {
        case .running, .paused:
            // 2) Only show "Edit Focus Text" if the current phase is focus
            let currentPhase = timerModel.phases[timerModel.currentPhaseIndex]
            if currentPhase.type == .focus {
                menu.addItem(makeMenuRowItem(isEnabled: true,
                                             closesMenu: true,
                                             target: self,
                                             action: #selector(showFocusTextInput),
                                             textProvider: { "Edit Focus Text" }))
            }

            // 3) Prevent Sleep
            menu.addItem(makeMenuRowItem(isEnabled: true,
                                         closesMenu: false,
                                         target: self,
                                         action: #selector(togglePreventSleep),
                                         textProvider: {
                self.preventSleepEnabled ? "Prevent Sleep (ON)" : "Prevent Sleep (OFF)"
            }))
            
            // 4) Focus Phase X/4 (disabled)
            menu.addItem(makeMenuRowItem(isEnabled: false,
                                         closesMenu: false,
                                         target: nil,
                                         action: nil,
                                         textProvider: { self.currentCycleLabel() }))
            
            // 5) Reset App
            menu.addItem(makeMenuRowItem(isEnabled: true,
                                         closesMenu: true,
                                         target: self,
                                         action: #selector(resetPhases),
                                         textProvider: { "Reset App" }))
            
        case .notStarted:
            // If not started, show "Edit Phase Times"
            menu.addItem(makeMenuRowItem(isEnabled: true,
                                         closesMenu: true,
                                         target: self,
                                         action: #selector(showPhaseTimesInput),
                                         textProvider: { "Edit Phase Times" }))
        }
        
        return menu
    }
    
    // MARK: - UI Update
    func updateUI() {
        guard let button = statusItem?.button else { return }
        let phase = timerModel.phases[timerModel.currentPhaseIndex]
        
        switch timerModel.timerState {
        case .running:
            let mins = Int(ceil(Double(timerModel.countdownSeconds)/60.0))
            let text = "\(mins): \(phase.label)"
            button.image = createStatusBarImage(text: text,
                                               
                                                backgroundColor: phase.backgroundColor,
                                                textColor: .white)
        case .paused:
            let text = "II: \(phase.label)"
            button.image = createStatusBarImage(text: text,
                                                backgroundColor: .darkGray,
                                                textColor: .white)
    // MARK: - TEsting the Dot :)
        case .notStarted:
            button.image = createStatusBarImage(text: "FOCUS·ON",
                                                backgroundColor: initialBackgroundColor,
                                                textColor: .darkGray)
        }
    }
    
    // MARK: - Current Cycle Label
    func currentCycleLabel() -> String {
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
        alert.messageText = "Focus/relax cycles"
        alert.informativeText = "Edit the focus, short break, and longer break times."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let containerWidth: CGFloat = 200
        let containerHeight: CGFloat = 30
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: containerHeight))
        
        let fieldWidth: CGFloat = 50
        let spacing: CGFloat = 10
        let totalWidth = 3*fieldWidth + 2*spacing
        let margin = (containerWidth - totalWidth)/2
        
        let fField = NSTextField(frame: NSRect(x: margin, y: 0, width: fieldWidth, height: containerHeight))
        fField.alignment = .center
        fField.delegate = self
        fField.tag = 1001
        fField.stringValue = "\(currentFocus)"
        
        let sField = NSTextField(frame: NSRect(x: margin+fieldWidth+spacing, y: 0, width: fieldWidth, height: containerHeight))
        sField.alignment = .center
        sField.delegate = self
        sField.tag = 1001
        sField.stringValue = "\(currentShort)"
        
        let lField = NSTextField(frame: NSRect(x: margin+2*(fieldWidth+spacing), y: 0, width: fieldWidth, height: containerHeight))
        lField.alignment = .center
        lField.delegate = self
        lField.tag = 1001
        lField.stringValue = "\(currentLong)"
        
        container.addSubview(fField)
        container.addSubview(sField)
        container.addSubview(lField)
        
        alert.accessoryView = container
        return (alert, [fField, sField, lField])
    }
    
    // MARK: - Sound
    func playGongSound() {
        guard let gongURL = Bundle.main.url(forResource: "tibetan_Gong", withExtension: "wav"),
              let gongSound = NSSound(contentsOf: gongURL, byReference: false) else {
            print("ERROR: Could not load tibetan_Gong.wav.")
            return
        }
        gongSound.play()
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
}
