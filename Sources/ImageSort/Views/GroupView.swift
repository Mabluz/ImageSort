import SwiftUI

struct ThumbnailView: View {
    let url: URL?
    let maxPixel: Int
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await ThumbnailCache.shared.image(for: url, maxPixel: maxPixel)
        }
    }
}

struct GroupView: View {
    @Environment(LibraryViewModel.self) private var model
    let group: PhotoGroup

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 420), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(group.photos.enumerated()), id: \.element.id) { index, photo in
                            PhotoCell(
                                photo: photo,
                                index: index,
                                group: group,
                                isFocused: index == model.focusedIndex
                            )
                            .id(photo.id)
                            .onTapGesture(count: 2) { model.openViewer(at: index) }
                            .onTapGesture {
                                model.focusedIndex = index
                                if group.isReviewable { model.toggle(photo.url) }
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.focusedIndex) { _, i in
                    guard group.photos.indices.contains(i) else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(group.photos[i].id) }
                }
            }
            Divider()
            ActionBar(group: group)
        }
    }
}

struct PhotoCell: View {
    @Environment(LibraryViewModel.self) private var model
    let photo: Photo
    let index: Int
    let group: PhotoGroup
    let isFocused: Bool

    private var isSelected: Bool { group.selected.contains(photo.url) }
    private var inCollection: Bool { model.isInCollection(photo) }
    private var score: PhotoScore? { group.scores[photo.url] }
    private var dimmed: Bool { group.isReviewable && !isSelected }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(url: photo.url, maxPixel: 600)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) { badges }
                .overlay(alignment: .topTrailing) { selectionMark }
                .overlay(alignment: .bottomLeading) {
                    Button { model.toggleCollection(photo) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: inCollection ? "pin.fill" : "pin")
                            if inCollection, let name = model.collectionName {
                                Text(name).lineLimit(1)
                            }
                        }
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, inCollection ? 10 : 0)
                        .frame(minWidth: 30, minHeight: 30)
                        .background(inCollection ? Color.orange : Color.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help(inCollection ? "Fjern fra «\(model.collectionName ?? "")» (K)"
                          : model.collectionName.map { "Kopier til «\($0)» (K)" } ?? "Velg en samling og kopier bildet dit (K)")
                }
                .overlay(alignment: .bottomTrailing) {
                    Button { model.openViewer(at: index) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.body.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.55), in: Circle())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Vis i full størrelse med zoom (F eller dobbeltklikk)")
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(borderColor, lineWidth: isSelected || isFocused ? 4 : 0)
                }
                .opacity(dimmed ? 0.45 : 1)
                .saturation(dimmed ? 0.3 : 1)

            HStack(spacing: 6) {
                if let score {
                    Text("\(Int(score.total.rounded()))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(scoreColor(score.total).opacity(0.2), in: Capsule())
                        .foregroundStyle(scoreColor(score.total))
                    Text(score.reasons.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 4) {
            if index < 9 && group.isReviewable {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .frame(width: 22, height: 22)
                    .background(.black.opacity(0.55), in: Circle())
                    .foregroundStyle(.white)
            }
            if photo.url == group.suggested {
                Label("Forslag", systemImage: "star.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.yellow, in: Capsule())
                    .foregroundStyle(.black)
            }
            if photo.url == group.claudePick {
                Label("Claude", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.purple, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(8)
    }

    @ViewBuilder private var selectionMark: some View {
        HStack(spacing: 6) {
            if isFocused || group.kind != .series {
                Button {
                    model.focusedIndex = index
                    model.trashFocused()
                } label: {
                    Image(systemName: "trash")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("Flytt dette bildet til Papirkurven (⌫). ⌘Z angrer.")
            }
            if group.isReviewable {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.green : Color.black.opacity(0.35))
            }
        }
        .padding(8)
    }

    private var borderColor: Color {
        if isSelected && group.isReviewable { return .green }
        if isFocused { return .accentColor }
        return .clear
    }

    private func scoreColor(_ s: Double) -> Color {
        s >= 75 ? .green : s >= 50 ? .orange : .red
    }
}

struct ActionBar: View {
    @Environment(LibraryViewModel.self) private var model
    let group: PhotoGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let comment = group.claudeComment, !comment.isEmpty {
                Label(comment, systemImage: "sparkles")
                    .font(.callout)
                    .foregroundStyle(.purple)
            }
            HStack(spacing: 12) {
                if group.kind == .singles {
                    Button { model.openViewer() } label: {
                        Label("Full visning", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("F")
                    Label("⌫ eller 🗑 flytter bildet til Papirkurven (⌘Z angrer). K eller 📌 legger det i samlingen.",
                          systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if group.kind == .junk {
                    let discard = group.photos.count - group.selected.count
                    Button {
                        model.requestConfirm()
                    } label: {
                        Label(group.selected.isEmpty ? "Slett alle \(discard)" : "Slett \(discard), behold \(group.selected.count)",
                              systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(discard == 0)
                    .help("Enter")

                    Button { model.openViewer() } label: {
                        Label("Full visning", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("F")

                    Label("Bildene her ser uskarpe eller dårlige ut. Trykk mellomrom på de du vil beholde.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                } else if group.status == .pending {
                    let discard = group.photos.count - group.selected.count
                    Button {
                        model.requestConfirm()
                    } label: {
                        Label(discard > 0 ? "Behold \(group.selected.count), slett \(discard)" : "Behold alle",
                              systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .help("Enter")

                    Button("Hopp over") { model.skip() }.help("S")

                    Button { model.openViewer() } label: {
                        Label("Full visning", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("F")

                    Button {
                        model.askClaude()
                    } label: {
                        if model.claudeBusy.contains(group.id) {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Claude tenker …") }
                        } else {
                            Label("Spør Claude", systemImage: "sparkles")
                        }
                    }
                    .disabled(model.claudeBusy.contains(group.id))
                    .help("C")
                } else if group.status == .skipped {
                    Button("Gjennomgå likevel") { model.reopenFinished(group.id) }
                } else {
                    Label("Ferdig. Beholdt \(group.photos.count) bilde(r).", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
                Text("←→ flytt · ⌫ slett bilde · mellomrom velg · 1–9 velg kun · ↩ bekreft · S hopp over · F full visning · K samling · C Claude · ↑↓ gruppe")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
