import SwiftUI

/// In-app Privacy Policy and Terms & Conditions viewer.
struct LegalView: View {
    enum LegalPage { case privacy, terms }
    let page: LegalPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(page == .privacy ? "Privacy Policy" : "Terms & Conditions")
                    .font(DS.display(32))
                    .tracking(-1)
                    .foregroundStyle(DS.inkAdaptive)

                Text("Last updated: September 1, 2026")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.subAdaptive)

                Text(page == .privacy ? privacyText : termsText)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DS.inkAdaptive)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 80)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Privacy Policy

    private var privacyText: String { """
Radflow ("we", "our", "us") is committed to protecting the privacy of our users. This Privacy Policy explains how we collect, use, and safeguard your information when you use the Radflow mobile application.

1. INFORMATION WE COLLECT

• Account Information: When you sign in with Apple, we receive your Apple ID, email address (which may be a relay address), and name.
• Dictation Data: Audio captured during dictation is processed on-device using speech recognition technology. Raw audio is never transmitted to external servers.
• Report Data: Reports you create are stored locally on your device using encrypted storage. If you choose to export or share reports, that data leaves your device per your explicit action.
• Usage Analytics: We may collect anonymized usage statistics to improve the app experience. No personally identifiable information is included.

2. HOW WE USE YOUR INFORMATION

• To provide and maintain the dictation and reporting service
• To authenticate your identity and manage your account
• To process AI-assisted report structuring
• To improve app performance and user experience

3. DATA STORAGE & SECURITY

• All dictation processing occurs on-device by default
• Reports are stored locally in encrypted storage
• Account credentials are managed through Apple's Sign in with Apple service and Supabase authentication
• We use industry-standard security measures to protect your data

4. HEALTH INFORMATION (PHI)

• Radflow may process Protected Health Information (PHI) as part of medical report creation
• We do not transmit PHI to third parties without explicit user action (e.g., sharing via PDF or WhatsApp)
• Users are responsible for ensuring their use of Radflow complies with applicable regulations (HIPAA, local data protection laws)

5. MICROPHONE & SPEECH RECOGNITION

• The app requires microphone access for dictation purposes only
• Speech recognition is performed on-device
• Audio data is not stored permanently and is discarded after transcription

6. PHOTO LIBRARY

• Camera/photo access is used solely to attach medical images to reports
• Images are stored locally within the app's secure container

7. THIRD-PARTY SERVICES

• Apple Sign In: Subject to Apple's privacy policy
• Supabase: Used for authentication. Subject to Supabase's privacy policy
• AI Processing: Report structuring may use cloud-based AI services. Only report text (not audio) is transmitted, and only when actively processing

8. DATA RETENTION & DELETION

• You may delete your account at any time through the app settings
• Account deletion removes all server-side data permanently
• Local data can be removed by uninstalling the app

9. CHILDREN'S PRIVACY

• Radflow is not intended for use by individuals under 17 years of age

10. CHANGES TO THIS POLICY

• We may update this Privacy Policy from time to time. Changes will be reflected in the app and on our website.

11. CONTACT US

• For privacy-related inquiries, contact us at privacy@radflow.app
• GitHub: https://github.com/Souravgupta2111/RadFlow
"""
    }

    // MARK: - Terms & Conditions

    private var termsText: String { """
Please read these Terms & Conditions carefully before using the Radflow mobile application.

1. ACCEPTANCE OF TERMS

By downloading, installing, or using Radflow, you agree to be bound by these Terms & Conditions. If you do not agree, do not use the app.

2. DESCRIPTION OF SERVICE

Radflow is a medical dictation and report-building productivity tool designed for radiologists and healthcare professionals. It provides:
• On-device speech-to-text dictation
• AI-assisted report structuring and formatting
• Report template management
• PDF generation and sharing capabilities

3. MEDICAL DISCLAIMER

RADFLOW IS NOT A MEDICAL DEVICE. It is a documentation and productivity tool only. Radflow does not provide medical diagnoses, clinical recommendations, or treatment advice. All AI-generated content is for documentation assistance only and must be reviewed, verified, and approved by a qualified medical professional before clinical use. Users are solely responsible for the accuracy of all medical reports.

4. USER RESPONSIBILITIES

• You are responsible for maintaining the confidentiality of your account
• You must comply with all applicable healthcare regulations and privacy laws
• You must not use Radflow as a substitute for professional medical judgment
• You are responsible for backing up your data

5. INTELLECTUAL PROPERTY

• The Radflow app and its content are owned by Radflow and protected by copyright laws
• Report templates and content you create remain your intellectual property

6. SUBSCRIPTION & PAYMENT

• Certain features of Radflow may require a paid subscription
• Payment is processed through Apple's App Store
• Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period

7. LIMITATION OF LIABILITY

• Radflow is provided "as is" without warranties of any kind
• We are not liable for any clinical decisions made based on reports generated using Radflow
• We are not liable for data loss due to device failure or user error
• Our total liability shall not exceed the amount paid for the service in the preceding 12 months

8. TERMINATION

• We reserve the right to suspend or terminate your account for violation of these terms
• You may terminate your account at any time through the app settings

9. GOVERNING LAW

• These terms are governed by the laws of India

10. CHANGES TO TERMS

• We may modify these terms at any time. Continued use constitutes acceptance of modified terms.

11. CONTACT

• For questions about these terms, contact us at support@radflow.app
• GitHub: https://github.com/Souravgupta2111/RadFlow
"""
    }
}
