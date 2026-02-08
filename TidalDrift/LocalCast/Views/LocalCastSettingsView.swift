import SwiftUI

struct LocalCastSettingsView: View {
    @AppStorage("localCastQuality") var quality: LocalCastConfiguration.QualityPreset = .high
    @AppStorage("localCastCodec") var codec: LocalCastConfiguration.Codec = .h264
    @AppStorage("localCastAdaptive") var adaptiveQuality = true
    @AppStorage("showLatencyOverlay") var showOverlay = false
    @AppStorage("localCastAutoHost") var autoHost = false
    
    @StateObject private var permissions = LocalCastPermissions()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("LocalCast Screen Sharing")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Quality & Performance")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Quality Preset", selection: $quality) {
                    ForEach(LocalCastConfiguration.QualityPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue.capitalized).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                
                Picker("Video Codec", selection: $codec) {
                    Text("H.264 (Faster)").tag(LocalCastConfiguration.Codec.h264)
                    Text("HEVC (Smaller)").tag(LocalCastConfiguration.Codec.hevc)
                }
                
                Toggle("Adaptive quality", isOn: $adaptiveQuality)
                    .help("Automatically adjust quality based on network conditions")
                
                Toggle("Show latency overlay", isOn: $showOverlay)
                
                Toggle("Auto-host on launch", isOn: $autoHost)
                    .help("Automatically start hosting when TidalDrift launches")
            }
            .padding(.leading, 8)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Permissions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "video.fill")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("Screen Recording")
                    Spacer()
                    if permissions.screenCaptureGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant") {
                            permissions.openScreenCapturePreferences()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundColor(.purple)
                        .frame(width: 20)
                    Text("Accessibility (for input)")
                    Spacer()
                    if permissions.accessibilityGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant") {
                            permissions.requestAccessibilityPermission()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.leading, 8)
            
            Spacer()
        }
        .padding()
        .task {
            await permissions.checkPermissions()
        }
    }
}

struct LocalCastSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        LocalCastSettingsView()
            .frame(width: 400, height: 500)
    }
}





