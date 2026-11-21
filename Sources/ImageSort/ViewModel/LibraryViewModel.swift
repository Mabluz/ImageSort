import AppKit
import Observation
import Vision

enum Settings {
    static let timeGapKey = "timeGapSeconds"
    static let thresholdKey = "similarityThreshold"
    static let claudeModelKey = "claudeModel"
    static let preselectKey = "preselectBest"
    static let confirmedOnceKey = "confirmedTrashOnce"
    static let collectionKey = "activeCollectionPath"
    static let recentCollectionsKey = "recentCollectionPaths"

    static let defaultTimeGap = 90.0
    /// Kalibrert på ekte serier: samme motiv ~0.1–0.4, annet motiv i samme rom ~0.64+.
    static let defaultThreshold = 0.6
    static let defaultModel = "sonnet"

    static func register() {
        UserDefaults.standard.register(defaults: [
            timeGapKey: defaultTimeGap,
            thresholdKey: defaultThreshold,
            claudeModelKey: defaultModel,
            preselectKey: true,
            confirmedOnceKey: false,
        ])
    }
}

enum Phase: Equatable {
    case idle
    case scanning
    case analyzing(done: Int, total: Int)
    case ready
}

private struct UndoRecord {
    let groupID: UUID
    let items: [TrashedItem]
    let previousStatus: GroupStatus
}

@MainActor
@Observable
final class LibraryViewModel {
    var rootURL: URL?
    var phase: Phase = .idle
    var groups: [PhotoGroup] = []
    var selectedGroupID: UUID?
    var focusedIndex = 0
    var showPreview = false
    var zoomCommand: ZoomCommand?
    var errorMessage: String?
    var claudeBusy: Set<UUID> = []
    var pendingConfirmGroupID: UUID?
    var pendingDeleteAllGroupID: UUID?
    var totalPhotos = 0

    private(set) var trashedCount = 0
    private(set) var trashedBytes: Int64 = 0
    private var undoStack: [UndoRecord] = []

    private var photos: [Photo] = []
    private var analyses: [URL: PhotoAnalysis] = [:]
    private var featurePrints: [URL: VNFeaturePrintObservation] = [:]
    /// Bilder i grupper som er ferdig behandlet (tas ikke med ved ny gruppering).
    private var reviewed: Set<URL> = []
    private var loadTask: Task<Void, Never>?

    // MARK: Samling (f.eks. «Julekalender2026»)
    private(set) var collectionURL: URL?
    private(set) var recentCollections: [URL] = []
    private(set) var collectionNames: Set<String> = []
    var collectionName: String? { collectionURL?.lastPathComponent }

