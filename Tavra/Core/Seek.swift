import Foundation

/// How a jump on the media timeline reaches a player. macOS keeps its now-playing information to
/// itself, so Tavra asks the players that answer, and presses arrow keys in the ones that don't.
enum SeekRoute: Sendable, Equatable {
    /// Knows the track and its position, and can jump to the exact second.
    case script(player: String)
    /// Left and right arrow, which nearly every video player understands.
    case arrows
    /// Nothing here to seek, and an arrow key would only move a text cursor.
    case nothing
}

enum Seek {
    static let music = "com.apple.Music"
    static let spotify = "com.spotify.client"

    /// Apps where an arrow key seeks a playing video.
    static let videoApps: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "app.zen-browser.zen",
        "com.apple.QuickTimePlayerX", "com.apple.TV", "com.colliderli.iina", "org.videolan.vlc", "com.firecore.infuse",
    ]

    /// The app in front is what's being watched. Otherwise a music app that's already open is what's
    /// being listened to. Only ever one that's running: asking one that isn't would launch it.
    static func route(front: String?, running: Set<String>) -> SeekRoute {
        if let front, front == music || front == spotify { return .script(player: front) }
        if let front, videoApps.contains(front) { return .arrows }
        if running.contains(spotify) { return .script(player: spotify) }
        if running.contains(music) { return .script(player: music) }
        return .nothing
    }

    /// Whole key presses for a jump. Never so many it would take long to send.
    static func arrowPresses(seconds: Double, arrowSeconds: Double) -> (count: Int, forward: Bool) {
        let count = Int((abs(seconds) / max(arrowSeconds, 1)).rounded())
        return (min(count, 120), seconds >= 0)
    }

    /// Where a jump lands, kept inside the track.
    static func target(position: Double, duration: Double, jump: Double) -> Double {
        min(max(position + jump, 0), max(duration - 1, 0))
    }

    /// "1:05", "1:02:09".
    static func clock(_ seconds: Double) -> String {
        let total = Int(abs(seconds).rounded())
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "+1:05", "−0:10".
    static func signedClock(_ seconds: Double) -> String { (seconds < 0 ? "−" : "+") + clock(seconds) }

    static func script(toRead player: String) -> String {
        // Spotify gives a track's length in milliseconds, Music in seconds.
        let duration = player == spotify ? "(duration of current track) / 1000" : "duration of current track"
        let name = player == spotify ? "Spotify" : "Music"
        return """
        tell application "\(name)"
            if player state is stopped then return ""
            return (player position as text) & "|" & (\(duration) as text) & "|" & (name of current track)
        end tell
        """
    }

    static func script(toJump player: String, to seconds: Double) -> String {
        let name = player == spotify ? "Spotify" : "Music"
        return "tell application \"\(name)\" to set player position to \(String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), seconds))"
    }

    /// Reads what `script(toRead:)` gives back. AppleScript writes numbers the way the Mac's region
    /// does, so "12,5" is as likely as "12.5".
    static func parse(_ reply: String) -> (position: Double, duration: Double, title: String)? {
        let parts = reply.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return nil }
        func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
        guard let position = number(parts[0]), let duration = number(parts[1]), duration > 0 else { return nil }
        return (position, duration, parts[2])
    }
}
