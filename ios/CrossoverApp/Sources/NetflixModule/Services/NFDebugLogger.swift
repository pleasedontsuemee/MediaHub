import Foundation
import Combine

#if canImport(UIKit)
import UIKit
#endif

public enum NFLogLevel: String, CaseIterable {
    case info = "INFO"
    case net = "NET"
    case stream = "STREAM"
    case player = "PLAYER"
    case ui = "UI"
    case error = "ERROR"
}

public struct NFLogEntry: Identifiable, Hashable {
    public let id = UUID()
    public let timestamp: Date
    public let level: NFLogLevel
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

public final class NFDebugLogger: ObservableObject, @unchecked Sendable {
    public static let shared = NFDebugLogger()

    @Published public private(set) var entries: [NFLogEntry] = []
    @Published public var livePlayerSummary: String = "Idle"

    private let maxEntries = 1000

    private init() {
        log(.info, tag: "App", "NetflixClone + Movix Engine initialized (\(Bundle.main.bundleIdentifier ?? "com.movix.netflixclone"))")
    }

    public func log(_ level: NFLogLevel, tag: String, _ message: String) {
        let entry = NFLogEntry(timestamp: Date(), level: level, tag: tag, message: message)
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
            self?.livePlayerSummary = summary
        }
    }

    public func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
    }

    public func copyAllToClipboard() {
        #if canImport(UIKit)
        UIPasteboard.general.string = entries.map(\.formattedLine).joined(separator: "\n")
        #endif
    }
}
