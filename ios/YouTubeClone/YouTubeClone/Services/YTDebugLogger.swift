import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Full-App Real-Time Debug Logger (`YTDebugLogger`)
public enum YTLogLevel: String, CaseIterable {
    case info = "INFO"
    case net = "NET"
    case stream = "STREAM"
    case player = "PLAYER"
    case ui = "UI"
    case error = "ERROR"
}

public struct YTLogEntry: Identifiable, Hashable {
    public let id = UUID()
    public let timestamp: Date
    public let level: YTLogLevel
    public let tag: String
    public let message: String

    public var formattedTime: String {
        Self.formatter.string(from: timestamp)
    }

    public var formattedLine: String {
        "[\(formattedTime)] [\(level.rawValue)] [\(tag)] \(message)"
    }

    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
}

public final class YTDebugLogger: ObservableObject, @unchecked Sendable {
    public static let shared = YTDebugLogger()

    @Published public private(set) var entries: [YTLogEntry] = []
    @Published public var livePlayerStateSummary: String = "Idle"

    private let queue = DispatchQueue(label: "com.ytmine.debuglogger")
    private let maxEntries = 1000

    private init() {
        log(.info, tag: "App", "YTDebugLogger initialized (bundle: \(Bundle.main.bundleIdentifier ?? "unknown"))")
    }

    public func log(_ level: YTLogLevel, tag: String, _ message: String) {
        let entry = YTLogEntry(timestamp: Date(), level: level, tag: tag, message: message)
        #if DEBUG
        print(entry.formattedLine)
        #endif
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    public func updatePlayerSummary(_ summary: String) {
        DispatchQueue.main.async { [weak self] in
            self?.livePlayerStateSummary = summary
        }
    }

    public func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
            self?.log(.info, tag: "Debug", "Logs cleared")
        }
    }

    public func exportAllText() -> String {
        entries.map(\.formattedLine).joined(separator: "\n")
    }

    public func copyAllToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = exportAllText()
        #endif
    }
}
