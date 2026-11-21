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
                            .onTapGesture(count: 2) {
                                model.focusedIndex = index
                                model.showPreview = true
                            }
                            .onTapGesture {
                                model.focusedIndex = index
                                if group.status == .pending { model.toggle(photo.url) }
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
    let photo: Photo
    let index: Int
    let group: PhotoGroup
    let isFocused: Bool

    private var isSelected: Bool { group.selected.contains(photo.url) }
    private var score: PhotoScore? { group.scores[photo.url] }
    private var dimmed: Bool { group.status == .pending && !isSelected }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(url: photo.url, maxPixel: 600)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .topLeading) { badges }
                .overlay(alignment: .topTrailing) { selectionMark }
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
            if index < 9 {
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
        if group.status == .pending {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, isSelected ? Color.green : Color.black.opacity(0.35))
                .padding(8)
        }
    }

    private var borderColor: Color {
        if isSelected && group.status == .pending { return .green }
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
                if group.status == .pending {
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
                Text("←→ flytt · mellomrom velg · 1–9 velg kun · ↩ bekreft · S hopp over · F forstørr · C Claude · ↑↓ gruppe")
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
