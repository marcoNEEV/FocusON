import SwiftUI

@main
struct FocusONApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Remove the default window; use only the menu bar and onboarding window
        Settings {
            EmptyView()
        }
    }
}
