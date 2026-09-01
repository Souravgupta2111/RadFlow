import Foundation

/// Central configuration for Supabase REST API calls.
enum SupabaseConfig {
    static let projectURL = "https://htqheofokgmpggzfwgbq.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh0cWhlb2Zva2dtcGdnemZ3Z2JxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgyNDg4NjQsImV4cCI6MjEwMzgyNDg2NH0.RM7hcRkFaYjx4P6oD1B6hi51kuF_sflyz2DDAoHG8mw"

    /// Auth endpoints
    static var signUpURL: URL { URL(string: "\(projectURL)/auth/v1/signup")! }
    static var signInURL: URL { URL(string: "\(projectURL)/auth/v1/token?grant_type=id_token")! }
    static var signOutURL: URL { URL(string: "\(projectURL)/auth/v1/logout")! }
    static var userURL: URL { URL(string: "\(projectURL)/auth/v1/user")! }

    /// Standard headers for every Supabase request.
    static var baseHeaders: [String: String] {
        [
            "apikey": anonKey,
            "Content-Type": "application/json"
        ]
    }

    /// Headers that include the user's access token.
    static func authHeaders(accessToken: String) -> [String: String] {
        var h = baseHeaders
        h["Authorization"] = "Bearer \(accessToken)"
        return h
    }
}
