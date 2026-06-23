import SwiftUI
import FlowScribeCore

struct HomeView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let onToggleRecord: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            if !permissions.allGranted {
                PermissionsView(model: permissions)
                Divider()
            }
            Spacer()
            Text("FlowScribe").font(.largeTitle.bold())
            Text("Appuie sur ⌥Espace — ou le bouton — pour dicter.")
                .foregroundStyle(.secondary)
            Button(action: onToggleRecord) {
                Image(systemName: "mic.fill").font(.system(size: 28))
                    .frame(width: 88, height: 88)
            }
            .buttonStyle(.glassProminent)
            .clipShape(Circle())
            Text("Moteur : \(settings.defaultProvider.displayName)")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
            Spacer()
            Text("Tes transcriptions récentes apparaîtront ici (bientôt).")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
