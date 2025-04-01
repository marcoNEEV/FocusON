import SwiftUI

@main
struct FocusONApp: App {
    // Inject AppDelegate so its logic runs alongside SwiftUI.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // For a menu-bar app you may not need a main window;
        // here we use a Settings scene with an EmptyView.
        Settings {
            EmptyView()
        }
    }
}
