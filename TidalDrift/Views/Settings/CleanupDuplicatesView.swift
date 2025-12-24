import SwiftUI

struct CleanupDuplicatesView: View {
    @State private var installations: [InstallationInfo] = []
    @State private var selectedInstallations: Set<URL> = []
    @State private var isScanning = false
    @State private var showDeleteConfirmation = false
    @State private var deleteResult: String?
    
    var body: some View {
        VStack(spacing: 16) {
            headerSection
            
            if isScanning {
                ProgressView("Scanning for TidalDrift installations...")
                    .padding()
            } else if installations.isEmpty {
                emptyState
            } else {
                installationsList
            }
            
            actionButtons
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            scanForInstallations()
        }
        .alert("Delete Selected?", isPresented: $showDeleteConfirmation) {
            Button("Move to Trash", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will move \(selectedInstallations.count) TidalDrift installation(s) to the Trash.")
        }
        .alert("Cleanup Complete", isPresented: .constant(deleteResult != nil)) {
            Button("OK") {
                deleteResult = nil
                scanForInstallations()
            }
        } message: {
            Text(deleteResult ?? "")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("TidalDrift Installation Cleanup")
                .font(.headline)
            
            Text("Found installations of TidalDrift on your system. Select duplicates to remove them.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            
            Text("No Duplicate Installations Found")
                .font(.headline)
            
            Text("Your system only has one TidalDrift installation.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private var installationsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Found Installations")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(installations.count) found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Current app (not selectable)
                    if let currentApp = installations.first(where: { $0.url.path == Bundle.main.bundlePath }) {
                        InstallationRow(
                            info: currentApp,
                            isSelected: false,
                            isCurrent: true,
                            onToggle: {}
                        )
                    }
                    
                    // Other installations (selectable)
                    ForEach(installations.filter { $0.url.path != Bundle.main.bundlePath }, id: \.url) { info in
                        InstallationRow(
                            info: info,
                            isSelected: selectedInstallations.contains(info.url),
                            isCurrent: false,
                            onToggle: {
                                if selectedInstallations.contains(info.url) {
                                    selectedInstallations.remove(info.url)
                                } else {
                                    selectedInstallations.insert(info.url)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                scanForInstallations()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            if !installations.isEmpty {
                Button {
                    // Select all except current
                    selectedInstallations = Set(
                        installations
                            .filter { $0.url.path != Bundle.main.bundlePath }
                            .map { $0.url }
                    )
                } label: {
                    Text("Select All Duplicates")
                }
                .buttonStyle(.bordered)
            }
            
            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Selected", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedInstallations.isEmpty)
        }
    }
    
    private func scanForInstallations() {
        isScanning = true
        selectedInstallations.removeAll()
        
        DispatchQueue.global(qos: .userInitiated).async {
            let urls = InstallationCleanupService.shared.findAllInstallations()
            let infos = urls.map { InstallationCleanupService.shared.getInstallationInfo($0) }
            
            // Also add current app
            var allInfos = infos
            let currentInfo = InstallationCleanupService.shared.getInstallationInfo(
                URL(fileURLWithPath: Bundle.main.bundlePath)
            )
            allInfos.insert(currentInfo, at: 0)
            
            DispatchQueue.main.async {
                installations = allInfos
                isScanning = false
            }
        }
    }
    
    private func deleteSelected() {
        let toDelete = Array(selectedInstallations)
        let deleted = InstallationCleanupService.shared.deleteInstallations(toDelete)
        deleteResult = "Moved \(deleted) installation(s) to Trash."
        selectedInstallations.removeAll()
    }
}

struct InstallationRow: View {
    let info: InstallationInfo
    let isSelected: Bool
    let isCurrent: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox (only for non-current)
            if !isCurrent {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .onTapGesture {
                        onToggle()
                    }
            } else {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }
            
            // App icon
            Image(systemName: "app.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(info.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if isCurrent {
                        Text("(Current)")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text(info.location)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("v\(info.version)")
                        .font(.caption2)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(info.formattedSize)
                        .font(.caption2)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(info.formattedDate)
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Show in Finder button
            Button {
                NSWorkspace.shared.selectFile(info.url.path, inFileViewerRootedAtPath: info.location)
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isCurrent {
                onToggle()
            }
        }
    }
}

struct CleanupDuplicatesView_Previews: PreviewProvider {
    static var previews: some View {
        CleanupDuplicatesView()
    }
}


