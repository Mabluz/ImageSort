import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.claudeModelKey) private var claudeModel = Settings.defaultModel
    @AppStorage(Settings.preselectKey) private var preselect = true
    @AppStorage(Settings.blurKey) private var blur = Ranking.defaultBlurThreshold
    @State private var claudeStatus: Bool?

    var body: some View {
        Form {
            Section("Gruppering") {
                GroupingSliders()
                Toggle("Velg det foreslåtte bildet automatisk", isOn: $preselect)
            }

            Section("Enkeltbilder") {
                LabeledContent("Uskarphet") {
                    VStack(alignment: .leading) {
                        Slider(value: $blur, in: 40...300, step: 10) {
                            EmptyView()
                        } minimumValueLabel: { Text("Mild").font(.caption) } maximumValueLabel: { Text("Streng").font(.caption) }
                        Text("Enkeltbilder med skarphet under \(Int(blur)) havner i «Sannsynligvis dårlige». Strengere gir flere forslag.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
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
