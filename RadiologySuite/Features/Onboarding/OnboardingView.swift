import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @AppStorage("onboarding.complete") var onboardingComplete = false

    @AppStorage("user.name") private var userName = ""
    @AppStorage("user.hospital") private var hospitalName = ""
    @AppStorage("welcome.complete") private var welcomeComplete = false

    var body: some View {
        ZStack {
            if !welcomeComplete {
                WelcomeView()
                    .transition(.opacity)
            } else {
                loginContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: welcomeComplete)
    }
    
    private var loginContent: some View {
        VStack(spacing: 0) {
            // Welcome header with branding
            VStack(spacing: 16) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(DS.coral)
                    .padding(.top, 40)

                Text("Welcome to Radflow")
                    .font(DS.display(34))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DS.inkAdaptive)

                Text("Dictate. Structure. Share.\nYour reports in seconds.")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.subAdaptive)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Profile setup
            VStack(spacing: 16) {
                SettingsTextField(placeholder: "Name (e.g. Dr. Smith)", text: $userName)
                SettingsTextField(placeholder: "Hospital / Practice name", text: $hospitalName)
            }
            .padding(.top, 40)
            .padding(.horizontal, 8)

            Spacer()

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authResults):
                    if let appleIDCredential = authResults.credential as? ASAuthorizationAppleIDCredential {
                        if let email = appleIDCredential.email {
                            UserDefaults.standard.set(email, forKey: "user.appleEmail")
                        }
                        
                        Task {
                            await AuthService.shared.handleAppleCredential(appleIDCredential, doctorName: userName, hospitalName: hospitalName)
                            
                            if AuthService.shared.isSignedIn {
                                // Proceed with onboarding
                                UserDefaults.standard.set(true, forKey: "dictation.useMedASR")
                                UserDefaults.standard.set(true, forKey: "dictation.liveAI")
                                UserDefaults.standard.set(true, forKey: "privacy.auditTrail")
                                onboardingComplete = true
                            }
                        }
                    }
                case .failure(let error):
                    print("Apple sign in failed: \(error.localizedDescription)")
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .disabled(userName.isEmpty || hospitalName.isEmpty || AuthService.shared.isLoading)
            .opacity(userName.isEmpty || hospitalName.isEmpty ? 0.5 : 1)
            
            if AuthService.shared.isLoading {
                ProgressView()
                    .padding(.top, 16)
            } else if let err = AuthService.shared.errorMessage {
                Text(err)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
            }
        }
        .padding(32)
        .background(DS.paperAdaptive.ignoresSafeArea())
        .onAppear {
            MedASREngine.shared.preload()
        }
    }
}
