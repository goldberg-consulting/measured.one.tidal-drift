import SwiftUI
import Combine

class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var screenSharingEnabled: Bool = false
    @Published var fileSharingEnabled: Bool = false
    @Published var canProceed: Bool = true
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        Publishers.CombineLatest($screenSharingEnabled, $fileSharingEnabled)
            .sink { [weak self] screen, file in
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
        case .fileSharing:
            canProceed = fileSharingEnabled
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
