import Foundation

/// Formats an elapsed duration for the status line, e.g. "45m" or "1h 12m".
public func formatElapsed(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int(max(0, seconds) / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours == 0 ? "\(minutes)m" : "\(hours)h \(minutes)m"
}
