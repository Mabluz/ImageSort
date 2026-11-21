import SwiftUI

/// Fullskjermvisning i full oppløsning: zoom, bla raskt og velg/fjern valg.
struct ViewerView: View {
    @Environment(LibraryViewModel.self) private var model
    @State private var preview: NSImage?
    @State private var full: NSImage?
    @State private var pixelSize: CGSize?
    @State private var zoom: CGFloat = 1

    var body: some View {
        if let group = model.selectedGroup, !group.photos.isEmpty {
            let index = min(max(0, model.focusedIndex), group.photos.count - 1)
            let photo = group.photos[index]
            VStack(spacing: 0) {
                topBar(group: group, photo: photo, index: index)
                ZStack {
                    ZoomableImageView(image: full ?? preview, pixelSize: pixelSize, command: model.zoomCommand) { zoom = $0 }
                    navButtons(count: group.photos.count, index: index)
                    if full == nil {
                        VStack {
                            Spacer()
                            Label("Laster full oppløsning …", systemImage: "arrow.down.circle")
                                .font(.caption).padding(8)
                                .background(.black.opacity(0.6), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(.bottom, 12)
                        }
                    }
                }
                filmstrip(group: group, index: index)
            }
            .background(Color.black)
            .task(id: photo.url) { await load(photo.url, group: group, index: index) }
        }
    }

    private func load(_ url: URL, group: PhotoGroup, index: Int) async {
        full = FullImageCache.shared.cached(url)
        if full == nil {
            preview = await ThumbnailCache.shared.image(for: url, maxPixel: 1600)
        }
        pixelSize = await Task.detached { ImageLoader.displayPixelSize(url: url) }.value
        if full == nil {
            let img = await FullImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            full = img
        }
        // Forhåndslast naboene.
        let neighbors = [index - 1, index + 1, index + 2].filter { group.photos.indices.contains($0) }.map { group.photos[$0].url }
        FullImageCache.shared.prefetch(neighbors)
    }

    // MARK: - Deler

    private func topBar(group: PhotoGroup, photo: Photo, index: Int) -> some View {
        let selected = group.selected.contains(photo.url)
        return HStack(spacing: 12) {
            Button { model.showPreview = false } label: { Label("Lukk", systemImage: "xmark") }
                .help("Lukk (Esc eller F)")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Bilde \(index + 1) av \(group.photos.count)").font(.headline)
                    if photo.url == group.suggested { badge("Forslag", "star.fill", .yellow, .black) }
                    if photo.url == group.claudePick { badge("Claude", "sparkles", .purple, .white) }
                }
                if let s = group.scores[photo.url] {
                    Text("Score \(Int(s.total.rounded()))" + (s.reasons.isEmpty ? "" : " · " + s.reasons.joined(separator: " · ")))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()

            HStack(spacing: 4) {
                Button { model.zoom(.zoomOut) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom ut (−)")
                Text("\(Int((zoom * 100).rounded())) %").monospacedDigit().frame(width: 52)
                Button { model.zoom(.zoomIn) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom inn (+)")
                Button("Tilpass") { model.zoom(.fit) }.help("Tilpass til vinduet (0)")
                Button("100 %") { model.zoom(.actualSize) }.help("Full størrelse (dobbeltklikk i bildet)")
            }

            let inCollection = model.isInCollection(photo)
            Button {
                model.toggleCollection(photo)
            } label: {
                Label(inCollection ? "I \(model.collectionName ?? "")" : (model.collectionName.map { "Legg i \($0)" } ?? "Legg i samling …"),
                      systemImage: inCollection ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderedProminent)
            .tint(inCollection ? .orange : .gray)
            .help("K – kopier bildet til samlingen (navn: samling_dato_filnavn)")

            if group.status == .pending {
                Button {
                    model.toggle(photo.url)
                } label: {
                    Label(selected ? "Beholdes" : "Beholdes ikke", systemImage: selected ? "checkmark.circle.fill" : "circle")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(selected ? .green : .gray)
                .help("Mellomrom")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.bar)
        .environment(\.colorScheme, .dark)
    }

    private func badge(_ text: String, _ icon: String, _ bg: Color, _ fg: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(bg, in: Capsule())
            .foregroundStyle(fg)
    }

    private func navButtons(count: Int, index: Int) -> some View {
        HStack {
            navButton("chevron.left", enabled: index > 0) { model.moveFocus(-1) }
            Spacer()
            navButton("chevron.right", enabled: index < count - 1) { model.moveFocus(1) }
        }
        .padding(.horizontal, 12)
    }

    private func navButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title.weight(.semibold))
                .frame(width: 44, height: 64)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0)
        .disabled(!enabled)
    }

    private func filmstrip(group: PhotoGroup, index: Int) -> some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(group.photos.enumerated()), id: \.element.id) { i, p in
                            let sel = group.selected.contains(p.url)
                            ThumbnailView(url: p.url, maxPixel: 240)
                                .frame(width: 96, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .opacity(group.status == .pending && !sel ? 0.4 : 1)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(i == index ? Color.white : (sel ? .green : .clear), lineWidth: i == index ? 3 : 2))
                                .overlay(alignment: .topTrailing) {
                                    if sel && group.status == .pending {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white, .green).padding(3)
                                    }
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if model.isInCollection(p) {
                                        Image(systemName: "pin.fill").font(.caption2)
                                            .foregroundStyle(.white).padding(3)
                                            .background(.orange, in: Circle()).padding(3)
                                    }
                                }
                                .overlay(alignment: .topLeading) {
                                    if p.url == group.suggested {
                                        Image(systemName: "star.fill").font(.caption2)
                                            .foregroundStyle(.yellow).padding(4)
                                    }
                                }
                                .id(p.id)
                                .onTapGesture { model.focusedIndex = i }
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .onChange(of: index) { _, i in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(group.photos[i].id, anchor: .center) }
                }
            }
            HStack {
                Text("←→ bla · mellomrom behold/ikke · K samling · +/− zoom · 0 tilpass · dobbeltklikk 100 % · ↩ bekreft og neste gruppe · Esc lukk")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if group.status == .pending {
                    let discard = group.photos.count - group.selected.count
                    Button {
                        model.requestConfirm()
                    } label: {
                        Label(discard > 0 ? "Behold \(group.selected.count), slett \(discard)" : "Behold alle", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                    .help("Enter")
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
        .background(.bar)
        .environment(\.colorScheme, .dark)
    }
}
