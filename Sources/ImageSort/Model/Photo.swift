import Foundation

/// Ett bilde på disk.
struct Photo: Identifiable, Hashable, Sendable {
    let url: URL
    let captureDate: Date
    let fileSize: Int64
    let modificationDate: Date

    var id: URL { url }
    var fileName: String { url.lastPathComponent }
}

/// Rå analyse av ett bilde (lagres i cache).
struct PhotoAnalysis: Codable, Hashable, Sendable {
    /// Øk når analysen endres, så gamle cache-oppføringer analyseres på nytt.
    static let currentVersion = 2
    var version: Int? = PhotoAnalysis.currentVersion
    /// Arkivert VNFeaturePrintObservation.
    var featurePrint: Data?
    /// Apple estetikk-score, -1...1.
    var aesthetics: Float?
    var isUtility: Bool = false
    /// Laplace-varians (høyere = skarpere).
    var sharpness: Double = 0
    /// Ansiktskvalitet 0...1 per (stort nok) ansikt.
    var faceQualities: [Float] = []
    /// Antall ansikter der øynene ser lukket ut.
    var eyesClosedCount: Int = 0
}

/// Gruppe-relativ score for et bilde.
struct PhotoScore: Hashable, Sendable {
    var total: Double
    var reasons: [String]
}

enum GroupStatus: String, Sendable {
    case pending, done, skipped
}

enum GroupKind: Sendable {
    /// Serie med like bilder: velg det beste, resten kan slettes.
    case series
    /// Enkeltbilder (per måned): bla, merke til samling og slette enkeltvis.
    case singles
    /// Enkeltbilder som sannsynligvis er dårlige (uskarpe osv.). Valgte beholdes, resten kan slettes.
    case junk
}

/// En serie like bilder.
struct PhotoGroup: Identifiable, Sendable {
    let id = UUID()
    var photos: [Photo]
    var scores: [URL: PhotoScore] = [:]
    var suggested: URL?
    var selected: Set<URL> = []
    var status: GroupStatus = .pending
    var claudePick: URL?
    var claudeComment: String?
    var kind: GroupKind = .series
    var title: String?

    /// Kan man velge/slette i denne gruppen?
    var isReviewable: Bool { kind != .singles && status == .pending }

    var date: Date { photos.first?.captureDate ?? .distantPast }
    var totalBytes: Int64 { photos.reduce(0) { $0 + $1.fileSize } }
}
