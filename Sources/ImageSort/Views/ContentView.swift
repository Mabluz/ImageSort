import SwiftUI

struct ContentView: View {
    @Environment(LibraryViewModel.self) private var model
    @AppStorage(Settings.timeGapKey) private var timeGap = Settings.defaultTimeGap
    @AppStorage(Settings.thresholdKey) private var threshold = Settings.defaultThreshold
    @AppStorage(Settings.blurKey) private var blur = Ranking.defaultBlurThreshold

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            DetailView()
        }
        .toolbar { toolbar }
        .navigationTitle(model.rootURL?.lastPathComponent ?? "ImageSort")
        .navigationSubtitle(subtitle)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
            model.open(url)
            return true
        }
        .onAppear {
            model.installKeyMonitor()
            // `ImageSort --open /sti/til/mappe` åpner en mappe direkte (nyttig for testing).
            let args = CommandLine.arguments
            if model.rootURL == nil, let i = args.firstIndex(of: "--open"), i + 1 < args.count {
                model.open(URL(fileURLWithPath: args[i + 1]))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshCollection()
        }
        .onChange(of: [timeGap, threshold, blur]) { model.regroup() }
        .overlay {
            if model.showPreview {
                ViewerView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.showPreview)
        .modifier(AlertsModifier())
    }

    private var subtitle: String {
        switch model.phase {
        case .idle: return ""
        case .scanning: return "Leter etter bilder …"
        case .analyzing(let done, let total): return "Analyserer \(done) av \(total) bilder …"
        case .ready: return "\(model.totalPhotos) bilder · \(model.pendingGroups.count) grupper igjen"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if case .analyzing(let done, let total) = model.phase, total > 0 {
                ProgressView(value: Double(done), total: Double(total))
                    .frame(width: 140)
            } else if model.phase == .scanning {
                ProgressView().controlSize(.small)
            }
            if model.trashedCount > 0 {
                Text("\(model.trashedCount) slettet · \(ByteCountFormatter.string(fromByteCount: model.trashedBytes, countStyle: .file)) frigjort")
                    .foregroundStyle(.secondary)
            }
            GroupingMenu()
                .disabled(model.phase != .ready)
            CollectionMenu()
            Button { model.undo() } label: { Label("Angre", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .help("Angre siste sletting (⌘Z)")
            Button { model.chooseFolder() } label: { Label("Åpne mappe", systemImage: "folder") }
                .help("Åpne mappe (⌘O)")
        }
    }
}

struct SidebarView: View {
    @Environment(LibraryViewModel.self) private var model

    var body: some View {
        List(selection: Binding(get: { model.selectedGroupID }, set: { model.select(group: $0) })) {
            if !model.pendingGroups.isEmpty {
                Section("Å gjennomgå (\(model.pendingGroups.count))") {
                    ForEach(model.pendingGroups) { GroupRow(group: $0).tag($0.id) }
                }
            }
            if !model.singleGroups.isEmpty || !model.junkGroups.isEmpty {
                Section("Enkeltbilder (\(model.singleCount + model.junkGroups.reduce(0) { $0 + $1.photos.count }))") {
                    ForEach(model.junkGroups) { GroupRow(group: $0).tag($0.id) }
                    ForEach(model.singleGroups) { GroupRow(group: $0).tag($0.id) }
                }
            }
            if !model.finishedGroups.isEmpty {
                Section("Ferdig (\(model.finishedGroups.count))") {
                    ForEach(model.finishedGroups) { GroupRow(group: $0).tag($0.id) }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct GroupRow: View {
    let group: PhotoGroup

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(url: group.suggested ?? group.photos.first?.url, maxPixel: 120)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                if group.kind != .series, let title = group.title {
                    Text(title.prefix(1).uppercased() + title.dropFirst()).font(.callout)
                } else {
                    Text(group.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(.callout)
                }
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if group.kind == .junk {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            switch group.status {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .skipped: Image(systemName: "forward.fill").foregroundStyle(.secondary)
            case .pending: EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    private var caption: String {
        if group.kind == .singles { return "\(group.photos.count) enkeltbilder" }
        if group.kind == .junk { return "\(group.photos.count) bilder å se over" }
        switch group.status {
        case .pending: return "\(group.photos.count) bilder"
        case .done: return "beholdt \(group.photos.count)"
        case .skipped: return "hoppet over · \(group.photos.count) bilder"
        }
    }
}

struct DetailView: View {
    @Environment(LibraryViewModel.self) private var model

    var body: some View {
        switch model.phase {
        case .idle:
            EmptyStateView()
        case .scanning, .analyzing:
            VStack(spacing: 16) {
                ProgressView()
                Text(progressText).foregroundStyle(.secondary)
                Text("Første gang tar det litt tid. Neste gang går det mye raskere.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if model.groups.isEmpty {
                ContentUnavailableView("Fant ingen like bilder", systemImage: "photo.on.rectangle",
                                       description: Text("Trykk «Gruppering» i verktøylinjen og dra likhet eller tidsvindu mot høyre."))
            } else if let group = model.selectedGroup {
                GroupView(group: group)
            } else {
                ContentUnavailableView("Velg en gruppe", systemImage: "square.grid.2x2")
            }
        }
    }

    private var progressText: String {
        if case .analyzing(let d, let t) = model.phase { return "Analyserer bildene lokalt … \(d) av \(t)" }
        return "Leter etter bilder …"
    }
}

struct EmptyStateView: View {
    @Environment(LibraryViewModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.stack")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            Text("Rydd i bildene dine").font(.title2.weight(.semibold))
            Text("Dra en mappe hit eller åpne en mappe.\nLike bilder samles i grupper, og det beste i hver gruppe er valgt på forhånd.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Åpne mappe …") { model.chooseFolder() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Velger hvilken samling (mappe) merkede bilder kopieres til.
struct CollectionMenu: View {
    @Environment(LibraryViewModel.self) private var model

    var body: some View {
        Menu {
            if !model.recentCollections.isEmpty {
                Section("Samlinger") {
                    ForEach(model.recentCollections, id: \.self) { url in
                        Button {
                            model.setCollection(url)
                        } label: {
                            if url == model.collectionURL {
                                Label(url.lastPathComponent, systemImage: "checkmark")
                            } else {
                                Text(url.lastPathComponent)
                            }
                        }
                    }
                }
            }
            Button("Velg eller lag ny samling …") { model.chooseCollection() }
            if model.collectionURL != nil {
                Button("Vis «\(model.collectionName ?? "")» i Finder") { model.revealCollection() }
                Button("Ingen samling") { model.setCollection(nil) }
            }
        } label: {
            if let name = model.collectionName {
                Label("\(name) (\(model.collectionCount))", systemImage: "pin.fill")
            } else {
                Label("Samling", systemImage: "pin")
            }
        }
        .help("Merk bilder med K for å kopiere dem til samlingen (f.eks. til kalender eller fotobok)")
    }
}

/// Bekreftelser og feilmeldinger (egen modifier så ContentView holder seg enkel for kompilatoren).
struct AlertsModifier: ViewModifier {
    @Environment(LibraryViewModel.self) private var model

    func body(content: Content) -> some View {
        content
            .alert("Flytte uvalgte bilder til Papirkurven?", isPresented: Binding(
                get: { model.pendingConfirmGroupID != nil },
                set: { if !$0 { model.pendingConfirmGroupID = nil } }
            )) {
                Button("Flytt til Papirkurven") {
                    if let id = model.pendingConfirmGroupID { model.confirm(groupID: id) }
                    model.pendingConfirmGroupID = nil
                }
                .keyboardShortcut(.defaultAction)
                Button("Avbryt", role: .cancel) { model.pendingConfirmGroupID = nil }
            } message: {
                Text(model.confirmMessage)
            }
            .alert("Ingen bilder er valgt", isPresented: Binding(
                get: { model.pendingDeleteAllGroupID != nil },
                set: { if !$0 { model.pendingDeleteAllGroupID = nil } }
            )) {
                Button("Flytt alle til Papirkurven", role: .destructive) {
                    if let id = model.pendingDeleteAllGroupID { model.confirm(groupID: id) }
                    model.pendingDeleteAllGroupID = nil
                }
                Button("Avbryt", role: .cancel) { model.pendingDeleteAllGroupID = nil }
            } message: {
                Text("Vil du virkelig flytte hele gruppen til Papirkurven?")
            }
            .alert("Noe gikk galt", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
    }
}
