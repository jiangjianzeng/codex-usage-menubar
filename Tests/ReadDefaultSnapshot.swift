import Foundation

@main
struct ReadDefaultSnapshot {
    static func main() {
        do {
            let snapshot = try CodexUsageReader().read()
            print("rateLimitsAvailable=\(snapshot.rateLimitsAvailable) primary=\(snapshot.primary.remainingPercent) secondary=\(snapshot.secondary.remainingPercent) today=\(snapshot.todayTokens)")
        } catch {
            print("error=\(error.localizedDescription)")
        }
    }
}
