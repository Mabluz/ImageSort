import Testing
import Foundation
@testable import ImageSort

@Suite struct GroupingTests {
    @Test func timeClustersSplitOnGap() {
        let t0 = Date(timeIntervalSince1970: 0)
        let dates = [0, 2, 5, 200, 201, 1000].map { t0.addingTimeInterval($0) }
        #expect(SimilarityGrouper.timeClusters(dates: dates, maxGap: 90) == [[0, 1, 2], [3, 4], [5]])
    }

    @Test func timeClustersEmpty() {
        #expect(SimilarityGrouper.timeClusters(dates: [], maxGap: 90).isEmpty)
    }

    @Test func clusterIsTransitive() {
        // 0~1, 1~2 (men 0 og 2 er langt fra hverandre) => én gruppe. 3 alene.
        let d: [[Float]] = [
            [0, 0.3, 0.9, 1.5],
            [0.3, 0, 0.3, 1.5],
            [0.9, 0.3, 0, 1.5],
            [1.5, 1.5, 1.5, 0],
        ]
        let groups = SimilarityGrouper.cluster(count: 4, threshold: 0.5) { d[$0][$1] }
        #expect(groups == [[0, 1, 2], [3]])
    }

    @Test func clusterIgnoresMissingPrints() {
        let groups = SimilarityGrouper.cluster(count: 3, threshold: 0.5) { _, _ in nil }
        #expect(groups == [[0], [1], [2]])
    }

    @Test func clusterRespectsWindow() {
        let groups = SimilarityGrouper.cluster(count: 3, window: 1, threshold: 0.5) { a, b in
            (a, b) == (0, 2) ? 0.1 : 2
        }
        #expect(groups.count == 3)
    }
}

@Suite struct RankingTests {
    @Test func sharperWinsWithoutFaces() {
        let blurry = PhotoAnalysis(aesthetics: 0.2, sharpness: 50)
        let sharp = PhotoAnalysis(aesthetics: 0.2, sharpness: 500)
        let s = Ranking.score([blurry, sharp])
        #expect(s[1].total > s[0].total)
        #expect(s[0].reasons.contains("uskarpt"))
        #expect(s[1].reasons.contains("skarpest"))
    }

    @Test func closedEyesArePenalised() {
        let open = PhotoAnalysis(aesthetics: 0.3, sharpness: 400, faceQualities: [0.6])
        let closed = PhotoAnalysis(aesthetics: 0.3, sharpness: 400, faceQualities: [0.6], eyesClosedCount: 1)
        let s = Ranking.score([open, closed])
        #expect(s[0].total > s[1].total)
        #expect(s[1].reasons.contains("øyne lukket"))
    }

    @Test func scoresAreClamped() {
        let a = PhotoAnalysis(aesthetics: -1, sharpness: 0, faceQualities: [], eyesClosedCount: 5)
        let b = PhotoAnalysis(aesthetics: 1, sharpness: 100, faceQualities: [1])
        for s in Ranking.score([a, b]) { #expect((0...100).contains(s.total)) }
    }

    @Test func emptyInput() { #expect(Ranking.score([]).isEmpty) }
}

@Suite struct ClaudeParsingTests {
    @Test func parsesCliEnvelope() throws {
        let inner = #"Her er svaret: {"best": 2, "ranking": [2, 1, 3], "comment": "Skarpest og smiler."}"#
        let env = try String(data: JSONSerialization.data(withJSONObject: ["type": "result", "is_error": false, "result": inner]), encoding: .utf8)!
        let v = try ClaudeAdvisor.parse(output: env, count: 3)
        #expect(v == ClaudeVerdict(best: 1, ranking: [1, 0, 2], comment: "Skarpest og smiler."))
    }

    @Test func parsesBareJSON() throws {
        let v = try ClaudeAdvisor.parse(output: #"{"best":1,"comment":"ok"}"#, count: 2)
        #expect(v.best == 0)
        #expect(v.ranking.isEmpty)
    }

    @Test func rejectsOutOfRange() {
        #expect(throws: ClaudeError.self) { try ClaudeAdvisor.parse(output: #"{"best": 9}"#, count: 3) }
    }

    @Test func rejectsCliError() {
        let env = #"{"type":"result","is_error":true,"result":"Not logged in"}"#
        #expect(throws: ClaudeError.self) { try ClaudeAdvisor.parse(output: env, count: 3) }
    }
}

@Suite struct CacheTests {
    @Test func keyChangesWithModification() {
        let d = Date(timeIntervalSince1970: 1000)
        let a = AnalysisCache.key(path: "/a.jpg", modificationDate: d, size: 10)
        #expect(a != AnalysisCache.key(path: "/a.jpg", modificationDate: d.addingTimeInterval(1), size: 10))
        #expect(a != AnalysisCache.key(path: "/a.jpg", modificationDate: d, size: 11))
        #expect(a == AnalysisCache.key(path: "/a.jpg", modificationDate: d, size: 10))
    }

    @Test func roundTripsToDisk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("imagesort-test-\(UUID()).plist")
        defer { try? FileManager.default.removeItem(at: file) }
        let photo = Photo(url: URL(fileURLWithPath: "/x.jpg"), captureDate: .now, fileSize: 5, modificationDate: .now)
        let c1 = AnalysisCache(fileURL: file)
        c1.set(PhotoAnalysis(aesthetics: 0.5, sharpness: 12), for: photo)
        c1.save()
        let c2 = AnalysisCache(fileURL: file)
        #expect(c2.get(photo)?.sharpness == 12)
    }
}

@Suite struct FileNameDateTests {
    private func parts(_ name: String) -> [Int]? {
        guard let d = FolderScanner.dateFromFileName(name) else { return nil }
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        return [c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!]
    }

    @Test(arguments: [
        "20261121_164418.jpg",
        "20261121_164418(0).jpg",
        "IMG_20261121_164418.jpg",
        "PXL_20261121_164418123.jpg",
        "2026-11-21 16.44.18.jpg",
        "Screenshot 2026-11-21 at 16.44.18.png",
    ])
    func parsesCommonPatterns(_ name: String) {
        #expect(parts(name) == [2026, 11, 21, 16, 44, 18])
    }

    @Test func rejectsNonDates() {
        #expect(parts("IMG_1234.jpg") == nil)
        #expect(parts("20261399_999999.jpg") == nil)
    }
}

@Suite struct SharpnessTests {
    @Test func flatImageHasZeroVariance() {
        let px = [UInt8](repeating: 128, count: 100)
        #expect(Sharpness.laplacianVariance(gray: px, width: 10, height: 10) == 0)
    }

    @Test func edgesIncreaseVariance() {
        var px = [UInt8](repeating: 0, count: 100)
        for i in stride(from: 0, to: 100, by: 2) { px[i] = 255 }
        #expect(Sharpness.laplacianVariance(gray: px, width: 10, height: 10) > 1000)
    }
}

@Suite struct CollectionTests {
    @Test func fileNameUsesSourceFolderDateAndOriginalName() {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 21; c.hour = 16; c.minute = 44; c.second = 18
        let date = Calendar.current.date(from: c)!
        let photo = Photo(url: URL(fileURLWithPath: "/Users/x/Desktop/ImageSort-test/20261121_164418.jpg"),
                          captureDate: date, fileSize: 1, modificationDate: date)
        let collection = URL(fileURLWithPath: "/Users/x/Julekalender2026")
        #expect(CollectionService.fileName(for: photo, in: collection)
                == "ImageSort-test_2026-11-21_16-44-18_20261121_164418.jpg")
        #expect(CollectionService.fileName(prefix: "Bok 2026/vår", captureDate: date, originalName: "a.heic")
                == "Bok 2026-vår_2026-11-21_16-44-18_a.heic")
    }

