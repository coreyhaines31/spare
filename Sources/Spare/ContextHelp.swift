import SwiftUI

struct ContextHelp: View {
    let title: String
    let text: String
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }.buttonStyle(.borderless).help(text).accessibilityLabel("About \(title)")
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline)
                    Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(width: 320)
            }
    }
}
