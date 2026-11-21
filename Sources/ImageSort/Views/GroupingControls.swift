import SwiftUI

/// Sliderne som styrer hvor tett bilder grupperes. Brukes både i verktøylinjen og i Innstillinger.
struct GroupingSliders: View {
    @AppStorage(Settings.timeGapKey) private var timeGap = Settings.defaultTimeGap
    @AppStorage(Settings.thresholdKey) private var threshold = Settings.defaultThreshold

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hvor like må bildene være?").font(.headline)
                Slider(value: $threshold, in: 0.2...1.0, step: 0.05) {
                    EmptyView()
                } minimumValueLabel: { Text("Veldig like").font(.caption) } maximumValueLabel: { Text("Litt like").font(.caption) }
                Text("Mot venstre deles gruppene opp i mindre grupper med bilder som er nesten helt like. Mot høyre slås bilder som bare ligner litt, sammen til større grupper. (\(threshold, specifier: "%.2f"), standard \(Settings.defaultThreshold, specifier: "%.2f"))")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Tidsvindu").font(.headline)
                Slider(value: $timeGap, in: 10...600, step: 10) {
                    EmptyView()
                } minimumValueLabel: { Text("10 s").font(.caption) } maximumValueLabel: { Text("10 min").font(.caption) }
                Text("Bilder som er tatt med mer enn \(Self.duration(timeGap)) mellomrom, havner aldri i samme gruppe. (Standard \(Self.duration(Settings.defaultTimeGap)).)")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func duration(_ s: Double) -> String {
        let s = Int(s)
        if s < 60 { return "\(s) sek" }
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) sek"
    }
}

/// Knapp i verktøylinjen som åpner grupperingssliderne og viser resultatet med en gang.
struct GroupingMenu: View {
    @Environment(LibraryViewModel.self) private var model
    @AppStorage(Settings.timeGapKey) private var timeGap = Settings.defaultTimeGap
    @AppStorage(Settings.thresholdKey) private var threshold = Settings.defaultThreshold
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: { Label("Gruppering", systemImage: "slider.horizontal.3") }
            .help("Juster hvor tett bildene grupperes")
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    GroupingSliders()
                    Divider()
                    HStack {
                        Text(summary).font(.callout).monospacedDigit()
                        Spacer()
                        Button("Standard") {
                            threshold = Settings.defaultThreshold
                            timeGap = Settings.defaultTimeGap
                        }
                        .disabled(threshold == Settings.defaultThreshold && timeGap == Settings.defaultTimeGap)
                    }
                    Text("Grupper du allerede har gått gjennom, endres ikke.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(18)
                .frame(width: 380)
            }
    }

    private var summary: String {
        let pending = model.pendingGroups
        let photos = pending.reduce(0) { $0 + $1.photos.count }
        return "\(pending.count) grupper · \(photos) bilder i grupper · \(model.singleCount) enkeltbilder"
    }
}
