import SwiftUI

struct ContentView: View {
    @Environment(LibraryViewModel.self) private var model
    @AppStorage(Settings.timeGapKey) private var timeGap = Settings.defaultTimeGap
    @AppStorage(Settings.thresholdKey) private var threshold = Settings.defaultThreshold

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
        .onAppear { model.installKeyMonitor() }
        .onChange(of: timeGap) { model.regroup() }
        .onChange(of: threshold) { model.regroup() }
        .sheet(isPresented: $model.showPreview) {
            PreviewView()
                .environment(model)
        }
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
            Text("Bildene du ikke har valgt, flyttes til Papirkurven, så du kan hente dem tilbake. Du får bare dette spørsmålet én gang. Trykk ⌘Z for å angre.")
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
            Button { model.undo() } label: { Label("Angre", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .help("Angre siste gruppe (⌘Z)")
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
                Text(group.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.callout)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch group.status {
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .skipped: Image(systemName: "forward.fill").foregroundStyle(.secondary)
            case .pending: EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    private var caption: String {
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
                                       description: Text("Prøv å øke tidsvinduet eller likhetsterskelen i Innstillinger (⌘,)."))
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
