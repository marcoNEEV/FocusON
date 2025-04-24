import Cocoa

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