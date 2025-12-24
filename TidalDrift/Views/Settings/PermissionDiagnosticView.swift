import SwiftUI

struct PermissionDiagnosticView: View {
    @ObservedObject var diagnosticService = PermissionDiagnosticService.shared
    @State private var showResetConfirmation = false
    @State private var resetMessage: String?
    @State private var hostnameConfig: PermissionDiagnosticService.HostnameConfig?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                
                statusCards
                
                hostnameSection
                
                if let result = diagnosticService.lastDiagnostic {
                    issuesSection(result)
                    recommendationsSection(result)
                }
                
                actionsSection
                
                explanationSection
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 550)
        .onAppear {
            Task {
                await diagnosticService.runFullDiagnostic()
                hostnameConfig = diagnosticService.checkHostnameConfiguration()
            }
        }
        .alert("Reset Complete", isPresented: .constant(resetMessage != nil)) {
            Button("OK") { resetMessage = nil }
        } message: {
            Text(resetMessage ?? "")
        }
        .alert("Reset All Permissions?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                Task {
                    let success = await diagnosticService.resetAllPermissions()
                    resetMessage = success 
                        ? "Permissions reset. Please quit and restart TidalDrift."
                        : "Reset failed. Try running from Terminal with admin privileges."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all TidalDrift permissions. You'll need to grant them again after restarting the app.")
        }
    }
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Permission Diagnostic")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Check and fix permission issues")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                Task {
                    await diagnosticService.runFullDiagnostic()
                }
            } label: {
                if diagnosticService.isRunningDiagnostic {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Label("Run Diagnostic", systemImage: "stethoscope")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(diagnosticService.isRunningDiagnostic)
        }
    }
    
    private var statusCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatusCard(
                title: "Screen Sharing",
                subtitle: "Remote desktop service",
                isEnabled: diagnosticService.screenSharingServiceRunning && diagnosticService.screenSharingPortOpen,
                icon: "rectangle.on.rectangle",
                action: {
                    diagnosticService.openScreenSharingSettings()
                }
            )
            
            StatusCard(
                title: "Screen Recording",
                subtitle: "App capture permission",
                isEnabled: diagnosticService.screenRecordingGranted,
                icon: "video.fill",
                action: {
                    diagnosticService.openScreenRecordingSettings()
                }
            )
        }
    }
    
    private var hostnameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Hostname & Bonjour")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    diagnosticService.openHostnameSettings()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if let config = hostnameConfig {
                VStack(alignment: .leading, spacing: 8) {
                    HostnameRow(
                        label: "Computer Name",
                        value: config.computerName,
                        help: "Friendly name shown in Finder"
                    )
                    
                    HostnameRow(
                        label: "Local Hostname",
                        value: "\(config.localHostname).local",
                        help: "Used for Bonjour on local network"
                    )
                    
                    if let globalHostname = config.hostname, !globalHostname.isEmpty {
                        HostnameRow(
                            label: "Dynamic Global Hostname",
                            value: globalHostname,
                            help: "For remote access via internet"
                        )
                    }
                    
                    HStack {
                        Text("Bonjour Domains")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        ForEach(config.bonjourDomains, id: \.self) { domain in
                            Text(domain)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        }
                    }
                    
                    if !config.wideAreaEnabled {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Wide-Area Bonjour is not configured. This is only needed for access outside your local network.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("Loading hostname configuration...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    @ViewBuilder
    private func issuesSection(_ result: PermissionDiagnosticService.DiagnosticResult) -> some View {
        if !result.issues.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Issues Found")
                    .font(.headline)
                
                ForEach(Array(result.issues.enumerated()), id: \.offset) { _, issue in
                    IssueRow(issue: issue)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
            )
        }
    }
    
    @ViewBuilder
    private func recommendationsSection(_ result: PermissionDiagnosticService.DiagnosticResult) -> some View {
        if !result.recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recommendations")
                    .font(.headline)
                
                ForEach(result.recommendations, id: \.self) { rec in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text(rec)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.1))
            )
        }
    }
    
    @State private var showScreenSharingFixAlert = false
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            HStack(spacing: 12) {
                Button {
                    showScreenSharingFixAlert = true
                    diagnosticService.openScreenSharingSettings()
                } label: {
                    Label("Fix Screen Sharing", systemImage: "wrench.fill")
                }
                .buttonStyle(.bordered)
                .alert("Fix Screen Sharing", isPresented: $showScreenSharingFixAlert) {
                    Button("Done") {
                        Task {
                            await diagnosticService.runFullDiagnostic()
                        }
                    }
                } message: {
                    Text("""
                    In System Settings:
                    
                    1. Turn OFF Screen Sharing
                    2. Wait 3 seconds
                    3. Turn ON Screen Sharing
                    
                    This fixes the "port not listening" issue.
                    Click Done when complete.
                    """)
                }
                
                Button {
                    Task {
                        let success = await diagnosticService.resetScreenRecordingPermission()
                        resetMessage = success
                            ? "Screen Recording permission reset. Please quit and restart TidalDrift, then grant permission when prompted."
                            : "Reset failed."
                    }
                } label: {
                    Label("Reset Screen Recording", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset All", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Why Permissions Get \"Sticky\"")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                ExplanationRow(
                    icon: "signature",
                    title: "Code Signature Changes",
                    description: "When you rebuild the app, macOS may see it as a new app requiring fresh permissions."
                )
                
                ExplanationRow(
                    icon: "memorychip",
                    title: "Permission Caching",
                    description: "macOS caches permissions in memory. Changes require quitting and restarting the app."
                )
                
                ExplanationRow(
                    icon: "doc.on.doc",
                    title: "Multiple Installations",
                    description: "Each TidalDrift copy has separate permissions. Remove duplicates in Settings → Maintenance."
                )
            }
            
            Divider()
            
            Text("**Quick Fix:** Quit TidalDrift completely → Reset permission → Restart → Grant when prompted")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct StatusCard: View {
    let title: String
    let subtitle: String
    let isEnabled: Bool
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isEnabled ? .green : .red)
                    .frame(width: 40)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isEnabled ? .green : .red)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

struct IssueRow: View {
    let issue: PermissionDiagnosticService.DiagnosticResult.Issue
    
    var severityColor: Color {
        switch issue.severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(severityColor)
                    .frame(width: 8, height: 8)
                
                Text(issue.category.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(severityColor)
            }
            
            Text(issue.description)
                .font(.subheadline)
            
            if let fix = issue.fix {
                Text("Fix: \(fix)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExplanationRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct HostnameRow: View {
    let label: String
    let value: String
    let help: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Text(help)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

struct PermissionDiagnosticView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionDiagnosticView()
    }
}

