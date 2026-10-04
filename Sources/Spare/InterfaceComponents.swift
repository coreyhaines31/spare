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
                    .foregroundStyle(monitor.error != nil || !monitor.ready ? Color.secondary : monitor.health.level == 0 ? Color.green : Color.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.error != nil ? "Readings unavailable" : monitor.health.title).font(.headline)
                    Text(monitor.error ?? monitor.health.message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let sample = monitor.samples.last {
                HStack {
                    metric("CPU", monitor.ready ? DisplayFormat.percent(sample.cpu) : "—", "of total processing power")
                    Divider().frame(height: 35)
                    metric("Memory", monitor.error != nil ? "Unavailable" : sample.pressure.rawValue.capitalized,
                           "\(DisplayFormat.memory(sample.memory)) of \(DisplayFormat.memory(sample.physical)) used")
                }
            }
        }.padding(16)
    }
    private func metric(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(title).foregroundStyle(.secondary); Text(value).fontWeight(.medium) }.font(.body)
            Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
