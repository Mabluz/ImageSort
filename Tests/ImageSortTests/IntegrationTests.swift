import Testing
import Foundation
import CoreGraphics
import ImageIO
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

@Suite(.serialized) struct SingleDeleteIntegrationTests {
    /// Lager et JPEG med et gitt mønster (så bildene ikke ligner hverandre).
    private func writeJPEG(_ url: URL, pattern: Int) throws {
        let w = 256, h = 192
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            switch pattern {
            case 0: px[i] = 230; px[i + 1] = 30; px[i + 2] = 30                     // rød flate
            case 1: let c: UInt8 = ((x / 16 + y / 16) % 2 == 0) ? 255 : 0; px[i] = c; px[i + 1] = c; px[i + 2] = c  // sjakk
            default: px[i] = UInt8(x); px[i + 1] = UInt8(y); px[i + 2] = 200        // gradient
            }
            px[i + 3] = 255
        } }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    /// Lager bilder og legger inn kjente analyseverdier i cachen, så testen ikke avhenger av Vision.
    private func makeLibrary(_ files: [(String, Double)]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("imagesort-single-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, f) in files.enumerated() { try writeJPEG(dir.appendingPathComponent(f.0), pattern: i % 3) }
        let sharpness = Dictionary(uniqueKeysWithValues: files)
        for p in FolderScanner.scan(dir) {
            AnalysisCache.shared.set(PhotoAnalysis(aesthetics: 0.3, sharpness: sharpness[p.fileName]!), for: p)
        }
        return dir
    }

    @MainActor private func openAndWait(_ dir: URL) async throws -> LibraryViewModel {
        let vm = LibraryViewModel()
        vm.open(dir)
        for _ in 0..<200 where vm.phase != .ready { try await Task.sleep(for: .milliseconds(50)) }
        #expect(vm.phase == .ready)
        return vm
    }

    @Test @MainActor func trashAndUndoSinglePhoto() async throws {
        // Ulike måneder (fra filnavn) => egne enkeltbilde-grupper. Alle skarpe.
        let dir = try makeLibrary([("20261001_120000.jpg", 500), ("20261101_120000.jpg", 500), ("20261102_120000.jpg", 500)])
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("20261001_120000.jpg")
        let b = dir.appendingPathComponent("20261101_120000.jpg")
        let c = dir.appendingPathComponent("20261102_120000.jpg")

        let vm = try await openAndWait(dir)
        #expect(vm.singleCount == 3)
        #expect(vm.pendingGroups.isEmpty)
        #expect(vm.junkGroups.isEmpty)

        // Slett b i november-gruppen.
        let nov = try #require(vm.singleGroups.first { $0.photos.count == 2 })
        vm.select(group: nov.id)
        vm.focusedIndex = 0
        vm.trashFocused()
        #expect(!FileManager.default.fileExists(atPath: b.path))
        #expect(vm.singleCount == 2)
        #expect(vm.selectedGroup?.photos.map(\.fileName) == [c.lastPathComponent])

        vm.undo()
        #expect(FileManager.default.fileExists(atPath: b.path))
        #expect(vm.selectedGroup?.photos.map(\.fileName) == [b.lastPathComponent, c.lastPathComponent])
        #expect(vm.focusedIndex == 0)

        // Slett eneste bilde i oktober: gruppen forsvinner, angre gjenoppretter den.
        let oct = try #require(vm.singleGroups.first { $0.photos.count == 1 })
        vm.select(group: oct.id)
        vm.trashFocused()
        #expect(vm.singleGroups.count == 1)
        vm.undo()
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(vm.singleGroups.count == 2)
        #expect(vm.selectedGroup?.photos.map(\.fileName) == [a.lastPathComponent])
    }

    @Test @MainActor func likelyBadGroupKeepsSelectedAndTrashesRest() async throws {
        let dir = try makeLibrary([("20261001_120000.jpg", 40), ("20261002_120000.jpg", 60), ("20261003_120000.jpg", 500)])
        defer { try? FileManager.default.removeItem(at: dir) }
        let blurry1 = dir.appendingPathComponent("20261001_120000.jpg")
        let blurry2 = dir.appendingPathComponent("20261002_120000.jpg")

        let vm = try await openAndWait(dir)
        let junk = try #require(vm.junkGroups.first)
        #expect(junk.photos.map(\.fileName) == [blurry1.lastPathComponent, blurry2.lastPathComponent])
        #expect(junk.selected.isEmpty, "ingenting beholdes før brukeren velger")
        #expect(junk.scores[junk.photos[0].url]?.reasons.contains("uskarpt") == true)
        #expect(vm.singleCount == 1)
        #expect(vm.pendingGroups.isEmpty, "listen skal ikke vises som serie")

        // Behold det ene, slett resten (krever alltid bekreftelse).
        vm.select(group: junk.id)
        vm.toggle(junk.photos[1].url)
        vm.requestConfirm()
        let pending = try #require(vm.pendingConfirmGroupID)
        vm.confirm(groupID: pending)
        #expect(!FileManager.default.fileExists(atPath: blurry1.path))
        #expect(FileManager.default.fileExists(atPath: blurry2.path))
        #expect(vm.junkGroups.isEmpty)
        #expect(vm.singleCount == 2, "det beholdte bildet går tilbake til måneden sin")

        vm.undo()
        #expect(FileManager.default.fileExists(atPath: blurry1.path))
        #expect(vm.junkGroups.first?.photos.map(\.fileName) == [blurry1.lastPathComponent])
    }
}
