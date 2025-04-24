import Cocoa
import CoreText
import IOKit.pwr_mgt  // For sleep prevention
#if os(macOS) && canImport(ServiceManagement)
import ServiceManagement  // For login item persistence on macOS 13.0+
#endif

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
                _ = NSPoint(x: locationInScreen.x, y: locationInScreen.y)

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
        menu.addItem(NSMenuItem.separator())
        
        // 6) Focus Phase X/4 - always gray/inactive
        menu.addItem(makeMenuRowItem(isEnabled: false,
                                     closesMenu: false,
                                     target: nil,
                                     action: nil,
                                     textProvider: { self.currentCycleLabel() }))
        
        // 7) Reset App - active only in running/paused state
        let resetItem = NSMenuItem(title: "Reset App", action: #selector(resetPhases), keyEquivalent: "")
        resetItem.target = self
        // Disable and gray out in standby
        resetItem.isEnabled = isInActiveState
        let resetColor: NSColor = isInActiveState ? initialBackgroundColor : .darkGray
        resetItem.attributedTitle = NSAttributedString(string: "Reset App", attributes: [.foregroundColor: resetColor])
        menu.addItem(resetItem)
        
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
        print("🟢 showInfo called")
        NSApp.activate(ignoringOtherApps: true)
        
        // Check if onboarding window already exists
        if let controller = onboardingController, let window = controller.window {
            print("🔁 Reusing existing onboarding window")
            // If window exists, just bring it to front
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        print("🆕 Creating new onboarding window controller")
        // Create the onboarding controller only once
        let controller = OnboardingWindowController.create()
        controller.window?.delegate = self
        onboardingController = controller
        print("📐 Positioning onboarding window")
        
        // Position the window on screen
        if let window = controller.window, let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowRect = window.frame
            let newOrigin = NSPoint(
                x: screenRect.midX - windowRect.width / 2,
                y: screenRect.midY - windowRect.height / 2
            )
            window.setFrameOrigin(newOrigin)
            
            print("👁️ Showing onboarding window")
            // Show the window only once
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
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
    private var cardLabel: NSTextField!
    private let cardTextColor: NSColor = .white
    // Use 'Snell Roundhand' for a handwriting style
    private let cardTextFont: NSFont = NSFont(name: "Snell Roundhand", size: 18) ?? NSFont.systemFont(ofSize: 18, weight: .medium)
    
    // Convenience initializer
    static func create() -> OnboardingWindowController {
        print("🛠️ OnboardingWindowController.create() called")
        // Size window to 3/5 of previous size (now roughly 1/3 of typical laptop screen)
        let width: CGFloat = 920
        let height: CGFloat = 575
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true  // Defer window display until explicitly shown
        )
        window.title = "FocusON Onboarding"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.isMovableByWindowBackground = true
        
        // Create controller without loading window automatically
        let controller = OnboardingWindowController(window: window)
        
        // Ensure window is not shown automatically
        window.orderOut(nil)
        
        // Load content immediately but don't show the window yet
        controller.loadContent()
        
        return controller
    }
    
    // New method to load content before window is shown
    private func loadContent() {
        print("🖼️ loadContent called")
        // Register custom 'Caveat' font (ensure 'Caveat-Regular.ttf' is in the bundle resources)
        if let fontURL = Bundle.main.url(forResource: "Caveat-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
        // Load onboarding images
        loadOnboardingImages()
        
        guard let window = window, let contentView = window.contentView else { return }
        
        // Configure the window and setup views
        setupViews(in: contentView)
        
        // Update with first image
        updateUI()
    }
    
    private func loadOnboardingImages() {
        // Placeholder - in a real app, you'd bundle actual onboarding images
        // For now, we'll create colored rectangles as placeholders
        let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange]
        
        for color in colors {
            let image = NSImage(size: NSSize(width: 800, height: 500))
            image.lockFocus()
            
            // Draw colored background
            color.setFill()
            NSRect(x: 0, y: 0, width: 800, height: 500).fill()
            
            image.unlockFocus()
            onboardingImages.append(image)
        }
    }
    
    // Override showWindow to prevent automatic window display
    // This ensures only AppDelegate.showInfo() controls window visibility
    override func showWindow(_ sender: Any?) {
        // Do nothing - this prevents NSWindowController from automatically showing the window
        // Window will only be shown when makeKeyAndOrderFront is explicitly called
    }
    
    private func setupViews(in contentView: NSView) {
        // Clear any existing subviews
        contentView.subviews.forEach { $0.removeFromSuperview() }
        
        // Apply background color
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // Setup main UI components
        setupImageView(in: contentView)
        setupNavigationButtons(in: contentView)
        setupPageIndicator(in: contentView)
        
        // Add placeholder text label for onboarding cards
        cardLabel = NSTextField(frame: .zero)
        cardLabel.isEditable = false
        cardLabel.isBordered = false
        cardLabel.drawsBackground = false
        cardLabel.textColor = cardTextColor
        cardLabel.font = cardTextFont
        cardLabel.alignment = .center
        cardLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardLabel)
        
        setupConstraints(in: contentView)
    }
    
    private func setupImageView(in contentView: NSView) {
        imageView = NSImageView(frame: contentView.bounds)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
    }
    
    private func setupNavigationButtons(in contentView: NSView) {
        // Create navigation buttons
        leftButton = createButton(
            in: contentView,
            frame: NSRect(x: 20, y: contentView.bounds.height / 2 - 25, width: 50, height: 50),
            title: "◀",
            fontSize: 24,
            cornerRadius: 25,
            action: #selector(previousImage(_:))
        )
        
        rightButton = createButton(
            in: contentView,
            frame: NSRect(x: contentView.bounds.width - 70, y: contentView.bounds.height / 2 - 25, width: 50, height: 50),
            title: "▶",
            fontSize: 24,
            cornerRadius: 25,
            action: #selector(nextImage(_:))
        )
        
        // Create close button
        _ = createButton(
            in: contentView,
            frame: NSRect(x: contentView.bounds.width - 70, y: contentView.bounds.height - 70, width: 40, height: 40),
            title: "✕",
            fontSize: 18,
            cornerRadius: 20,
            action: #selector(close(_:))
        )
    }
    
    private func createButton(in contentView: NSView, frame: NSRect, title: String, fontSize: CGFloat, cornerRadius: CGFloat, action: Selector) -> NSButton {
        let button = NSButton(frame: frame)
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.title = title
        button.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        button.contentTintColor = .white
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        button.layer?.cornerRadius = cornerRadius
        contentView.addSubview(button)
        return button
    }
    
    private func setupPageIndicator(in contentView: NSView) {
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
    }
    
    private func setupConstraints(in contentView: NSView) {
        // Get the close button for constraints
        let closeButton = contentView.subviews.first { 
            ($0 as? NSButton)?.action == #selector(close(_:)) 
        } as? NSButton
        
        // Find the page indicator by tag
        let pageIndicator = contentView.viewWithTag(100)
        
        // Set constraints
        NSLayoutConstraint.activate([
            // Image view constraints
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // Navigation button constraints
            leftButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            leftButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            leftButton.widthAnchor.constraint(equalToConstant: 50),
            leftButton.heightAnchor.constraint(equalToConstant: 50),
            
            rightButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rightButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            rightButton.widthAnchor.constraint(equalToConstant: 50),
            rightButton.heightAnchor.constraint(equalToConstant: 50),
        ])
        
        // Close button constraints
        if let closeButton = closeButton {
            NSLayoutConstraint.activate([
                closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
                closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
                closeButton.widthAnchor.constraint(equalToConstant: 40),
                closeButton.heightAnchor.constraint(equalToConstant: 40)
            ])
        }
        
        // Page indicator constraints
        if let pageIndicator = pageIndicator {
            NSLayoutConstraint.activate([
                pageIndicator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
                pageIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                pageIndicator.widthAnchor.constraint(equalToConstant: 100),
                pageIndicator.heightAnchor.constraint(equalToConstant: 30)
            ])
            
            // Add constraints for cardLabel above the page indicator
            if let cardLabel = cardLabel {
                NSLayoutConstraint.activate([
                    cardLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                    cardLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                    cardLabel.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.8)
                ])
            }
        }
    }
    
    private func updateUI() {
        if !onboardingImages.isEmpty {
            imageView.image = onboardingImages[currentImageIndex]
            // Update dynamic placeholder label
            cardLabel.stringValue = "Onboarding Screen \(currentImageIndex + 1)"
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
