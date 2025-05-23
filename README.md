# FocusON

A macOS menu bar Pomodoro timer application designed to help you stay focused and productive.

## Features

- Simple Pomodoro timer with customizable focus and break durations
- Menu bar integration for easy access
- Visual timer with customizable labels
- Prevent sleep mode during focus sessions
- Optional timer display
- Audio notification when phases change
- Automatic startup on login (macOS 13.0+)

## Usage

- **Left-click** the menu bar icon to start/pause/resume the timer
- **Right-click** to access the settings menu:
  - Edit focus time durations
  - Customize focus text
  - Toggle sleep prevention
  - Toggle timer display
  - Reset the timer
  - View app information

## Pomodoro Technique

FocusON implements the Pomodoro Technique, a time management method that uses timed intervals of focused work followed by short breaks, with a longer break after four work sessions.

Default timers:
- Focus: 25 minutes
- Short break: 5 minutes
- Long break: 21 minutes

## Installation

Download the latest release and move it to your Applications folder.

## 🔋 Sleep Prevention System

FocusON uses macOS's IOKit to prevent the system from sleeping during active focus sessions.

### Key Implementation Details:
- Uses `kIOPMAssertionTypePreventUserIdleSystemSleep` (via `IOPMAssertionCreateWithName`) to block idle sleep only while the timer is running.
- Sleep prevention is **safely released** when:
  - the timer is paused or reset
  - the app is quit or terminated
  - the timer deinitializes (as a safeguard)
- This ensures the app never leaves behind active sleep assertions that could drain battery or cause heating issues.

### Debug Logging

To track sleep assertions and app state changes, FocusON includes a state-aware logging system:
- Logging is **enabled only in DEBUG builds** using `#if DEBUG`.
- You can toggle logging on/off with the `enableDebugLogging` flag.
- Logs are optimized to avoid repetition (e.g., logging only when the UI or state changes).
- All key user actions (start, pause, reset, quit) and assertion events are logged.

To enable debug logs, set:

```swift
let enableDebugLogging = true
```
