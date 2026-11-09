import SwiftUI
import SpareCore

enum SpareLayout {
    static let width: CGFloat = 440
    static let height: CGFloat = 640
}

struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search apps, projects, or ports"
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.setAccessibilityLabel("Search apps, projects, or ports")
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

struct WorkloadRow: View {
    let workload: Workload
    let sortCPU: Bool
    var note: String?
    /// Shown when memory keeps climbing, with the trend as its tooltip.
    var growth: String?
    let select: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                WorkloadIcon(workload: workload)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workload.name).font(.body.weight(.medium)).lineLimit(1)
                    Text([workload.subtitle, workload.commandSummary(arguments: ProcessArguments.cached(for:)), note]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        if let growth {
                            Image(systemName: "chart.line.uptrend.xyaxis").font(.caption).foregroundStyle(.orange)
                                .help("Memory growing · \(growth)").accessibilityLabel("Memory growing")
                        }
                        Text(sortCPU ? DisplayFormat.percent(workload.cpu) : DisplayFormat.memory(workload.memory))
                            .font(.body).monospacedDigit()
                    }
                    Text(sortCPU ? DisplayFormat.memory(workload.memory) : "\(DisplayFormat.percent(workload.cpu)) CPU")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(.horizontal, 8).padding(.vertical, 8).contentShape(Rectangle())
                .background(hovered ? Color(nsColor: .quaternaryLabelColor).opacity(0.4) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .help("View \(workload.name)")
    }
}

struct ResourceSummary: View {
    @ObservedObject var monitor: Monitor
    /// Clicking a reading sorts the list below by that resource.
    @Binding var sortCPU: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: headlineSymbol).foregroundStyle(headlineColor).font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.error != nil ? "Readings unavailable" : monitor.health.title).font(.headline)
                    Text(monitor.error ?? monitor.health.message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let sample = monitor.samples.last {
                HStack(alignment: .top, spacing: 14) {
                    Button { sortCPU = true } label: { cpuReading(sample).contentShape(Rectangle()) }
                        .buttonStyle(.plain).help("Sort the list by CPU")
                    Divider().frame(height: 58)
                    Button { sortCPU = false } label: { pressureReading(sample).contentShape(Rectangle()) }
                        .buttonStyle(.plain).help("Sort the list by memory")
                }
            }
        }.padding(16)
    }

    /// The green check is only for a calm Mac. A maxed CPU that isn't a warning yet gets a neutral gauge.
    private var headlineSymbol: String {
        if monitor.error != nil { return "questionmark.circle" }
        if monitor.health.level > 0 { return "exclamationmark.circle.fill" }
        return monitor.health.isCalm ? "checkmark.circle.fill" : "gauge.with.needle.fill"
    }
    private var headlineColor: Color {
        if monitor.error != nil || !monitor.ready { return .secondary }
        if monitor.health.level > 0 { return monitor.health.level == 1 ? .orange : .red }
        return monitor.health.isCalm ? .green : .orange
    }

    private func cpuReading(_ sample: SystemSample) -> some View {
        let busy = sample.cpu > 85
        return VStack(alignment: .leading, spacing: 4) {
            Text("CPU").font(.caption).foregroundStyle(.secondary)
            Text(monitor.ready ? "\(DisplayFormat.percent(sample.cpu)) in use" : "Measuring…").fontWeight(.semibold)
            UsageBar(fraction: monitor.ready ? sample.cpu / 100 : 0, color: busy ? .orange : .accentColor)
                .accessibilityHidden(true)
            Text(monitor.ready ? cpuCaption(sample) : " ")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
        return VStack(alignment: .leading, spacing: 4) {
            Text("Memory pressure").font(.caption).foregroundStyle(.secondary)
            PressureBadge(pressure: state)
            Text("\(DisplayFormat.memory(sample.memory)) of \(DisplayFormat.memory(sample.physical)) in use")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A thin capacity bar: the filled part is what's in use.
struct UsageBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color).frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }.frame(height: 5)
    }
}

/// Memory pressure as a colored status, so Warning and Critical stand out at a glance.
struct PressureBadge: View {
    let pressure: MemoryPressure
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).imageScale(.small)
            Text(label)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory pressure \(label)")
    }
    private var label: String { pressure == .unknown ? "Unavailable" : pressure.rawValue.capitalized }
    private var color: Color {
        switch pressure {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
    private var symbol: String {
        switch pressure {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Whether an agent is mid-task, with how Spare knows as its tooltip.
struct ActivityBadge: View {
    let activity: AgentActivity
    var body: some View {
        Label(activity.label, systemImage: activity.isBusy ? "circle.fill" : "circle")
            .font(.caption.weight(.medium)).labelStyle(.titleAndIcon).imageScale(.small)
            .foregroundStyle(activity == .working ? Color.orange : .secondary)
            .help(activity == .working || activity == .waiting ? "Reported by Claude Code" : "Estimated from CPU use in the last 10 seconds")
    }
}
