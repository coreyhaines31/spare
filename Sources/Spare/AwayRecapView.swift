import SwiftUI
import SpareCore
import PanelKit

struct AwayRecapView: View {
    let recap: AwayRecap
    @ObservedObject var monitor: Monitor
    @Environment(\.brushed) private var theme
    private var current: [String: Workload] {
        Dictionary(monitor.workloads.map { (RecapHistory.workloadID($0.id), $0) }, uniquingKeysWith: { first, _ in first })
    }
    /// The second half of the old "recorded · pressure" line; the recorded time is the disclosure's subtitle.
    private var pressure: String {
        recap.report.totals.knownPressureSeconds > 0 ? RecapFormat.duration(recap.report.totals.pressureSeconds) + " elevated memory pressure" : "Memory pressure unavailable"
    }
    var body: some View {
        Disclosure("While you were away", subtitle: "\(RecapFormat.duration(recap.report.totals.observed)) recorded", initiallyExpanded: true) {
            VStack(alignment: .leading, spacing: 0) {
                PanelNote(pressure).padding(.bottom, 4)
                if recap.report.unobserved >= 60 {
                    PanelNote("\(RecapFormat.duration(recap.report.unobserved)) unobserved").padding(.bottom, 4)
                }
                ForEach(recap.leaders) { item in
                    Row(item.name) { status(for: item) }
                }
                HStack {
                    Text("Returned \(recap.ended.formatted(.dateTime.hour().minute()))").font(PanelFont.body(11.5)).foregroundStyle(theme.sub)
                    Spacer()
                    Button("Open recap") { monitor.onOpenRecap?() }.buttonStyle(.panelQuietLink)
                }.padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 10)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                ContextHelp(title: "While you were away", text: "Starts after five minutes without keyboard or mouse input and ends when input resumes. The first five minutes are excluded. This describes observed resource use, not completed or productive work. Sleep and missing samples are unobserved. This summary stays in memory for up to 18 hours or until you dismiss it or quit Spare.")
                Button { monitor.dismissAwayRecap() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(theme.sub).accessibilityLabel("Dismiss away recap")
            }.padding(.top, 10).padding(.trailing, 14)
        }
        .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    @ViewBuilder private func status(for item: RecapWorkload) -> some View {
        if !monitor.ready || monitor.error != nil {
            Text("Checking status…").font(PanelFont.body(11)).foregroundStyle(theme.sub)
        } else if current[item.id] == nil {
            Text("No longer detected").font(PanelFont.body(11)).foregroundStyle(theme.sub)
        } else {
            StatusLight(.go, "Running now")
        }
    }
}
