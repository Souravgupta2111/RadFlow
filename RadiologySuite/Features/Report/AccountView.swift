import SwiftUI

/// Account management: Sign In with Apple, Sign Out, Delete Account.
struct AccountView: View {
    @ObservedObject private var auth = AuthService.shared
    @State private var showDeleteConfirm = false
    @State private var showDeleteSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    Text("Account")
                        .font(DS.display(44))
                        .tracking(-1.6)
                        .foregroundStyle(DS.inkAdaptive)
                    Spacer()
                }

                if auth.isSignedIn {
                    signedInContent
                } else {
                    signedOutContent
                }

                if let err = auth.errorMessage {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete Account", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) {
                Task {
                    let ok = await auth.deleteAccount()
                    if ok { showDeleteSuccess = true }
                }
            }
        } message: {
            Text("This will permanently delete your account and all data from our servers. This action cannot be undone.")
        }
        .alert("Account Deleted", isPresented: $showDeleteSuccess) {
            Button("OK") {}
        } message: {
            Text("Your account has been deleted successfully.")
        }
    }

    // MARK: - Signed In

    private var signedInContent: some View {
        VStack(spacing: 14) {
            // User Info Card
            Tile {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(DS.coral)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.userDisplayName ?? "Radflow User")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(DS.inkAdaptive)
                            Text(auth.userEmail ?? "Signed in with Apple")
                                .font(.system(size: 13))
                                .foregroundStyle(DS.subAdaptive)
                        }
                    }
                }
            }

            // Sign Out
            Button {
                auth.signOut()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Sign Out")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(DS.inkAdaptive)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(DS.cardAdaptive))
                .overlay(RoundedRectangle(cornerRadius: DS.radius).strokeBorder(DS.lineAdaptive))
            }
            .buttonStyle(.plain)

            // Delete Account
            Button {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Delete Account")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: DS.radius).fill(Color.red.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: DS.radius).strokeBorder(Color.red.opacity(0.2)))
            }
            .buttonStyle(.plain)

            Text("Deleting your account will remove all your data from our servers permanently.")
                .font(.system(size: 12))
                .foregroundStyle(DS.subAdaptive)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Signed Out

    private var signedOutContent: some View {
        VStack(spacing: 18) {
            Tile {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(DS.coral)

                    Text("Sign in to sync your data and manage your subscription.")
                        .font(DS.bodyFont)
                        .foregroundStyle(DS.subAdaptive)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            // Sign In with Apple button
            Button {
                auth.signInWithApple()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Sign in with Apple")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black))
            }
            .buttonStyle(.plain)
            .disabled(auth.isLoading)
            .opacity(auth.isLoading ? 0.6 : 1)

            if auth.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