    @Test func recognisesLegacyCollectionPrefixedNames() {
        let photo = Photo(url: URL(fileURLWithPath: "/a/ImageSort-test/x.jpg"), captureDate: Date(timeIntervalSince1970: 0),
                          fileSize: 1, modificationDate: .now)
        let folder = URL(fileURLWithPath: "/b/Tester")
        let legacy = CollectionService.legacyFileName(for: photo, in: folder)
        #expect(legacy.hasPrefix("Tester_"))
        #expect(CollectionService.existingName(for: photo, in: folder, names: [legacy]) == legacy)
        #expect(CollectionService.existingName(for: photo, in: folder, names: []) == nil)
    }

    @Test func addAndRemoveCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("imagesort-col-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("bilder/IMG_1.jpg")
        try FileManager.default.createDirectory(at: src.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: src)
        let folder = root.appendingPathComponent("Julekalender2026")
        let photo = Photo(url: src, captureDate: Date(timeIntervalSince1970: 0), fileSize: 1, modificationDate: .now)

        try CollectionService.add(photo, to: folder)
        try CollectionService.add(photo, to: folder) // idempotent
        let name = CollectionService.fileName(for: photo, in: folder)
        #expect(CollectionService.existingNames(in: folder) == [name])
        #expect(FileManager.default.fileExists(atPath: src.path), "originalen skal ikke røres")

        try CollectionService.remove(photo, from: folder)
        #expect(CollectionService.existingNames(in: folder).isEmpty)
    }
}

@Suite struct OnlySelectedNavigationTests {
    @Test func togglesBetweenTwoSelected() {
        let sel = [false, true, false, false, true]
        #expect(LibraryViewModel.nextSelectedIndex(from: 1, delta: 1, selected: sel) == 4)
        #expect(LibraryViewModel.nextSelectedIndex(from: 4, delta: 1, selected: sel) == 1)  // går rundt
        #expect(LibraryViewModel.nextSelectedIndex(from: 1, delta: -1, selected: sel) == 4)
    }

    @Test func jumpsFromUnselectedToNearestSelected() {
        let sel = [false, true, false, false, true]
        #expect(LibraryViewModel.nextSelectedIndex(from: 2, delta: 1, selected: sel) == 4)
        #expect(LibraryViewModel.nextSelectedIndex(from: 2, delta: -1, selected: sel) == 1)
    }

    @Test func nilWhenNoOtherSelected() {
        #expect(LibraryViewModel.nextSelectedIndex(from: 1, delta: 1, selected: [false, true]) == nil)
        #expect(LibraryViewModel.nextSelectedIndex(from: 0, delta: 1, selected: [false, false]) == nil)
    }
}

@Suite struct SingleGroupsTests {
    private func photo(_ name: String, _ y: Int, _ m: Int, _ d: Int) -> Photo {
        let date = Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
        return Photo(url: URL(fileURLWithPath: "/\(name).jpg"), captureDate: date, fileSize: 1, modificationDate: date)
    }

    @Test @MainActor func splitsPerMonthSortedAndNeverReviewable() {
        let groups = LibraryViewModel.singleGroups([
            photo("c", 2026, 11, 20), photo("a", 2026, 10, 3), photo("b", 2026, 11, 2),
        ]).sorted { $0.date < $1.date }
        #expect(groups.count == 2)
        #expect(groups[0].title == "oktober 2026")
        #expect(groups[1].photos.map(\.fileName) == ["b.jpg", "c.jpg"])
        #expect(groups.allSatisfy { $0.kind == .singles && !$0.isReviewable })
    }
}
