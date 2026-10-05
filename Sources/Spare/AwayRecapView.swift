import SwiftUI
import SpareCore

struct AwayRecapView: View {
    let recap: AwayRecap
    @ObservedObject var monitor: Monitor
    private var current: [String: Workload] {
        Dictionary(monitor.workloads.map { (RecapHistory.workloadID($0.id), $0) }, uniquingKeysWith: { first, _ in first })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("While you were away", systemImage: "clock.badge.checkmark").font(.subheadline.weight(.semibold))
                ContextHelp(title: "While you were away", text: "Starts after five minutes without keyboard or mouse input and ends when input resumes. The first five minutes are excluded. This describes observed resource use, not completed or productive work. Sleep and missing samples are unobserved. This summary stays in memory for up to 18 hours or until you dismiss it or quit Spare.")
                Spacer()
                Button { monitor.dismissAwayRecap() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel("Dismiss away recap")
            }
            Text("\(RecapFormat.duration(recap.report.totals.observed)) recorded · \(recap.report.totals.knownPressureSeconds > 0 ? RecapFormat.duration(recap.report.totals.pressureSeconds) + " elevated memory pressure" : "Memory pressure unavailable")")
                .font(.caption).foregroundStyle(.secondary)
            if recap.report.unobserved >= 60 {
                Text("\(RecapFormat.duration(recap.report.unobserved)) unobserved").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(recap.leaders) { item in
                HStack {
                    Text(item.name).lineLimit(1)
                    Spacer()
                    Text(current[item.id] == nil ? "No longer detected" : "Running now")
                        .foregroundStyle(.secondary)
                }.font(.caption)
            }
            HStack {
                Text("Returned \(recap.ended.formatted(.dateTime.hour().minute()))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open recap") { monitor.onOpenRecap?() }.buttonStyle(.link).font(.caption)
            }
        }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
