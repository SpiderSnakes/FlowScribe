import SwiftUI

struct SidebarView: View {
    @Binding var section: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([AppSection.accueil, .fichiers, .vocabulaire]) { row($0) }
            Spacer()
            row(.reglages)
        }
        .padding(8)
        .animation(.snappy(duration: 0.22), value: section)
    }

    private func row(_ s: AppSection) -> some View {
        Button { section = s } label: {
            Label(s.title, systemImage: s.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(section == s ? Theme.accent.opacity(0.22) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(section == s ? Theme.accent : .primary)
    }
}
