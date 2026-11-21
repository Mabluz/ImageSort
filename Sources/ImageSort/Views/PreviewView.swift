import SwiftUI

/// Stor visning av fokusert bilde, valgfritt side ved side med forslaget.
struct PreviewView: View {
    @Environment(LibraryViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var compare = false
    @State private var actualSize = false

    var body: some View {
        let group = model.selectedGroup
        let photos = group?.photos ?? []
        let index = min(model.focusedIndex, max(0, photos.count - 1))

        VStack(spacing: 0) {
            HStack {
                if photos.indices.contains(index) {
                    Text("\(index + 1) av \(photos.count) · \(photos[index].fileName)")
                        .font(.headline)
                    if let s = group?.scores[photos[index].url] {
                        Text("Score \(Int(s.total.rounded()))").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("Sammenlign med forslag", isOn: $compare).toggleStyle(.checkbox)
                Toggle("100 %", isOn: $actualSize).toggleStyle(.checkbox)
                Button("Lukk") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)

            HStack(spacing: 2) {
                if photos.indices.contains(index) {
                    LargeImage(url: photos[index].url, actualSize: actualSize,
                               selected: group?.selected.contains(photos[index].url) ?? false)
                    if compare, let s = group?.suggested, s != photos[index].url {
                        LargeImage(url: s, actualSize: actualSize, selected: group?.selected.contains(s) ?? false)
                    }
                }
            }
        }
        .frame(minWidth: 1000, idealWidth: 1400, minHeight: 700, idealHeight: 900)
    }
}

private struct LargeImage: View {
    let url: URL
    let actualSize: Bool
    let selected: Bool
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                if actualSize {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: image.size.width / 2, height: image.size.height / 2)
                    }
                } else {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white, .green)
                    .padding(12)
            }
        }
        .task(id: url) {
            image = nil
            image = await ThumbnailCache.shared.image(for: url, maxPixel: 3000)
        }
    }
}
