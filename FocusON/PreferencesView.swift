import LaunchAtLogin

@AppStorage("preventSleepEnabled") private var preventSleepEnabled = false

struct PreferencesView: View {
    var body: some View {
        Form {
            Toggle("Prevent sleep during focus sessions", isOn: $preventSleepEnabled)
            LaunchAtLogin.Toggle {
                Text("Launch FocusON at Login")
            }
            // …other prefs…
        }
    }
} 