    init() {
        let d = UserDefaults.standard
        recentCollections = (d.stringArray(forKey: Settings.recentCollectionsKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if let path = d.string(forKey: Settings.collectionKey), FileManager.default.fileExists(atPath: path) {
            collectionURL = URL(fileURLWithPath: path)
            refreshCollection()
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var pendingGroups: [PhotoGroup] { groups.filter { $0.status == .pending } }
    var finishedGroups: [PhotoGroup] { groups.filter { $0.status != .pending } }

    var selectedGroup: PhotoGroup? {
        guard let id = selectedGroupID else { return nil }
        return groups.first { $0.id == id }
    }

    private var selectedIndex: Int? {
        guard let id = selectedGroupID else { return nil }
        return groups.firstIndex { $0.id == id }
    }

    // MARK: - Åpne og analysere

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Åpne"
        panel.message = "Velg mappen med bilder som skal sorteres"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        loadTask?.cancel()
        rootURL = url
        groups = []
        selectedGroupID = nil
        photos = []
        analyses = [:]
        featurePrints = [:]
        reviewed = []
        undoStack = []
        trashedCount = 0
        trashedBytes = 0
        phase = .scanning
        NSDocumentController.shared.noteNewRecentDocumentURL(url)

        loadTask = Task {
            let found = await Task.detached(priority: .userInitiated) { FolderScanner.scan(url) }.value
            guard !Task.isCancelled else { return }
            photos = found
            totalPhotos = found.count
            phase = .analyzing(done: 0, total: found.count)
            await analyzeAll(found)
            guard !Task.isCancelled else { return }
            AnalysisCache.shared.save()
            regroup()
            phase = .ready
        }
    }

    private func analyzeAll(_ list: [Photo]) async {
        let total = list.count
        let results = await AnalysisPipeline.run(list, cache: AnalysisCache.shared) { done in
            Task { @MainActor [weak self] in
                guard let self, case .analyzing(let current, _) = self.phase, done > current else { return }
                self.phase = .analyzing(done: done, total: total)
            }
        }
        guard !Task.isCancelled else { return }
        analyses = results
        for (url, a) in results {
            if let fp = PhotoAnalyzer.featurePrint(from: a.featurePrint) { featurePrints[url] = fp }
        }
    }

    /// Bygger gruppene på nytt (f.eks. når innstillinger endres). Ferdige grupper beholdes.
    func regroup() {
        guard !photos.isEmpty else { return }
        let d = UserDefaults.standard
        let gap = d.double(forKey: Settings.timeGapKey)
        let threshold = Float(d.double(forKey: Settings.thresholdKey))
        let preselect = d.bool(forKey: Settings.preselectKey)

        let candidates = photos.filter { !reviewed.contains($0.url) }
        let raw = SimilarityGrouper.group(photos: candidates, featurePrints: featurePrints, maxGap: gap, threshold: threshold)

        let fresh: [PhotoGroup] = raw.map { members in
            var g = PhotoGroup(photos: members)
            let scores = Ranking.score(members.map { analyses[$0.url] ?? PhotoAnalysis() })
            for (p, s) in zip(members, scores) { g.scores[p.url] = s }
            g.suggested = zip(members, scores).max { $0.1.total < $1.1.total }?.0.url
            if preselect, let s = g.suggested { g.selected = [s] } else { g.selected = Set(members.map(\.url)) }
            return g
        }
        let kept = groups.filter { $0.status != .pending }
        groups = (kept + fresh).sorted { $0.date < $1.date }
        if selectedGroup == nil || selectedGroup?.status != .pending {
            selectedGroupID = pendingGroups.first?.id ?? groups.first?.id
            focusedIndex = 0
        }
    }

    // MARK: - Navigasjon og valg

    func select(group id: UUID?) {
        selectedGroupID = id
        focusedIndex = 0
        if let g = selectedGroup, let s = g.suggested, let i = g.photos.firstIndex(where: { $0.url == s }) {
            focusedIndex = i
        }
    }

    func moveFocus(_ delta: Int) {
        guard let g = selectedGroup, !g.photos.isEmpty else { return }
        focusedIndex = min(max(0, focusedIndex + delta), g.photos.count - 1)
    }

    func moveGroup(_ delta: Int) {
        guard let i = selectedIndex else { select(group: groups.first?.id); return }
        let j = i + delta
        guard groups.indices.contains(j) else { return }
        select(group: groups[j].id)
    }

    func toggle(_ url: URL) {
        guard let i = selectedIndex else { return }
        if groups[i].selected.contains(url) { groups[i].selected.remove(url) } else { groups[i].selected.insert(url) }
    }

    func toggleFocused() {
        guard let g = selectedGroup, g.photos.indices.contains(focusedIndex) else { return }
        toggle(g.photos[focusedIndex].url)
    }

    func selectOnly(index: Int) {
        guard let i = selectedIndex, groups[i].photos.indices.contains(index) else { return }
        groups[i].selected = [groups[i].photos[index].url]
        focusedIndex = index
    }

    func zoom(_ action: ZoomAction) { zoomCommand = ZoomCommand(action: action) }

    func openViewer(at index: Int? = nil) {
        if let index { focusedIndex = index }
        showPreview = true
    }

    // MARK: - Samlinger

    /// Velg eller opprett en mappe som utvalgte bilder kopieres inn i.
    func chooseCollection() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Bruk denne mappen"
        panel.message = "Velg eller lag en mappe for samlingen, f.eks. «Julekalender2026». Merkede bilder kopieres hit."
        if panel.runModal() == .OK, let url = panel.url { setCollection(url) }
    }

    func setCollection(_ url: URL?) {
        collectionURL = url
        let d = UserDefaults.standard
        d.set(url?.path, forKey: Settings.collectionKey)
        if let url {
            recentCollections.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
            recentCollections.insert(url, at: 0)
            recentCollections = Array(recentCollections.prefix(8))
            d.set(recentCollections.map(\.path), forKey: Settings.recentCollectionsKey)
        }
        refreshCollection()
    }

    func refreshCollection() {
        collectionNames = collectionURL.map { CollectionService.existingNames(in: $0) } ?? []
    }

    func isInCollection(_ photo: Photo) -> Bool {
        guard let folder = collectionURL else { return false }
        return collectionNames.contains(CollectionService.fileName(for: photo, in: folder))
    }

    /// Antall filer i samlingsmappen.
    var collectionCount: Int { collectionNames.filter { !$0.hasPrefix(".") }.count }

    func toggleCollection(_ photo: Photo) {
        guard let folder = collectionURL else { chooseCollection(); if collectionURL != nil { toggleCollection(photo) }; return }
        let name = CollectionService.fileName(for: photo, in: folder)
        let adding = !collectionNames.contains(name)
        // Oppdater med en gang, kopier i bakgrunnen (filer i Dropbox kan måtte lastes ned først).
        if adding {
            collectionNames.insert(name)
            if let i = selectedIndex, groups[i].photos.contains(photo), groups[i].status == .pending {
                groups[i].selected.insert(photo.url)  // merkede bilder skal aldri slettes ved en feil
            }
        } else {
            collectionNames.remove(name)
        }
        Task.detached {
            do {
                if adding { try CollectionService.add(photo, to: folder) } else { try CollectionService.remove(photo, from: folder) }
            } catch {
                await MainActor.run {
                    self.refreshCollection()
                    self.errorMessage = "Kunne ikke \(adding ? "kopiere bildet til" : "fjerne bildet fra") «\(folder.lastPathComponent)»: \(error.localizedDescription)"
                }
            }
        }
    }

    func toggleCollectionFocused() {
        guard let g = selectedGroup, g.photos.indices.contains(focusedIndex) else { return }
        toggleCollection(g.photos[focusedIndex])
    }

    func revealCollection() {
        guard let url = collectionURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Bekreft / hopp over / angre

    /// Kalles fra Enter / knapp. Viser bekreftelse første gang.
    func requestConfirm() {
        guard let g = selectedGroup, g.status == .pending else { return }
        if g.selected.isEmpty {
            pendingDeleteAllGroupID = g.id
            return
        }
        if !UserDefaults.standard.bool(forKey: Settings.confirmedOnceKey) {
            pendingConfirmGroupID = g.id
            return
        }
        confirm(groupID: g.id)
    }

    func confirm(groupID: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == groupID }) else { return }
        UserDefaults.standard.set(true, forKey: Settings.confirmedOnceKey)
        let g = groups[i]
        let toTrash = g.photos.filter { !g.selected.contains($0.url) }
        let result = TrashService.trash(toTrash)
        let trashedURLs = Set(result.done.map(\.original))

        groups[i].photos.removeAll { trashedURLs.contains($0.url) }
        groups[i].status = .done
        photos.removeAll { trashedURLs.contains($0.url) }
        reviewed.formUnion(groups[i].photos.map(\.url))
        trashedCount += result.done.count
        trashedBytes += result.done.reduce(0) { $0 + $1.photo.fileSize }
        undoStack.append(UndoRecord(groupID: groupID, items: result.done, previousStatus: g.status))

        if !result.failed.isEmpty {
            errorMessage = "Kunne ikke flytte \(result.failed.count) bilde(r) til Papirkurven: \(result.failed[0].1.localizedDescription)"
        }
        advance(from: i)
    }

    func skip() {
        guard let i = selectedIndex, groups[i].status == .pending else { return }
        groups[i].status = .skipped
        reviewed.formUnion(groups[i].photos.map(\.url))
        undoStack.append(UndoRecord(groupID: groups[i].id, items: [], previousStatus: .pending))
        advance(from: i)
    }

    private func advance(from i: Int) {
        let next = groups[(i + 1)...].first { $0.status == .pending } ?? groups.first { $0.status == .pending }
        select(group: next?.id ?? groups[i].id)
    }

    func undo() {
        guard let record = undoStack.popLast(),
              let i = groups.firstIndex(where: { $0.id == record.groupID }) else { return }
        let restored = TrashService.restore(record.items)
        if restored.count < record.items.count {
            errorMessage = "Noen bilder kunne ikke legges tilbake. Sjekk Papirkurven."
        }
        let back = restored.map(\.photo)
        groups[i].photos = (groups[i].photos + back).sorted { $0.captureDate < $1.captureDate }
        groups[i].status = record.previousStatus
        photos.append(contentsOf: back)
        photos.sort { $0.captureDate < $1.captureDate }
        reviewed.subtract(groups[i].photos.map(\.url))
        trashedCount -= restored.count
        trashedBytes -= restored.reduce(0) { $0 + $1.photo.fileSize }
        select(group: groups[i].id)
    }

    /// Angre skal bare gjelde det som er gjort i appen, og bare mens den kjører.
    func reopenFinished(_ id: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == id }), groups[i].status == .skipped else { return }
        groups[i].status = .pending
        reviewed.subtract(groups[i].photos.map(\.url))
        select(group: id)
    }

    // MARK: - Claude

    func askClaude() {
        guard let g = selectedGroup, g.status == .pending, !claudeBusy.contains(g.id) else { return }
        let id = g.id
        // Store grupper: send de beste lokalt rangerte, men i samme rekkefølge som i appen.
        let top = Set(g.photos.sorted { (g.scores[$0.url]?.total ?? 0) > (g.scores[$1.url]?.total ?? 0) }
            .prefix(ClaudeAdvisor.maxImages).map(\.url))
        let urls = g.photos.map(\.url).filter { top.contains($0) }
        let model = UserDefaults.standard.string(forKey: Settings.claudeModelKey) ?? Settings.defaultModel
        claudeBusy.insert(id)
        Task {
            defer { claudeBusy.remove(id) }
            do {
                let verdict = try await ClaudeAdvisor.ask(about: urls, model: model)
                guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
                let pick = urls[verdict.best]
                groups[i].claudePick = pick
                groups[i].claudeComment = verdict.comment
                if groups[i].status == .pending { groups[i].selected = [pick] }
                if selectedGroupID == id, let fi = groups[i].photos.firstIndex(where: { $0.url == pick }) {
                    focusedIndex = fi
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Tastatur

    private var keyMonitor: Any?

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        // Ikke stjel taster fra tekstfelt (innstillinger) eller andre vinduer/dialoger.
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSText { return false }
        if NSApp.keyWindow?.identifier?.rawValue.contains("Settings") == true { return false }
        if NSApp.modalWindow != nil || pendingConfirmGroupID != nil || pendingDeleteAllGroupID != nil || errorMessage != nil { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if event.charactersIgnoringModifiers == "z", canUndo { undo(); return true }
            return false
        }
        if flags.contains(.option) || flags.contains(.control) { return false }

        switch event.keyCode {
        case 123: moveFocus(-1); return true          // ←
        case 124: moveFocus(1); return true           // →
        case 126: moveGroup(-1); return true          // ↑
        case 125: moveGroup(1); return true           // ↓
        case 36, 76:                                  // Enter (visningen holdes åpen og går til neste gruppe)
            requestConfirm(); return true
        case 49: toggleFocused(); return true         // mellomrom
        case 53:                                      // Esc
            if showPreview { showPreview = false; return true }
            return false
        default: break
        }
        guard let ch = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch ch {
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            selectOnly(index: Int(ch)! - 1); return true
        case "s": skip(); return true
        case "f": showPreview.toggle(); return true
        case "+", "=", "-", "0":
            guard showPreview else { return false }
            zoom(ch == "-" ? .zoomOut : ch == "0" ? .fit : .zoomIn); return true
        case "c": askClaude(); return true
        case "k": toggleCollectionFocused(); return true
        default: return false
        }
    }
}
