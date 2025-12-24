import SwiftUI

struct OnboardingContainerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var healthService = PermissionHealthService.shared
    @State private var isFinalizingSetup = false
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 0) {
                progressIndicator
                    .padding(.top, 24)
                
                currentStepView
                    .frame(maxHeight: .infinity)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .id(viewModel.currentStep)
                
                navigationButtons
                    .padding(.vertical, 24)
            }
            .padding(.horizontal, 50)
            
            // Overlay while finalizing setup
            if isFinalizingSetup {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Finalizing Setup...")
                        .font(.headline)
                    Text("Verifying permissions and fixing any issues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(radius: 20)
                )
            }
        }
        .frame(minWidth: 700, minHeight: 620)
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .windowBackgroundColor).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var progressIndicator: some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step == viewModel.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .scaleEffect(step == viewModel.currentStep ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: viewModel.currentStep)
            }
        }
    }
    
    @ViewBuilder
    private var currentStepView: some View {
        switch viewModel.currentStep {
        case .welcome:
            WelcomeStepView()
        case .screenSharing:
            ScreenSharingSetupView(viewModel: viewModel)
        case .sharingUser:
            SharingUserSetupView(viewModel: viewModel)
        case .fileSharing:
            FileSharingSetupView(viewModel: viewModel)
        case .firewall:
            FirewallSetupView(viewModel: viewModel)
        case .completion:
            CompletionStepView(viewModel: viewModel)
        }
    }
    
    private var navigationButtons: some View {
        HStack {
            if viewModel.currentStep != .welcome && viewModel.currentStep != .completion {
                Button("Back") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.previousStep()
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if viewModel.currentStep == .completion {
                Button("Get Started") {
                    Task {
                        await finalizeSetup()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isFinalizingSetup)
            } else if viewModel.canProceed {
                Button(viewModel.currentStep == .welcome ? "Let's Go" : "Continue") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.nextStep()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button("Skip for Now") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.nextStep()
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
    
    @MainActor
    private func finalizeSetup() async {
        isFinalizingSetup = true
        
        // Run health check and auto-fix any stuck permissions
        let _ = await healthService.performStartupHealthCheck()
        
        // Small delay for visual feedback
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        isFinalizingSetup = false
        
        // Complete onboarding
        withAnimation {
            AppState.shared.hasCompletedOnboarding = true
            NetworkDiscoveryService.shared.startBrowsing()
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case screenSharing
    case sharingUser  // New: Create dedicated sharing account
    case fileSharing
    case firewall
    case completion
}

struct OnboardingContainerView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingContainerView()
            .environmentObject(AppState.shared)
    }
}
