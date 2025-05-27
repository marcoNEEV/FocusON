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
    var showTimerEnabled: Bool {
        get { AppState.shared.showTimer }
        set { AppState.shared.showTimer = newValue }
    }
    private var onboardingController: OnboardingWindowController?
    var preventSleepEnabled: Bool {
        get { AppState.shared.preventSleep }
        set { AppState.shared.preventSleep = newValue }
    }
    
    let initialBackgroundColor = NSColor(calibratedRed: 173/255.0,
                                         green: 216/255.0,
                                         blue: 230/255.0,
                                         alpha: 1.0)
    
    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setting up app persistence is optional - don't let it interfere with app startup
        // REMOVED: if #available(macOS 13.0, *) {
        //     DispatchQueue.global(qos: .background).async { [weak self] in
        //         self?.addAppToLoginItems()
        //     }
        // }
        
        // Initialize status item - this is the core functionality
        setupStatusItem()
        
        // Register for sleep/wake notifications
        registerSleepWakeNotifications()
    }
    
    // Set up the status bar item and timer model
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else {
            print("ERROR: No status bar button.")
            return
        }
        
        // Load saved preferences
        debugLog("🔄 Loaded preferences: Show Timer = \(showTimerEnabled ? "ON" : "OFF")")
        
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
            // Show custom menu directly below the status bar icon
            let menu = buildCustomMenu()
            if let button = statusItem?.button {
                menu.popUp(positioning: nil,
                           at: NSPoint(x: 0, y: button.bounds.height),
                           in: button)
            }
            return
        }
        
        // Left-click: start, pause, resume
        switch timerModel.timerState {
        case .notStarted:
            debugLog("▶️ Timer starting")
            timerModel.start()
            // Force log the state change
            logUIStateChange(timerState: .running, showTimer: showTimerEnabled, force: true)
            
        case .running:
            debugLog("⏸️ Timer pausing")
            timerModel.pause()
            // Force log the state change
            logUIStateChange(timerState: .paused, showTimer: showTimerEnabled, force: true)
            updateUI()
            
        case .paused:
            debugLog("▶️ Timer resuming")
            timerModel.resume()
            // Force log the state change
            logUIStateChange(timerState: .running, showTimer: showTimerEnabled, force: true)
        }
    }
    
    // MARK: - Build the "Grid" Menu
    func buildCustomMenu() -> NSMenu {
        let isInActiveState = (timerModel.timerState == .running || timerModel.timerState == .paused)
        // Debug: log to system console to verify menu state
        NSLog("🔧 buildCustomMenu – timerState: %@, isInActiveState: %@", String(describing: timerModel.timerState), String(isInActiveState))
        let menu = NSMenu()
        // Disable auto-enabling so manual .isEnabled flags are honored
        menu.autoenablesItems = false
        
        // Apply consistent style to the menu
        menu.font = NSFont.systemFont(ofSize: 13)
        
        // 1) Terminate App - standard OS menu item
        let terminateItem = NSMenuItem(title: "Terminate App", action: #selector(terminateApp), keyEquivalent: "")
        terminateItem.target = self
        terminateItem.isEnabled = true
        // Add terminate icon
        if let terminateImage = NSImage(named: NSImage.stopProgressTemplateName) {
            terminateImage.size = NSSize(width: 16, height: 16)
            terminateItem.image = terminateImage
        }
        menu.addItem(terminateItem)
        
        // Settings submenu - contains grouped settings
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: ",")  // Add keyboard shortcut
        let settingsSubmenu = NSMenu()
        settingsSubmenu.autoenablesItems = false  // Important for consistent behavior
        // Style the submenu with the same font
        settingsSubmenu.font = NSFont.systemFont(ofSize: 13)
        
        // Apply styling to Settings menu item
        settingsItem.attributedTitle = NSAttributedString(
            string: "Settings",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
        
        // 2) Edit Focus Time – moved to Settings submenu
        let editFocusTimeItem = NSMenuItem(title: "Edit Focus Time",
                                           action: #selector(showPhaseTimesInput),
                                           keyEquivalent: "t")
        editFocusTimeItem.target = self
        editFocusTimeItem.isEnabled = !isInActiveState
        editFocusTimeItem.indentationLevel = 1
        // Add clock icon
        if let clockImage = NSImage(named: NSImage.colorPanelName) {
            clockImage.size = NSSize(width: 16, height: 16)
            editFocusTimeItem.image = clockImage
        }
        settingsSubmenu.addItem(editFocusTimeItem)
        
        // 3) Edit Focus Text – moved to Settings submenu
        let editFocusTextItem = NSMenuItem(title: "Edit Focus Text",
                                           action: #selector(showFocusTextInput),
                                           keyEquivalent: "e")
        editFocusTextItem.target = self
        // Enable only when timer is running or paused
        editFocusTextItem.isEnabled = isInActiveState
        editFocusTextItem.indentationLevel = 1
        // Add text edit icon
        if let textEditImage = NSImage(named: NSImage.fontPanelName) {
            textEditImage.size = NSSize(width: 16, height: 16)
            editFocusTextItem.image = textEditImage
        }
        settingsSubmenu.addItem(editFocusTextItem)
        
        // 4) Show Timer – moved to Settings submenu
        let showTimerItem = NSMenuItem(title: "Show Timer", action: #selector(toggleShowTimer), keyEquivalent: "s")
        showTimerItem.target = self
        showTimerItem.state = self.showTimerEnabled ? .on : .off
        showTimerItem.isEnabled = isInActiveState
        showTimerItem.indentationLevel = 1
        // Add time icon
        if let timerImage = NSImage(named: NSImage.revealFreestandingTemplateName) {
            timerImage.size = NSSize(width: 16, height: 16)
            showTimerItem.image = timerImage
        }
        settingsSubmenu.addItem(showTimerItem)
        
        // 5) Prevent Sleep – user-controlled focus-session sleep block
        let preventSleepItem = NSMenuItem(
            title: "Prevent Sleep",
            action: #selector(togglePreventSleep),
            keyEquivalent: "p"
        )
        preventSleepItem.target = self
        preventSleepItem.state = preventSleepEnabled ? NSControl.StateValue.on : NSControl.StateValue.off
        preventSleepItem.isEnabled = isInActiveState
        preventSleepItem.indentationLevel = 1
        if let sleepImage = NSImage(named: NSImage.computerName) {
            sleepImage.size = NSSize(width: 16, height: 16)
            preventSleepItem.image = sleepImage
        }
        settingsSubmenu.addItem(preventSleepItem)
        
        // Add a separator for better visual organization
        settingsSubmenu.addItem(NSMenuItem.separator())
        
        // Add icons to menu items
        if let gearImage = NSImage(named: NSImage.preferencesGeneralName) {
            gearImage.size = NSSize(width: 16, height: 16)
            settingsItem.image = gearImage
        }
        
        // Set the submenu for the Settings item
        settingsItem.submenu = settingsSubmenu
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 6) Focus Phase X/4 – standard OS menu item (always disabled)
        let cycleItem = NSMenuItem(title: currentCycleLabel(), action: nil, keyEquivalent: "")
        cycleItem.isEnabled = false
        // Add cycle icon
        if let cycleImage = NSImage(named: NSImage.refreshTemplateName) {
            cycleImage.size = NSSize(width: 16, height: 16)
            cycleItem.image = cycleImage
        }
        menu.addItem(cycleItem)
        
        // 7) Reset App - active only in running/paused state
        let resetItem = NSMenuItem(title: "Reset App", action: #selector(resetPhases), keyEquivalent: "r")
        resetItem.target = self
        // Disable and gray out in standby
        resetItem.isEnabled = isInActiveState
        // Add reset icon
        if let resetImage = NSImage(named: NSImage.refreshTemplateName) {
            resetImage.size = NSSize(width: 16, height: 16)
            resetItem.image = resetImage
        }
        // Style with color if enabled
        if isInActiveState {
            resetItem.attributedTitle = NSAttributedString(
                string: "Reset App",
                attributes: [.foregroundColor: initialBackgroundColor]
            )
        } else {
            resetItem.attributedTitle = NSAttributedString(
                string: "Reset App",
                attributes: [.foregroundColor: NSColor.darkGray]
            )
        }
        menu.addItem(resetItem)
        
        // 8) Info – standard OS menu item
        let infoItem = NSMenuItem(title: "Info", action: #selector(showInfo), keyEquivalent: "i")
        infoItem.target = self
        infoItem.isEnabled = true
        // Add info icon
        if let infoImage = NSImage(named: NSImage.infoName) {
            infoImage.size = NSSize(width: 16, height: 16)
            infoItem.image = infoImage
        }
        menu.addItem(infoItem)
        
        // Debug: log each item's enabled state
        for item in menu.items {
            NSLog("🔧 menuItem '%@' enabled: %d", item.title, item.isEnabled ? 1 : 0)
        }
        
        return menu
    }
    
    // MARK: - UI Update
    func updateUI() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }
            let phase = self.timerModel.phases[self.timerModel.currentPhaseIndex]
            
            // Log UI state changes only when they change, not on every update
            logUIStateChange(timerState: self.timerModel.timerState, showTimer: self.showTimerEnabled)
            
            switch self.timerModel.timerState {
            case .running:
                let mins = Int(ceil(Double(self.timerModel.countdownSeconds)/60.0))
                // Format as "25: FOCUS ON!" or just "FOCUS ON!" based on showTimerEnabled
                let text = self.showTimerEnabled ? "\(mins): \(phase.label)" : phase.label
                button.image = createStatusBarImage(text: text,
                                                    backgroundColor: phase.backgroundColor,
                                                    textColor: .white)
            case .paused:
                // Format as "II: FOCUS ON!" or just "FOCUS ON!" based on showTimerEnabled
                let text = self.showTimerEnabled ? "II: \(phase.label)" : phase.label
                button.image = createStatusBarImage(text: text,
                                                    backgroundColor: NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.86, alpha: 1.0),
                                                    textColor: .labelColor)
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
        let currentPhaseLabel = timerModel.phases.first { $0.type == .focus }?.label ?? "FOCUS ON!"
        
        Task { @MainActor in
            WindowManager.shared.showTextInputAlert(
                key: "phaseTimesInput",
                title: "Edit Focus Label",
                message: "Enter a label (max 6 characters)",
                defaultText: currentPhaseLabel,
                completion: { newText in
                    Task { @MainActor in
                        WindowManager.shared.updateFocusPhaseLabel(newText ?? currentPhaseLabel)
                    }
                }
            )
        }
    }
    
    // MARK: - Show Phase Times
    @objc func showPhaseTimesInput() {
        Task { @MainActor in
            WindowManager.shared.showAlert(
                key: "phaseTimesInput",
                title: "Timer Settings",
                message: "Configure focus and break durations",
                style: .informational,
                buttons: ["OK", "Cancel"]
            ) { response in
                if response == .alertFirstButtonReturn {
                    // handle OK
                }
            }
        }
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
    
    // MARK: - Show Timer Toggle
    @objc func toggleShowTimer() {
        // Toggle the state
        showTimerEnabled.toggle()
        
        // Log the change using our debug logger
        debugLog("🕒 Show Timer toggled: now \(showTimerEnabled ? "ON" : "OFF")")
        
        // Force log the state change since this is a user-initiated action
        logUIStateChange(timerState: timerModel.timerState, showTimer: showTimerEnabled, force: true)
        
        // Update UI immediately
        updateUI()
    }
    
    // MARK: - Reset / Terminate
    @objc func resetPhases() {
        timerModel.reset()
        
        // Force log the state change since this is a user-initiated action
        logUIStateChange(timerState: timerModel.timerState, showTimer: showTimerEnabled, force: true)
        
        // Manually update UI after reset to ensure changes are reflected
        updateUI()
        
        // Log for debugging
        debugLog("🔄 App reset: Timer state is now \(timerModel.timerState)")
    }
    
    @objc func terminateApp() {
        Task { @MainActor in
            WindowManager.shared.showAlert(
                key: "terminate",
                title: "Confirm Termination",
                message: "Are you sure you want to quit?",
                style: .warning,
                buttons: ["Cancel", "Quit"],
                defaultButtonIndex: 0,  // Make Cancel the default (blue) button
                destructiveButtonIndex: 1,  // Make Quit the destructive button
                completion: { response in
                    if response == .alertSecondButtonReturn {
                        NSApp.terminate(nil)
                    }
                }
            )
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
                tf.stringValue.removeLast()
            }
        }
    }
    
    // MARK: - App Persistence
    func addAppToLoginItems() {
        let launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        #if canImport(ServiceManagement)
        if #available(macOS 13, *) {
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        } else {
            let id = "com.yourcompany.FocusONHelper" as CFString
            SMLoginItemSetEnabled(id, launchAtLogin)
        }
        #endif
    }
    
    // MARK: - Show Info
    @MainActor
    @objc func showInfo() {
        print(" showInfo called")
        Task { @MainActor in WindowManager.shared.showOnboardingWindow() }
    }
    
    // MARK: - Sleep/Wake Notifications
    private func registerSleepWakeNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSleepNotification(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeNotification(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        // Also register for screen sleep/wake events (for lid close)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenSleepNotification(_:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenWakeNotification(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        // Register for termination notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }
    
    // Handle sleep notification
    @objc private func handleSleepNotification(_ notification: Notification) {
        print("💤 System will sleep - pausing timer if running")
        
        if timerModel.timerState == .running {
            timerModel.pause()
        }
    }
    
    // Handle wake notification
    @objc private func handleWakeNotification(_ notification: Notification) {
        print("⏰ System did wake - checking timer state")
        
        if timerModel.timerState == .paused {
            timerModel.resume()
        }
    }
    
    // Handle screen sleep notification (lid close, display sleep)
    @objc private func handleScreenSleepNotification(_ notification: Notification) {
        print("🔌 Screen will sleep - pausing timer if running")
        
        if timerModel.timerState == .running {
            timerModel.pause()
        }
    }
    
    // Handle screen wake notification
    @objc private func handleScreenWakeNotification(_ notification: Notification) {
        print("📱 Screen did wake - checking timer state")
        
        if timerModel.timerState == .paused {
            timerModel.resume()
        }
    }
    
    // Clean up when application terminates
    @objc func applicationWillTerminate(_ notification: Notification) {
        debugLog("👋 App terminating, cleaning up resources...")
        
        // Invalidate timers to prevent memory leaks and CPU usage
        timerModel.reset()
        
        // Remove observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        
        debugLog("👋 Application cleanup complete, goodbye!")
    }
    
    @objc func togglePreventSleep() {
        preventSleepEnabled.toggle()
        // Optionally, update the timer model's sleep guard if needed
        if preventSleepEnabled {
            timerModel?.sleepGuard.begin(reason: "Pomodoro focus session")
        } else {
            timerModel?.sleepGuard.end()
        }
        // Rebuild the menu to reflect the new state
        statusItem?.menu = buildCustomMenu()
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
    private let cardTextFont: NSFont = NSFont(name: "Snell Roundhand", size: 43.2) ?? NSFont.systemFont(ofSize: 43.2, weight: .medium)
    
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
        
        // Set the window level to be system modal
        window.level = .modalPanel
        
        // Set window behavior to modal without an explicit property
        window.styleMask.insert(.nonactivatingPanel)
        
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
        // Use a mix of light blue (standby icon) and warm gray
        let initialBlue = NSColor(calibratedRed: 0.5, green: 0.7, blue: 0.8, alpha: 1.0)
        let variantBlue = NSColor(calibratedRed: 0.45, green: 0.65, blue: 0.75, alpha: 1.0)
        let warmGray1 = NSColor(calibratedRed: 0.65, green: 0.63, blue: 0.60, alpha: 1.0)
        let warmGray2 = NSColor(calibratedRed: 0.70, green: 0.68, blue: 0.65, alpha: 1.0)
        let gradientPairs: [(NSColor, NSColor)] = [
            (initialBlue, warmGray1),
            (initialBlue, warmGray2),
            (variantBlue, warmGray1),
            (variantBlue, warmGray2)
        ]

        for (startColor, endColor) in gradientPairs {
            let image = NSImage(size: NSSize(width: 800, height: 500))
            image.lockFocus()
            
            let gradient = NSGradient(starting: startColor, ending: endColor)!
            gradient.draw(in: NSRect(x: 0, y: 0, width: 800, height: 500), angle: 90)
            
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
                    cardLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: 0.8)
                ])
            }
        }
    }
    
    private func updateUI() {
        if !onboardingImages.isEmpty {
            imageView.image = onboardingImages[currentImageIndex]
            
            // Update label based on screen index
            if currentImageIndex == 0 {
                // Special formatting for welcome screen
                cardLabel.font = NSFont(name: "Avenir", size: 16) ?? NSFont.systemFont(ofSize: 16, weight: .medium)
                cardLabel.textColor = .black
                cardLabel.preferredMaxLayoutWidth = 700 // Set preferred wrapping width
                cardLabel.cell?.wraps = true
                cardLabel.cell?.isScrollable = false
                cardLabel.cell?.truncatesLastVisibleLine = true
                cardLabel.stringValue = "Welcome to FocusON, the most minimalist macOS App designed to keep you focus! Stay on track with its discrete menu-bar icon and the Tibetan gong audio cues. No complicated settings or additional features, just what it is needed to stay key focus, right from the comfort of your menu-bar. Once downloaded, the light-blue icon will appear on your menu-bar, just click on it and start to be productive!"
            } else if currentImageIndex == 1 {
                // Screen 2 - Focus and Relax
                cardLabel.font = NSFont(name: "Avenir", size: 16) ?? NSFont.systemFont(ofSize: 16, weight: .medium)
                cardLabel.textColor = .black
                cardLabel.preferredMaxLayoutWidth = 700
                cardLabel.cell?.wraps = true
                cardLabel.cell?.isScrollable = false
                cardLabel.cell?.truncatesLastVisibleLine = true
                cardLabel.stringValue = "Focus and Relax\n\nThe App guides you through phases of focus and relax. The App is set by default on 25 minutes of deep focus, followed by a 5 minute breather. After four focus sessions, there is a longer 21 minute break. This is science-backed time management, simplified. Feel free to adjust focus and break times based on your needs."
            } else if currentImageIndex == 2 {
                // Screen 3 - App Controls
                cardLabel.font = NSFont(name: "Avenir", size: 16) ?? NSFont.systemFont(ofSize: 16, weight: .medium)
                cardLabel.textColor = .black
                cardLabel.preferredMaxLayoutWidth = 700
                cardLabel.cell?.wraps = true
                cardLabel.cell?.isScrollable = false
                cardLabel.cell?.truncatesLastVisibleLine = true 
                cardLabel.stringValue = "App Controls\n\nUse the Left-click the menu-bar icon to start (icon turns red), pause (icon turns pink) or resume the App (light blue icon). Use the Right-click for settings. Adjust your focus/break lengths (accessible when in standby). While running, use the setting to customize the label text, show/hide the minutes, toggle sleep prevention (this prevents your Mac to go in sleep mode if you do not touch the keyboard/mouse) and reset the App."
            } else if currentImageIndex == 3 {
                // Screen 4 - The App
                cardLabel.font = NSFont(name: "Avenir", size: 16) ?? NSFont.systemFont(ofSize: 16, weight: .medium)
                cardLabel.textColor = .black
                cardLabel.preferredMaxLayoutWidth = 700
                cardLabel.cell?.wraps = true
                cardLabel.cell?.isScrollable = false
                cardLabel.cell?.truncatesLastVisibleLine = true
                cardLabel.stringValue = "The App\n\nOnce downloaded from the Apple Store the App will be automatically stored in tour \"Applications\". The App will be launch at login. If you terminate the App the icon will disappear from the menu-bar. To restart the FocusON App simply go to Application and double click on it."
            } else {
                // Original formatting for other screens
                cardLabel.font = cardTextFont
                cardLabel.textColor = cardTextColor
                cardLabel.preferredMaxLayoutWidth = 0 // Reset wrapping
            cardLabel.stringValue = "Onboarding Screen \(currentImageIndex + 1)"
            }
            
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
        // Stop the modal session before closing the window
        NSApp.stopModal()
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

// Add after WindowManager
class AppState {
    static let shared = AppState()
    
    @Published var timerState: TimerState = .notStarted
    @Published var showTimer: Bool {
        didSet {
            UserDefaults.standard.set(showTimer, forKey: "ShowTimerEnabled")
        }
    }
    @Published var preventSleep: Bool {
        didSet {
            UserDefaults.standard.set(preventSleep, forKey: "preventSleepEnabled")
        }
    }
    
    private init() {
        showTimer = UserDefaults.standard.bool(forKey: "ShowTimerEnabled")
        preventSleep = UserDefaults.standard.bool(forKey: "preventSleepEnabled")
    }
    
    func updateTimerState(_ newState: TimerState) {
        DispatchQueue.main.async {
            self.timerState = newState
        }
    }
} 
