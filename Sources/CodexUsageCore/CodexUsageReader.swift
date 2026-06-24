import Foundation

public struct UsageWindow: Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int
    public let resetsAt: Date?

    public var remainingPercent: Double {
        max(0, 100 - usedPercent)
    }
}

public struct CodexUsageSnapshot: Equatable, Sendable {
    public let primary: UsageWindow
    public let secondary: UsageWindow
    public let todayTokens: Int
    public let totalTokens: Int
    public let planType: String?
    public let accountLabel: String?
    public let lastUpdated: Date?
    public let sourceFile: String?

    public static let empty = CodexUsageSnapshot(
        primary: UsageWindow(usedPercent: 0, windowMinutes: 300, resetsAt: nil),
        secondary: UsageWindow(usedPercent: 0, windowMinutes: 10_080, resetsAt: nil),
        todayTokens: 0,
        totalTokens: 0,
        planType: nil,
        accountLabel: nil,
        lastUpdated: nil,
        sourceFile: nil
    )
}

public enum CodexUsageError: Error, LocalizedError {
    case noReadableSessionData

    public var errorDescription: String? {
        switch self {
        case .noReadableSessionData:
            "No Codex token_count events were found in the configured session roots."
        }
    }
}

public final class CodexUsageReader {
    private let sessionRoots: [URL]
    private let authFile: URL?
    private let fileManager: FileManager
    private let calendar: Calendar

    public init(
        sessionRoots: [URL] = CodexUsageReader.defaultSessionRoots(),
        authFile: URL? = CodexUsageReader.defaultAuthFile(),
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) {
        self.sessionRoots = sessionRoots
        self.authFile = authFile
        self.fileManager = fileManager
        self.calendar = calendar
    }

    public func read() throws -> CodexUsageSnapshot {
        var latest: ParsedTokenCount?
        var todayTokens = 0
        let today = calendar.startOfDay(for: Date())
        let oldestUsefulModificationDate = calendar.date(byAdding: .day, value: -8, to: today) ?? today

        for file in sessionFiles(modifiedAfter: oldestUsefulModificationDate) {
            guard let stream = InputStream(url: file) else { continue }
            stream.open()
            defer { stream.close() }

            for line in LineReader(stream: stream) where line.contains(#""token_count""#) {
                guard let event = ParsedTokenCount(line: line, sourceFile: file.path(percentEncoded: false)) else {
                    continue
                }
                if calendar.startOfDay(for: event.timestamp) == today {
                    todayTokens += event.lastTokens
                }
                if latest == nil || event.timestamp > latest!.timestamp {
                    latest = event
                }
            }
        }

        guard let latest else {
            throw CodexUsageError.noReadableSessionData
        }

        return CodexUsageSnapshot(
            primary: latest.primary,
            secondary: latest.secondary,
            todayTokens: todayTokens,
            totalTokens: latest.totalTokens,
            planType: latest.planType,
            accountLabel: readAccountLabel(),
            lastUpdated: latest.timestamp,
            sourceFile: latest.sourceFile
        )
    }

    public static func defaultSessionRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: ".codex/sessions", directoryHint: .isDirectory),
            home.appending(path: ".codex/archived_sessions", directoryHint: .isDirectory)
        ]
    }

    public static func defaultAuthFile() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")
    }

    private func sessionFiles(modifiedAfter cutoff: Date) -> [URL] {
        sessionRoots.flatMap { root -> [URL] in
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            return enumerator.compactMap { item -> URL? in
                guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else { return nil }
                if let modified = values?.contentModificationDate, modified < cutoff {
                    return nil
                }
                return url
            }
        }
    }

    private func readAccountLabel() -> String? {
        guard let authFile,
              let data = try? Data(contentsOf: authFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let tokens = object["tokens"] as? [String: Any]
        if let idToken = tokens?["id_token"] as? String,
           let email = JWTClaims(token: idToken).email,
           !email.isEmpty {
            return email
        }

        if let accountID = tokens?["account_id"] as? String, !accountID.isEmpty {
            return accountID
        }

        return object["auth_mode"] as? String
    }
}

private struct ParsedTokenCount {
    let timestamp: Date
    let totalTokens: Int
    let lastTokens: Int
    let primary: UsageWindow
    let secondary: UsageWindow
    let planType: String?
    let sourceFile: String

    init?(line: String, sourceFile: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestampValue = object["timestamp"] as? String,
              let timestamp = DateParser.parse(timestampValue),
              let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let rateLimits = payload["rate_limits"] as? [String: Any],
              let totalUsage = info["total_token_usage"] as? [String: Any],
              let lastUsage = info["last_token_usage"] as? [String: Any],
              let totalTokens = totalUsage["total_tokens"] as? Int,
              let lastTokens = lastUsage["total_tokens"] as? Int,
              let primaryObject = rateLimits["primary"] as? [String: Any],
              let secondaryObject = rateLimits["secondary"] as? [String: Any],
              let primary = UsageWindow(json: primaryObject),
              let secondary = UsageWindow(json: secondaryObject)
        else {
            return nil
        }

        self.timestamp = timestamp
        self.totalTokens = totalTokens
        self.lastTokens = lastTokens
        self.primary = primary
        self.secondary = secondary
        self.planType = rateLimits["plan_type"] as? String
        self.sourceFile = sourceFile
    }
}

private extension UsageWindow {
    init?(json: [String: Any]) {
        guard let usedPercent = json["used_percent"] as? Double,
              let windowMinutes = json["window_minutes"] as? Int
        else {
            return nil
        }

        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        if let resetSeconds = json["resets_at"] as? TimeInterval {
            self.resetsAt = Date(timeIntervalSince1970: resetSeconds)
        } else {
            self.resetsAt = nil
        }
    }
}

private enum DateParser {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain = ISO8601DateFormatter()

    static func parse(_ value: String) -> Date? {
        fractional.date(from: value) ?? plain.date(from: value)
    }
}

private struct JWTClaims {
    let token: String

    var email: String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2,
              let payload = decodeBase64URL(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else {
            return nil
        }
        return object["email"] as? String
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        return Data(base64Encoded: base64)
    }
}

private struct LineReader: Sequence, IteratorProtocol {
    private let stream: InputStream
    private var buffer = Data()
    private var pending = Data()
    private var chunk = [UInt8](repeating: 0, count: 64 * 1024)
    private var reachedEOF = false

    init(stream: InputStream) {
        self.stream = stream
    }

    mutating func next() -> String? {
        while true {
            if let newline = pending.firstIndex(of: 10) {
                buffer.append(pending.prefix(upTo: newline))
                pending.removeSubrange(...newline)
                return String(data: bufferAndReset(), encoding: .utf8)
            }

            buffer.append(pending)
            pending.removeAll(keepingCapacity: true)

            guard !reachedEOF else {
                guard !buffer.isEmpty else { return nil }
                return String(data: bufferAndReset(), encoding: .utf8)
            }

            let count = stream.read(&chunk, maxLength: chunk.count)
            if count > 0 {
                pending.append(chunk, count: count)
            } else {
                reachedEOF = true
            }
        }
    }

    private mutating func bufferAndReset() -> Data {
        let data = buffer
        buffer.removeAll(keepingCapacity: true)
        return data
    }
}
