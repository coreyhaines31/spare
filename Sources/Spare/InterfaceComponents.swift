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
    let select: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                WorkloadIcon(workload: workload)
                VStack(alignment: .leading, spacing: 3) {
                    Text(workload.name).font(.body.weight(.medium)).lineLimit(1)
                    Text(workload.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(sortCPU ? DisplayFormat.percent(workload.cpu) : DisplayFormat.memory(workload.memory))
                        .font(.body).monospacedDigit()
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: monitor.error != nil ? "questionmark.circle" : monitor.health.level == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(monitor.error != nil || !monitor.ready ? Color.secondary : [Color.green, .orange, .red][min(monitor.health.level, 2)])
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.error != nil ? "Readings unavailable" : monitor.health.title).font(.headline)
                    Text(monitor.error ?? monitor.health.message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let sample = monitor.samples.last {
                HStack(alignment: .top, spacing: 14) {
                    cpuReading(sample)
                    Divider().frame(height: 58)
                    pressureReading(sample)
                }
            }
        }.padding(16)
    }

    private func cpuReading(_ sample: SystemSample) -> some View {
        let busy = sample.cpu > 85
        return VStack(alignment: .leading, spacing: 4) {
            Text("CPU").font(.caption).foregroundStyle(.secondary)
            Text(monitor.ready ? "\(DisplayFormat.percent(sample.cpu)) in use" : "Measuring…").fontWeight(.semibold)
            UsageBar(fraction: monitor.ready ? sample.cpu / 100 : 0, color: busy ? .orange : .accentColor)
                .accessibilityHidden(true)
            Text(monitor.ready ? "\(DisplayFormat.percent(max(0, 100 - sample.cpu))) available" : " ")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
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
