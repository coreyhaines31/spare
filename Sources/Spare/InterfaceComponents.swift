import SwiftUI
import SpareCore
import PanelKit

enum SpareLayout {
    static let width: CGFloat = 340
    static let height: CGFloat = 700
}

struct WorkloadRow: View {
    let workload: Workload
    let sortCPU: Bool
    var note: String?
    /// Shown when memory keeps climbing, with the trend as its tooltip.
    var growth: String?
    let select: () -> Void
    @State private var hovered = false
    @Environment(\.panelTheme) private var theme
    var body: some View {
        Button(action: select) {
            Row(workload.name, icon: WorkloadIcon(workload: workload, size: 22),
                subtitle: [workload.subtitle, workload.commandSummary(arguments: ProcessArguments.cached(for:)), note]
                    .compactMap { $0 }.joined(separator: " · "),
                value: sortCPU ? DisplayFormat.percent(workload.cpu) : DisplayFormat.memory(workload.memory),
                secondary: sortCPU ? DisplayFormat.memory(workload.memory) : "\(DisplayFormat.percent(workload.cpu)) CPU",
                options: hovered ? [.chevron, .selected] : [.chevron]) {
                if let growth {
                    Label("Growing", systemImage: "chart.line.uptrend.xyaxis").labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.caution)
                        .help("Memory growing · \(growth)").accessibilityLabel("Memory growing")
                }
            }
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .help("View \(workload.name)")
    }
}

/// The verdict under the fascia and the two readings that sort the list.
struct ResourceSummary: View {
    @ObservedObject var monitor: Monitor
    /// Clicking a reading sorts the list below by that resource.
    @Binding var sortCPU: Bool
    @Environment(\.panelTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Verdict(monitor.error != nil ? "Readings unavailable" : monitor.health.title,
                    message: monitor.error ?? monitor.health.message, status: status.0, statusLabel: status.1)
            if let sample = monitor.samples.last {
                HStack(alignment: .top, spacing: 8) {
                    Button { sortCPU = true } label: { cpuReading(sample) }
                        .buttonStyle(.plain).help("Sort the list by CPU")
                    Button { sortCPU = false } label: { pressureReading(sample) }
                        .buttonStyle(.plain).help("Sort the list by memory")
                }.fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
    }

    /// The light keeps the old headline colours: green only for a calm Mac, amber or red for a warning,
    /// and an unlit light while measuring, after an error, or when the CPU is busy but nothing is wrong yet.
    private var status: (PanelStatus, String) {
        if monitor.error != nil { return (.off, "Unavailable") }
        if !monitor.ready { return (.off, "Measuring") }
        if monitor.health.level > 1 { return (.stop, "Critical") }
        if monitor.health.level == 1 { return (.caution, "Strained") }
        if monitor.health.isCalm { return (.go, "Calm") }
        return (.off, (monitor.samples.last?.cpu ?? 0) > 85 ? "Busy" : "Watching")
    }

    private func cpuReading(_ sample: SystemSample) -> some View {
        let busy = sample.cpu > 85
        return ReadingTile(label: "CPU") {
            Text(monitor.ready ? "\(DisplayFormat.percent(sample.cpu)) in use" : "Measuring…").font(PanelFont.body(13, .semibold))
            Tape(monitor.ready ? sample.cpu / 100 : 0, status: busy ? .caution : nil).accessibilityHidden(true)
            Text(monitor.ready ? cpuCaption(sample) : " ")
                .font(PanelFont.body(11)).foregroundStyle(theme.sub).lineLimit(1).truncationMode(.middle)
        }.contentShape(Rectangle())
    }

    /// Names whatever is using the most CPU, so the answer to "what's busy?" is in the header.
    private func cpuCaption(_ sample: SystemSample) -> String {
        if let top = monitor.workloads.max(by: { $0.cpu < $1.cpu }), top.cpu >= 5 {
            return "Most: \(top.name) \(DisplayFormat.percent(top.cpu))"
        }
        return "\(100 - Int(min(max(sample.cpu, 0), 100).rounded()))% available"
    }

    private func pressureReading(_ sample: SystemSample) -> some View {
        let state = monitor.error != nil ? MemoryPressure.unknown : sample.pressure
        return ReadingTile(label: "Memory pressure") {
            PressureBadge(pressure: state).frame(height: 17)
            Text("\(DisplayFormat.memory(sample.memory)) of \(DisplayFormat.memory(sample.physical)) in use")
                .font(PanelFont.body(11)).foregroundStyle(theme.sub).lineLimit(1).minimumScaleFactor(0.8)
        }.contentShape(Rectangle())
    }
}

/// Memory pressure as a status light, so Warning and Critical stand out at a glance.
struct PressureBadge: View {
    let pressure: MemoryPressure
    var body: some View {
        StatusLight(status, label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Memory pressure \(label)")
    }
    private var label: String { pressure == .unknown ? "Unavailable" : pressure.rawValue.capitalized }
    private var status: PanelStatus {
        switch pressure {
        case .normal: return .go
        case .warning: return .caution
        case .critical: return .stop
        case .unknown: return .off
        }
    }
}

/// Whether an agent is mid-task, with how Spare knows as its tooltip.
struct ActivityBadge: View {
    let activity: AgentActivity
    var body: some View {
        StatusLight(activity == .working ? .caution : .off, activity.label)
            .help(activity == .working || activity == .waiting ? "Reported by Claude Code" : "Estimated from CPU use in the last 10 seconds")
    }
}
