import Foundation
import Testing
@testable import CodexUsageCore

@Suite("Codex usage parsing")
struct CodexUsageParserTests {
    @Test("latest token_count event drives five hour and weekly usage")
    func latestTokenCountEventDrivesSnapshot() throws {
        let directory = try TestFiles.makeTemporaryDirectory()
        let session = directory.appending(path: "session.jsonl")
        let today = Calendar.current.startOfDay(for: Date())
        let olderStamp = ISO8601DateFormatter.codex.string(from: today.addingTimeInterval(60))
        let newerStamp = ISO8601DateFormatter.codex.string(from: today.addingTimeInterval(120))
        let older = tokenCountLine(
            timestamp: olderStamp,
            totalTokens: 100,
            lastTokens: 50,
            primaryUsed: 10,
            primaryWindow: 300,
            primaryReset: 1_782_300_000,
            secondaryUsed: 20,
            secondaryWindow: 10_080,
            secondaryReset: 1_782_900_000,
            planType: "pro"
        )
        let newer = tokenCountLine(
            timestamp: newerStamp,
            totalTokens: 420,
            lastTokens: 75,
            primaryUsed: 36,
            primaryWindow: 300,
            primaryReset: 1_782_310_000,
            secondaryUsed: 48,
            secondaryWindow: 10_080,
            secondaryReset: 1_782_880_000,
            planType: "pro"
        )
        try [older, newer].joined(separator: "\n").write(to: session, atomically: true, encoding: .utf8)

        let snapshot = try CodexUsageReader(sessionRoots: [directory], authFile: nil).read()

        #expect(snapshot.primary.usedPercent == 36)
        #expect(snapshot.primary.remainingPercent == 64)
        #expect(snapshot.primary.windowMinutes == 300)
        #expect(snapshot.secondary.usedPercent == 48)
        #expect(snapshot.secondary.remainingPercent == 52)
        #expect(snapshot.todayTokens == 125)
        #expect(snapshot.totalTokens == 420)
        #expect(snapshot.planType == "pro")
    }

    @Test("today token total sums token_count deltas on local calendar day")
    func todayTokenTotalSumsLocalDayDeltas() throws {
        let directory = try TestFiles.makeTemporaryDirectory()
        let session = directory.appending(path: "session.jsonl")
        let today = Calendar.current.startOfDay(for: Date())
        let todayStamp = ISO8601DateFormatter.codex.string(from: today.addingTimeInterval(60))
        let yesterdayStamp = ISO8601DateFormatter.codex.string(from: today.addingTimeInterval(-60))

        try [
            tokenCountLine(timestamp: yesterdayStamp, totalTokens: 10, lastTokens: 10),
            tokenCountLine(timestamp: todayStamp, totalTokens: 50, lastTokens: 15),
            tokenCountLine(timestamp: todayStamp, totalTokens: 80, lastTokens: 30)
        ].joined(separator: "\n").write(to: session, atomically: true, encoding: .utf8)

        let snapshot = try CodexUsageReader(sessionRoots: [directory], authFile: nil).read()

        #expect(snapshot.todayTokens == 45)
    }

    @Test("account id is read without requiring token secrets")
    func accountIDIsReadFromAuthFile() throws {
        let directory = try TestFiles.makeTemporaryDirectory()
        let session = directory.appending(path: "session.jsonl")
        let auth = directory.appending(path: "auth.json")
        try tokenCountLine(timestamp: "2026-06-24T09:10:00.000Z").write(to: session, atomically: true, encoding: .utf8)
        try #"{"tokens":{"account_id":"acct_123"},"auth_mode":"chatgpt"}"#.write(to: auth, atomically: true, encoding: .utf8)

        let snapshot = try CodexUsageReader(sessionRoots: [directory], authFile: auth).read()

        #expect(snapshot.accountLabel == "acct_123")
    }
}

private enum TestFiles {
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private func tokenCountLine(
    timestamp: String,
    totalTokens: Int = 100,
    lastTokens: Int = 20,
    primaryUsed: Double = 25,
    primaryWindow: Int = 300,
    primaryReset: Int = 1_782_310_000,
    secondaryUsed: Double = 40,
    secondaryWindow: Int = 10_080,
    secondaryReset: Int = 1_782_880_000,
    planType: String = "pro"
) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":\(totalTokens)},"last_token_usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0,"total_tokens":\(lastTokens)},"model_context_window":237500},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":\(primaryUsed),"window_minutes":\(primaryWindow),"resets_at":\(primaryReset)},"secondary":{"used_percent":\(secondaryUsed),"window_minutes":\(secondaryWindow),"resets_at":\(secondaryReset)},"credits":null,"individual_limit":null,"plan_type":"\(planType)","rate_limit_reached_type":null}}}
    """
}

private extension ISO8601DateFormatter {
    static let codex: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
