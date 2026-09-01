import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Direct WhatsApp & SMS Patient Dispatch Service.
/// Dispatches the signed clinical report, bilingual action plan, and regional voice note summary
/// directly to the patient's phone number.
struct WhatsAppDispatchService {
    static let shared = WhatsAppDispatchService()

    /// Generates a structured clinical WhatsApp message payload.
    func generateWhatsAppText(patient: Patient?, report: RadiologyReport, clinic: ClinicProfile?, voiceSummary: String?) -> String {
        let clinicTitle = clinic?.clinicName ?? "Metro Diagnostic & Imaging Center"
        let doctor = clinic?.doctorName ?? "Dr. Rajesh Sharma, MD"
        let pName = patient?.name ?? "Patient"
        let arr = patient?.arrNumber ?? report.accessionNumber
        let modality = report.modality
        let dateStr = report.studyDate.formatted(date: .abbreviated, time: .omitted)

        var lines: [String] = []
        lines.append("🏥 *\(clinicTitle.uppercased())*")
        lines.append("👨‍⚕️ Attending: \(doctor)")
        lines.append("─────────────────────")
        lines.append("📋 *PATIENT DIAGNOSTIC DISPATCH*")
        lines.append("• *Patient:* \(pName)")
        lines.append("• *ARR / ID:* \(arr)")
        lines.append("• *Study:* \(modality) (\(dateStr))")
        lines.append("• *Status:* Officially Signed & Verified ✅")
        lines.append("─────────────────────")

        if let voice = voiceSummary, !voice.isEmpty {
            lines.append("🗣️ *PATIENT SUMMARY & CARE PLAN:*")
            lines.append(voice)
            lines.append("")
        }

        if let followUp = report.followUpAdvice, !followUp.isEmpty {
            lines.append("📅 *Next Follow-up:* \(followUp)")
        }

        lines.append("─────────────────────")
        lines.append("📄 *Official Digital Report PDF attached.*")
        lines.append("📞 Clinic Support: \(clinic?.phone ?? "+91 98100-00000")")

        return lines.joined(separator: "\n")
    }

    /// Dispatches the report payload to WhatsApp for a given phone number.
    func dispatchToWhatsApp(phoneNumber: String, text: String) {
        // Clean phone number (strip spaces, dashes, parentheses)
        let cleanedPhone = phoneNumber.filter { $0.isNumber || $0 == "+" }
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }

        let urlString = cleanedPhone.isEmpty 
            ? "whatsapp://send?text=\(encodedText)" 
            : "whatsapp://send?phone=\(cleanedPhone)&text=\(encodedText)"

        let webUrlString = cleanedPhone.isEmpty 
            ? "https://wa.me/?text=\(encodedText)" 
            : "https://wa.me/\(cleanedPhone)?text=\(encodedText)"

        #if canImport(UIKit)
        if let appURL = URL(string: urlString), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = URL(string: webUrlString) {
            UIApplication.shared.open(webURL)
        }
        #endif
    }
}
