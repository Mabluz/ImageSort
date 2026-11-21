import Foundation

struct TrashedItem: Sendable {
    let original: URL
    let trashed: URL
    let photo: Photo
}

enum TrashService {
    /// Flytter filer til Papirkurven. Returnerer det som lyktes og feil for resten.
    static func trash(_ photos: [Photo]) -> (done: [TrashedItem], failed: [(Photo, Error)]) {
        var done: [TrashedItem] = []
        var failed: [(Photo, Error)] = []
        for photo in photos {
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: photo.url, resultingItemURL: &resulting)
                if let r = resulting as URL? {
                    done.append(TrashedItem(original: photo.url, trashed: r, photo: photo))
                }
            } catch {
                failed.append((photo, error))
            }
        }
        return (done, failed)
    }

    /// Legger filer tilbake der de var.
    static func restore(_ items: [TrashedItem]) -> [TrashedItem] {
        var restored: [TrashedItem] = []
        for item in items {
            do {
                try FileManager.default.createDirectory(at: item.original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: item.trashed, to: item.original)
                restored.append(item)
            } catch {
                NSLog("ImageSort: kunne ikke gjenopprette \(item.original.path): \(error)")
            }
        }
        return restored
    }
}
