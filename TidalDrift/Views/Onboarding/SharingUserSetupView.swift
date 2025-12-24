import SwiftUI

struct SharingUserSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    @State private var wantsNewUser = true
    @State private var username = "screenshare"
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isCreatingUser = false
    @State private var creationResult: CreationResult?
    @State private var showPassword = false
    
    enum CreationResult {
        case success
        case failure(String)
    }
    
    var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    
    var isValidUsername: Bool {
        let pattern = "^[a-z][a-z0-9_]{2,30}$"
        return username.range(of: pattern, options: .regularExpression) != nil
    }
    
    var body: some View {
        VStack(spacing: 24) {
            header
            
            optionSelector
            
            if wantsNewUser {
                userCreationForm
            } else {
                skipExplanation
            }
            
            if let result = creationResult {
                resultView(result)
            }
            
            Spacer()
            
            navigationButtons
        }
        .padding(32)
    }
    
    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            Text("Screen Sharing Account")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("For security, we recommend creating a dedicated account for screen sharing instead of using your admin credentials.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var optionSelector: some View {
        VStack(spacing: 12) {
            OptionCard(
                title: "Create Sharing Account",
                description: "Create a dedicated user for screen sharing (recommended)",
                icon: "person.badge.plus",
                isSelected: wantsNewUser
            ) {
                wantsNewUser = true
            }
            
            OptionCard(
                title: "Use Existing Account",
                description: "I'll use my current user account for screen sharing",
                icon: "person.fill",
                isSelected: !wantsNewUser
            ) {
                wantsNewUser = false
            }
        }
    }
    
    private var userCreationForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Account Details")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Username")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("screenshare", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                
                if !username.isEmpty && !isValidUsername {
                    Text("Username must be lowercase, start with a letter, 3-31 characters")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Password")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    if showPassword {
                        TextField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if !password.isEmpty && password.count < 8 {
                    Text("Password must be at least 8 characters")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm Password")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                SecureField("Confirm password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                
                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords don't match")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            // Info box
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                
                Text("This will create a standard (non-admin) user account that can only be used for screen sharing. You'll need to enter your admin password to create it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    private var skipExplanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Using Your Admin Account")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("When you share your screen, you'll use your current macOS username and password. This gives full access to anyone who connects.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
            )
            
            Text("You can create a sharing account later in System Settings > Users & Groups.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
    
    @ViewBuilder
    private func resultView(_ result: CreationResult) -> some View {
        switch result {
        case .success:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Account Created Successfully!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Username: \(username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.1))
            )
            
        case .failure(let error):
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Failed to Create Account")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.1))
            )
        }
    }
    
    private var navigationButtons: some View {
        HStack {
            Button("Back") {
                viewModel.previousStep()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            if wantsNewUser {
                if case .success = creationResult {
                    Button("Continue") {
                        viewModel.nextStep()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        createSharingUser()
                    } label: {
                        HStack {
                            if isCreatingUser {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("Create Account")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!passwordsMatch || !isValidUsername || password.count < 8 || isCreatingUser)
                }
            } else {
                Button("Continue") {
                    viewModel.nextStep()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private func createSharingUser() {
        isCreatingUser = true
        creationResult = nil
        
        // Use AppleScript to create user with admin privileges
        let script = """
        do shell script "sysadminctl -addUser \(username) -password '\(escapeForShell(password))' -hint 'Screen sharing account'" with administrator privileges
        """
        
        Task {
            let success = await SharingConfigurationService.shared.executeAppleScript(script)
            
            await MainActor.run {
                isCreatingUser = false
                if success {
                    creationResult = .success
                    // Save the username for later use
                    UserDefaults.standard.set(username, forKey: "screenShareUsername")
                } else {
                    creationResult = .failure("Could not create user. The username may already exist, or the operation was cancelled.")
                }
            }
        }
    }
    
    private func escapeForShell(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
    }
}

struct OptionCard: View {
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .accentColor)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.1))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct SharingUserSetupView_Previews: PreviewProvider {
    static var previews: some View {
        SharingUserSetupView(viewModel: OnboardingViewModel())
            .frame(width: 500, height: 650)
    }
}

