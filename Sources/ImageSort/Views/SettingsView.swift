import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.timeGapKey) private var timeGap = Settings.defaultTimeGap
    @AppStorage(Settings.thresholdKey) private var threshold = Settings.defaultThreshold
    @AppStorage(Settings.claudeModelKey) private var claudeModel = Settings.defaultModel
    @AppStorage(Settings.preselectKey) private var preselect = true
    @State private var claudeStatus: Bool?

    var body: some View {
        Form {
            Section("Gruppering") {
                LabeledContent("Tidsvindu") {
                    VStack(alignment: .leading) {
                        Slider(value: $timeGap, in: 10...600, step: 10)
                        Text("Bilder tatt med mindre enn \(Int(timeGap)) sekunders mellomrom kan havne i samme gruppe.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Likhet") {
                    VStack(alignment: .leading) {
                        Slider(value: $threshold, in: 0.2...1.0, step: 0.05) {
                            EmptyView()
                        } minimumValueLabel: { Text("Streng").font(.caption) } maximumValueLabel: { Text("Romslig").font(.caption) }
                        Text("Høyere verdi gir større grupper med bilder som ligner mindre på hverandre. (\(threshold, specifier: "%.2f"))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Velg det foreslåtte bildet automatisk", isOn: $preselect)
            }

            Section("Claude") {
                Picker("Modell", selection: $claudeModel) {
                    Text("Sonnet (anbefalt)").tag("sonnet")
                    Text("Opus (best, tregere)").tag("opus")
                    Text("Haiku (raskest)").tag("haiku")
                }
                LabeledContent("Claude Code") {
                    switch claudeStatus {
                    case .none: ProgressView().controlSize(.small)
                    case .some(true): Label("Funnet", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .some(false): Label("Ikke installert", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
                Text("«Spør Claude» bruker Claude Code på Macen din, og dermed Claude-abonnementet ditt. Små kopier av bildene i gruppen sendes til Claude. Selve sorteringen skjer lokalt uten Claude.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .task { claudeStatus = await ClaudeAdvisor.isAvailable() }
    }
}
