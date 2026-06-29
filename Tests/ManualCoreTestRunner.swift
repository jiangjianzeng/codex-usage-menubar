import Foundation

@main
struct ManualCoreTestRunner {
    static func main() throws {
        try latestTokenCountEventDrivesSnapshot()
        try rateLimitNumbersAcceptIntegerAndRemainingPercent()
        try todayTokenTotalSumsLocalDayDeltas()
        try accountIDIsReadFromAuthFile()
        print("Manual core tests passed")
    }

    private static func latestTokenCountEventDrivesSnapshot() throws {
        let directory = try makeTemporaryDirectory()
        let session = directory.appending(path: "session.jsonl")
        let today = Calendar.current.startOfDay(for: Date())
        let olderStamp = iso.string(from: today.addingTimeInterval(60))
        let newerStamp = iso.string(from: today.addingTimeInterval(120))
        try [
            tokenCountLine(timestamp: olderStamp, totalTokens: 100, lastTokens: 50, primaryUsed: 10, secondaryUsed: 20),
            tokenCountLine(timestamp: newerStamp, totalTokens: 420, lastTokens: 75, primaryUsed: 36, secondaryUsed: 48)
        ].joined(separator: "\n").write(to: session, atomically: true, encoding: .utf8)

        let snapshot = try CodexUsageReader(sessionRoots: [directory], authFile: nil).read()
        try expect(snapshot.primary.usedPercent == 36, "primary used percent")
        try expect(snapshot.primary.remainingPercent == 64, "primary remaining percent")
        try expect(snapshot.secondary.usedPercent == 48, "secondary used percent")
        try expect(snapshot.secondary.remainingPercent == 52, "secondary remaining percent")
        try expect(snapshot.todayTokens == 125, "fixture day token total")
        try expect(snapshot.totalTokens == 420, "total tokens")
    }

    private static func rateLimitNumbersAcceptIntegerAndRemainingPercent() throws {
        let directory = try makeTemporaryDirectory()
        let session = directory.appending(path: "session.jsonl")
        let stamp = iso.string(from: Calendar.current.startOfDay(for: Date()).addingTimeInterval(60))
        let line = """
        {"timestamp":"\(stamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":100},"last_token_usage":{"total_tokens":20}},"rate_limits":{"primary":{"used_percent":6,"window_minutes":300,"resets_at":"1782310000"},"secondary":{"remaining_percent":55,"window_minutes":10080,"resets_at":1782880000},"plan_type":"pro"}}}
        """
        try line.write(to: session, atomically: true, encoding: .utf8)

        let snapshot = try CodexUsageReader(sessionRoots: [directory], authFile: nil).read()
        try expect(snapshot.primary.remainingPercent == 94, "integer used percent")
        try expect(snapshot.secondary.usedPercent == 45, "remaining percent fallback")
        try expect(snapshot.secondary.remainingPercent == 55, "remaining percent value")
    }

    private static func todayTokenTotalSumsLocalDayDeltas() throws {
        let directory = try makeTemporaryDirectory()
        let session = directory.appending(path: "session.jsonl")
        let today = Calendar.current.startOfDay(for: Date())
        let todayStamp = iso.string(from: today.addingTimeInterval(60))
        let yesterdayStamp = iso.string(from: today.addingTimeInterval(-60))
        try [
            tokenCountLine(timestamp: yesterdayStamp, totalTokens: 10, lastTokens: 10),
            tokenCountLine(timestamp: todayStamp, totalTokens: 50, lastTokens: 15),
            tokenCountLine(timestamp: todayStamp, totalTokens: 80, lastTokens: 30)
        ].joined(separator: "\n").write(to: session, atomically: true, encoding: .utf8)

        let snapshot = try CodexUsageReader(sessionRoots: [directory], authFile: nil).read()
        try expect(snapshot.todayTokens == 45, "today token sum")
    }

    private static func accountIDIsReadFromAuthFile() throws {
        let directory = try makeTemporaryDirectory()
        let session = directory.appending(path: "session.jsonl")
        let auth = directory.appending(path: "auth.json")
        try tokenCountLine(timestamp: "2026-06-24T09:10:00.000Z").write(to: session, atomically: true, encoding: .utf8)
        try #"{"tokens":{"account_id":"acct_123"},"auth_mode":"chatgpt"}"#.write(to: auth, atomically: true, encoding: .utf8)

        let snapshot = try CodexUsageReader(sessionRoots: [directory], authFile: auth).read()
        try expect(snapshot.accountLabel == "acct_123", "account id")
    }

    private static func expect(_ condition: Bool, _ label: String) throws {
        if !condition {
            throw TestFailure(label)
        }
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func tokenCountLine(
        timestamp: String,
        totalTokens: Int = 100,
        lastTokens: Int = 20,
        primaryUsed: Double = 25,
        secondaryUsed: Double = 40
    ) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\(totalTokens)},"last_token_usage":{"total_tokens":\(lastTokens)}},"rate_limits":{"primary":{"used_percent":\(primaryUsed),"window_minutes":300,"resets_at":1782310000},"secondary":{"used_percent":\(secondaryUsed),"window_minutes":10080,"resets_at":1782880000},"plan_type":"pro"}}}
        """
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
