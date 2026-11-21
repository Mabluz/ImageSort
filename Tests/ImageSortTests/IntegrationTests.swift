import Testing
import Foundation
@testable import ImageSort

@Suite struct TrashIntegrationTests {
    @Test func trashAndRestoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("imagesort-trash-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.jpg")
        try Data("hei".utf8).write(to: url)
        let photo = Photo(url: url, captureDate: .now, fileSize: 3, modificationDate: .now)

        let result = TrashService.trash([photo])
        #expect(result.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let restored = TrashService.restore(result.done)
        #expect(restored.count == 1)
        #expect(try String(contentsOf: url, encoding: .utf8) == "hei")
    }
}

/// Manuell: IMAGESORT_CLAUDE_DIR=/mappe swift test --filter ClaudeLive
@Suite struct ClaudeLive {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["IMAGESORT_CLAUDE_DIR"] != nil))
    func asksClaude() async throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["IMAGESORT_CLAUDE_DIR"]!)
        let urls = FolderScanner.scan(dir).map(\.url)
        let start = Date()
        let v = try await ClaudeAdvisor.ask(about: urls, model: "sonnet")
        print("Claude (\(Int(Date().timeIntervalSince(start))) s): best=\(urls[v.best].lastPathComponent) ranking=\(v.ranking.map { urls[$0].lastPathComponent }) – \(v.comment)")
    }
}
