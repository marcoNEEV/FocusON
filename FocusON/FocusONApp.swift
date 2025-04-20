import SwiftUI

@main
struct FocusONApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView().frame(width: 0, height: 0)
        }
    }
}
