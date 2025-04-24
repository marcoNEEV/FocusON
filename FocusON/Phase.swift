import Foundation
import AppKit

enum PhaseType {
    case focus
    case relax
}

struct Phase {
    let duration: Int
    let backgroundColor: NSColor
    let label: String
    let type: PhaseType
} 