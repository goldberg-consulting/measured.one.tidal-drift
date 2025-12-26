import SwiftUI
import Combine

class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var screenSharingEnabled: Bool = false
    @Published var fileSharingEnabled: Bool = false
    @Published var remoteLoginEnabled: Bool = false
    @Published var canProceed: Bool = true
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        Publishers.CombineLatest3($screenSharingEnabled, $fileSharingEnabled, $remoteLoginEnabled)
            .sink { [weak self] _, _, _ in
                self?.updateCanProceed()
            }
            .store(in: &cancellables)
    }
    
    func updateCanProceed() {
        switch currentStep {
        case .welcome:
            canProceed = true
        case .screenSharing:
            canProceed = screenSharingEnabled
        case .sharingUser:
            canProceed = true // User can skip or create account
        case .fileSharing:
            canProceed = fileSharingEnabled
        case .sshSetup:
            canProceed = true // SSH is optional but recommended
        case .firewall:
            canProceed = true
        case .completion:
            canProceed = true
        }
    }
    
    func nextStep() {
        guard let nextStepValue = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            return
        }
        currentStep = nextStepValue
        updateCanProceed()
    }
    
    func previousStep() {
        guard let prevStepValue = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = prevStepValue
        updateCanProceed()
    }
    
    func goToStep(_ step: OnboardingStep) {
        currentStep = step
        updateCanProceed()
    }
    
    var progress: Double {
        Double(currentStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
    
    var currentStepIndex: Int {
        currentStep.rawValue + 1
    }
    
    var totalSteps: Int {
        OnboardingStep.allCases.count
    }
}
