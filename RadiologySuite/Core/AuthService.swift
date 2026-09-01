import Foundation
import AuthenticationServices
import SwiftUI
import SwiftData

/// Lightweight Supabase-backed auth service using Sign in with Apple + REST API.
@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published var isSignedIn = false
    @Published var userEmail: String?
    @Published var userDisplayName: String?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Stored in Keychain so tokens survive app restarts.
    private var accessToken: String? {
        get { try? KeychainService.load(key: "supabase.accessToken") }
        set {
            if let v = newValue { try? KeychainService.save(key: "supabase.accessToken", value: v) }
            else { try? KeychainService.delete(key: "supabase.accessToken") }
        }
    }
    private var refreshToken: String? {
        get { try? KeychainService.load(key: "supabase.refreshToken") }
        set {
            if let v = newValue { try? KeychainService.save(key: "supabase.refreshToken", value: v) }
            else { try? KeychainService.delete(key: "supabase.refreshToken") }
        }
    }
    private var userId: String? {
        get { UserDefaults.standard.string(forKey: "supabase.userId") }
        set { UserDefaults.standard.set(newValue, forKey: "supabase.userId") }
    }

    private var appleSignInContinuation: CheckedContinuation<ASAuthorization, Error>?

    override init() {
        super.init()
        // Restore session
        if accessToken != nil {
            isSignedIn = true
            userEmail = UserDefaults.standard.string(forKey: "supabase.userEmail")
            userDisplayName = UserDefaults.standard.string(forKey: "supabase.userDisplayName")
            // Silently refresh user data
            Task { await fetchUser() }
        }
    }

    private var pendingDoctorName: String?
    private var pendingHospitalName: String?
    
    // MARK: - Sign In with Apple

    func signInWithApple(doctorName: String? = nil, hospitalName: String? = nil) {
        self.pendingDoctorName = doctorName
        self.pendingHospitalName = hospitalName
        isLoading = true
        errorMessage = nil

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    /// Called by the ASAuthorizationController delegate after Apple auth succeeds.
    func handleAppleCredential(_ credential: ASAuthorizationAppleIDCredential, doctorName: String? = nil, hospitalName: String? = nil) async {
        if let d = doctorName { self.pendingDoctorName = d }
        if let h = hospitalName { self.pendingHospitalName = h }
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            isLoading = false
            errorMessage = "Could not read Apple identity token."
            return
        }

        // Extract name if provided (only on first sign-in)
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        if !fullName.isEmpty {
            userDisplayName = fullName
            UserDefaults.standard.set(fullName, forKey: "supabase.userDisplayName")
        }

        // Exchange the Apple identity token with Supabase
        do {
            let body: [String: Any] = [
                "provider": "apple",
                "id_token": identityToken
            ]
            var request = URLRequest(url: SupabaseConfig.signInURL)
            request.httpMethod = "POST"
            request.allHTTPHeaderFields = SupabaseConfig.baseHeaders
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AuthError.serverError(errorBody)
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            accessToken = json["access_token"] as? String
            refreshToken = json["refresh_token"] as? String

            if let user = json["user"] as? [String: Any] {
                userId = user["id"] as? String
                userEmail = user["email"] as? String
                UserDefaults.standard.set(userEmail, forKey: "supabase.userEmail")
            }
            
            // Push doctor Name and Hospital to Supabase metadata
            if let token = accessToken, let doctor = pendingDoctorName, let hospital = pendingHospitalName {
                Task {
                    await updateSupabaseProfile(accessToken: token, name: doctor, hospital: hospital)
                }
            }

            isSignedIn = true
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Sign in failed: \(error.localizedDescription)"
        }
    }
    
    private func updateSupabaseProfile(accessToken: String, name: String, hospital: String) async {
        var request = URLRequest(url: SupabaseConfig.userURL)
        request.httpMethod = "PUT"
        request.allHTTPHeaderFields = SupabaseConfig.authHeaders(accessToken: accessToken)
        let body: [String: Any] = [
            "data": [
                "doctor_name": name,
                "hospital": hospital
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Sign Out

    func signOut() {
        Task {
            if let token = accessToken {
                var request = URLRequest(url: SupabaseConfig.signOutURL)
                request.httpMethod = "POST"
                request.allHTTPHeaderFields = SupabaseConfig.authHeaders(accessToken: token)
                _ = try? await URLSession.shared.data(for: request)
            }
            clearSession()
        }
    }

    // MARK: - Delete Account

    func deleteAccount() async -> Bool {
        guard let token = accessToken, userId != nil else {
            errorMessage = "Not signed in."
            return false
        }
        isLoading = true

        // Call Supabase Edge Function or RPC to delete the user.
        // The admin delete endpoint requires service_role key which must NOT be in the client.
        // We use an RPC function: `delete_own_account` that the user sets up in Supabase SQL editor.
        //
        // SQL to create in Supabase:
        // CREATE OR REPLACE FUNCTION delete_own_account()
        // RETURNS void AS $$
        // BEGIN
        //   DELETE FROM auth.users WHERE id = auth.uid();
        // END;
        // $$ LANGUAGE plpgsql SECURITY DEFINER;
        //
        // Then call it via REST:
        do {
            let rpcURL = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/rpc/delete_own_account")!
            var request = URLRequest(url: rpcURL)
            request.httpMethod = "POST"
            request.allHTTPHeaderFields = SupabaseConfig.authHeaders(accessToken: token)
            request.httpBody = "{}".data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse

            if let status = http?.statusCode, (200...299).contains(status) {
                clearSession()
                isLoading = false
                return true
            } else {
                // Fallback: sign out locally even if server delete fails
                let body = String(data: data, encoding: .utf8) ?? ""
                errorMessage = "Account deletion request sent. Server: \(body)"
                clearSession()
                isLoading = false
                return true
            }
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
            isLoading = false
            return false
        }
    }

    // MARK: - Fetch User

    private func fetchUser() async {
        guard let token = accessToken else { return }
        var request = URLRequest(url: SupabaseConfig.userURL)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = SupabaseConfig.authHeaders(accessToken: token)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Token might be expired — clear session
            if accessToken != nil { clearSession() }
            return
        }
        userEmail = json["email"] as? String
        userId = json["id"] as? String
        UserDefaults.standard.set(userEmail, forKey: "supabase.userEmail")
        isSignedIn = true
    }

    // MARK: - Helpers

    private func clearSession() {
        accessToken = nil
        refreshToken = nil
        userId = nil
        userEmail = nil
        userDisplayName = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: "supabase.userEmail")
        UserDefaults.standard.removeObject(forKey: "supabase.userDisplayName")
        UserDefaults.standard.removeObject(forKey: "supabase.userId")
        
        try? KeychainService.delete(key: "supabase.accessToken")
        try? KeychainService.delete(key: "supabase.refreshToken")
        
        UserDefaults.standard.removeObject(forKey: "user.name")
        UserDefaults.standard.removeObject(forKey: "user.hospital")
        
        // Wipe local database
        let ctx = ModelContext(RadiologySuiteApp.sharedContainer)
        try? ctx.delete(model: Patient.self)
        try? ctx.delete(model: RadiologyReport.self)
        try? ctx.delete(model: ReportTemplate.self)
        try? ctx.delete(model: DictationSession.self)
        try? ctx.delete(model: ImageItem.self)
        try? ctx.delete(model: ClinicProfile.self)
        try? ctx.save()
        
        UserDefaults.standard.set(false, forKey: "onboarding.complete")
        UserDefaults.standard.set(false, forKey: "welcome.complete")
    }

    enum AuthError: LocalizedError {
        case serverError(String)
        var errorDescription: String? {
            switch self {
            case .serverError(let msg): return msg
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
        Task { @MainActor in
            await handleAppleCredential(credential)
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor in
            isLoading = false
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }
}
