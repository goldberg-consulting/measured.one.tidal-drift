import SwiftUI
import OSLog

struct StatusCardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var localCast = LocalCastService.shared
    @ObservedObject private var clipboard = ClipboardSyncService.shared
    private let logger = Logger(subsystem: "com.tidaldrift", category: "StatusCard")

    @State private var isTogglingScreen = false
    @State private var isTogglingFile = false
    @State private var isTogglingSSH = false
    @State private var isTogglingLocalCast = false
    @State private var showPermissionAlert = false
    @State private var permissionAlertMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            toggleSection
            Divider()
            infoSection
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("Open Screen Recording Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(permissionAlertMessage)
        }
        .onAppear {
            appState.refreshLocalInfo()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.computerName)
                    .font(.headline)
                Text("This Mac")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var toggleSection: some View {
        VStack(spacing: 8) {
            SharingToggleRow(label: "Screen Sharing", isEnabled: appState.screenSharingEnabled, isToggling: isTogglingScreen) {
                toggleScreenSharing()
            }

            SharingToggleRow(label: "File Sharing", isEnabled: appState.fileSharingEnabled, isToggling: isTogglingFile) {
                toggleFileSharing()
            }

            SharingToggleRow(label: "Remote Login (SSH)", isEnabled: appState.remoteLoginEnabled, isToggling: isTogglingSSH) {
                toggleRemoteLogin()
            }

            HStack {
                Text("Peer Discovery")
                    .font(.caption)
                Spacer()
                Toggle("", isOn: $appState.settings.peerDiscoveryEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .frame(width: 40)
            }

            Divider()
                .padding(.vertical, 2)

            HStack {
                Text("Clipboard Sync")
                    .font(.caption)
                Spacer()
                Toggle("", isOn: $clipboard.isEnabled)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .frame(width: 40)
            }

            HStack {
                Text("Screen Streaming")
                    .font(.caption)
                Spacer()

                if isTogglingLocalCast {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 40)
                } else {
                    Toggle("", isOn: Binding(
                        get: { localCast.isHosting },
                        set: { newValue in
                            isTogglingLocalCast = true
                            Task {
                                defer { Task { @MainActor in isTogglingLocalCast = false } }
                                if newValue {
                                    do {
                                        try await localCast.startHosting()
                                    } catch {
                                        await MainActor.run {
                                            permissionAlertMessage = error.localizedDescription
                                            showPermissionAlert = true
                                        }
                                    }
                                } else {
                                    localCast.stopHosting()
                                }
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                    .frame(width: 40)
                }
            }
            
            // Show auth status when hosting
            if localCast.isHosting {
                HStack(spacing: 4) {
                    Image(systemName: localCast.isAuthEnabled ? "lock.fill" : "lock.open")
                        .font(.caption2)
                        .foregroundColor(localCast.isAuthEnabled ? .green : .secondary)
                    Text(localCast.isAuthEnabled ? "Encrypted" : "No auth")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(spacing: 6) {
            HStack {
                Text(appState.localIPAddress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(appState.localIPAddress, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            let peerCount = appState.discoveredDevices.filter { $0.isTidalDriftPeer }.count
            HStack {
                if peerCount > 0 {
                    Text("\(peerCount) peer\(peerCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("v\(Bundle.main.appVersion)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func toggleScreenSharing() {
        isTogglingScreen = true
        Task {
            let success = await SharingConfigurationService.shared.toggleScreenSharing(enable: !appState.screenSharingEnabled)
            await MainActor.run {
                isTogglingScreen = false
                if success { appState.screenSharingEnabled.toggle() }
            }
            await appState.checkSharingStatus()
        }
    }

    private func toggleFileSharing() {
        isTogglingFile = true
        Task {
            let success = await SharingConfigurationService.shared.toggleFileSharing(enable: !appState.fileSharingEnabled)
            await MainActor.run {
                isTogglingFile = false
                if success { appState.fileSharingEnabled.toggle() }
            }
            await appState.checkSharingStatus()
        }
    }

    private func toggleRemoteLogin() {
        isTogglingSSH = true
        Task {
            let success = await SharingConfigurationService.shared.toggleRemoteLogin(enable: !appState.remoteLoginEnabled)
            await MainActor.run {
                isTogglingSSH = false
                if success { appState.remoteLoginEnabled.toggle() }
            }
            await appState.checkSharingStatus()
        }
    }
}

struct SharingToggleRow: View {
    let label: String
    let isEnabled: Bool
    let isToggling: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            if isToggling {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 40)
            } else {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.7)
                .frame(width: 40)
            }
        }
    }
}
