import SwiftUI
import UIKit

enum ReportRenderer {
    static func pdf(for report: RadiologyReport, clinic: ClinicProfile? = nil) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 46
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let themeColor = UIColor(hex: clinic?.themeColorHex ?? "#0A84FF")
        let clinicName = (clinic?.clinicName ?? UserDefaults.standard.string(forKey: "user.hospital") ?? UserDefaults.standard.string(forKey: "hospital.name") ?? "METRO IMAGING & DIAGNOSTIC CENTER").uppercased()
        let clinicAddress = clinic?.address ?? "104 Healthcare Boulevard, Medical Enclave"
        let clinicCity = clinic?.cityStateZip ?? "New Delhi, DL 110029"
        let clinicPhone = clinic?.phone ?? "+91 (011) 4567-8900"
        let clinicEmail = clinic?.email ?? "reports@metroimaging.org"
        let doctorName = clinic?.doctorName ?? UserDefaults.standard.string(forKey: "user.name") ?? ((try? KeychainService.load(key: "user.name")) ?? "Dr. Sourav Gupta")
        let doctorQual = clinic?.doctorQualifications ?? "MD (Radiodiagnosis), FRCR"
        let doctorReg = clinic?.doctorRegNumber ?? "DMC-84920"

        return renderer.pdfData { ctx in
            // ==================== PAGE 1: FORMAL RADIOLOGY REPORT ====================
            ctx.beginPage()
            var y = margin
            let maxWidth = pageRect.width - margin * 2

            // Header: Logo + Clinic Info
            var textStartX = margin
            if let logoData = clinic?.logoData, let logoImg = UIImage(data: logoData) {
                let logoRect = CGRect(x: margin, y: y, width: 44, height: 44)
                logoImg.draw(in: logoRect)
                textStartX = margin + 54
            }

            drawCustom(clinicName, at: &y, x: textStartX, size: 16, weight: .heavy, color: themeColor, width: maxWidth - (textStartX - margin))
            drawCustom(clinic?.tagline ?? "Advanced Diagnostic & Multi-Slice CT Center", at: &y, x: textStartX, size: 9, weight: .semibold, color: .darkGray, width: maxWidth - (textStartX - margin))
            drawCustom("\(clinicAddress), \(clinicCity) | Tel: \(clinicPhone) | \(clinicEmail)", at: &y, x: textStartX, size: 8, weight: .regular, color: .gray, width: maxWidth - (textStartX - margin))
            
            y = max(y, margin + 48) + 4
            
            // Accent Color Line (Canva Header Style)
            drawAccentBar(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageRect.width - margin, y: y), color: themeColor, height: 3)
            y += 10

            // Title & Patient Demographics Box
            let headerDocTitle = report.template?.headerTitle ?? "DEPARTMENT OF RADIODIAGNOSIS · \(report.modality.uppercased()) STUDY"
            draw(headerDocTitle, at: &y, size: 12, weight: .bold, color: themeColor, width: maxWidth)
            y += 2
            
            let patientText = report.patient?.name ?? report.patientName ?? "Unknown Patient"
            let mrnText = report.patient?.mrn ?? "—"
            let dobText = report.patient?.dateOfBirth?.formatted(date: .abbreviated, time: .omitted) ?? "—"
            let phoneText = report.patient?.phone.isEmpty == false ? report.patient?.phone ?? "—" : "—"
            
            let demoBox = """
            Patient Name: \(patientText) | MRN: \(mrnText) | Phone: \(phoneText)
            Age/Sex: \(report.patient?.age ?? 0)y / \(report.patient?.sex ?? "—") | DOB: \(dobText) | Accession: \(report.accessionNumber.isEmpty ? "ACC-\(Int.random(in: 1000...9999))" : report.accessionNumber)
            Date of Study: \(report.studyDate.formatted(date: .long, time: .shortened)) | Priority: \(report.priority.rawValue.capitalized)
            """
            
            drawBoxedText(demoBox, at: &y, margin: margin, width: maxWidth, bg: UIColor(white: 0.96, alpha: 1.0))
            y += 10

            // 2-Column Split Layout Rendering
            if report.template?.layoutType == "twoColumnSplit" {
                let leftWidth = (maxWidth - 12) * 0.42
                let rightWidth = (maxWidth - 12) * 0.58
                let startY = y
                var leftY = startY
                var rightY = startY
                let rightX = margin + leftWidth + 12

                let leftSections = report.sections.filter { $0.column == "left" }
                let rightSections = report.sections.filter { $0.column == "right" }
                let fullSections = report.sections.filter { $0.column == "fullWidth" }

                // Full width blocks first
                for sec in fullSections {
                    draw(sec.heading.uppercased(), at: &leftY, size: 10, weight: .bold, color: themeColor, width: maxWidth)
                    leftY += 2
                    drawBoxedText(sec.text.isEmpty ? "—" : sec.text, at: &leftY, margin: margin, width: maxWidth, bg: UIColor(white: 0.98, alpha: 1.0))
                    leftY += 8
                }
                rightY = leftY

                // Left column sections
                for sec in leftSections {
                    drawCustom(sec.heading.uppercased(), at: &leftY, x: margin, size: 9.5, weight: .bold, color: themeColor, width: leftWidth)
                    leftY += 2
                    let text = sec.text.isEmpty ? "—" : sec.text
                    drawBoxedText(text, at: &leftY, margin: margin, width: leftWidth, bg: UIColor(white: 0.99, alpha: 1.0))
                    leftY += 6
                }

                // Right column sections
                for sec in rightSections {
                    drawCustom(sec.heading.uppercased(), at: &rightY, x: rightX, size: 9.5, weight: .bold, color: themeColor, width: rightWidth)
                    rightY += 2

                    if sec.blockType == "pencilKitDrawing", let drawData = sec.drawingData, let img = UIImage(data: drawData) {
                        let drawRect = CGRect(x: rightX, y: rightY, width: rightWidth, height: 70)
                        img.draw(in: drawRect)
                        rightY += 76
                    } else {
                        let text = sec.text.isEmpty ? "—" : sec.text
                        // Soft tinted box for right column (matching Canva style)
                        drawBoxedText(text, at: &rightY, margin: rightX, width: rightWidth, bg: UIColor(red: 1.0, green: 0.96, blue: 0.96, alpha: 1.0))
                        rightY += 6
                    }
                }

                y = max(leftY, rightY) + 8
            } else {
                // Sequential Single-Column Report Sections
                for section in report.sections {
                    if y > pageRect.height - 130 {
                        ctx.beginPage()
                        y = margin
                    }
                    draw(section.heading.uppercased(), at: &y, size: 11, weight: .bold, color: themeColor, width: maxWidth)
                    y += 2
                    if section.blockType == "pencilKitDrawing", let drawData = section.drawingData, let img = UIImage(data: drawData) {
                        let drawRect = CGRect(x: margin, y: y, width: maxWidth, height: 80)
                        img.draw(in: drawRect)
                        y += 88
                    } else {
                        draw(section.text.isEmpty ? "—" : section.text, at: &y, size: 10.5, weight: .regular, color: .black, width: maxWidth)
                        y += 10
                    }
                }
            }

            // Doctor Signature & Authentication at bottom of Page 1
            let sigY = max(y + 10, pageRect.height - 90)
            if let sigData = clinic?.signatureData, let sigImg = UIImage(data: sigData) {
                let sigRect = CGRect(x: pageRect.width - margin - 120, y: sigY - 24, width: 100, height: 26)
                sigImg.draw(in: sigRect)
            }
            var footY = sigY
            drawCustom("Digitally signed by: \(doctorName)", at: &footY, x: pageRect.width - margin - 220, size: 9, weight: .bold, color: .black, width: 220, align: .right)
            drawCustom("\(doctorQual) · Reg: \(doctorReg)", at: &footY, x: pageRect.width - margin - 220, size: 8, weight: .regular, color: .gray, width: 220, align: .right)

            // Medical Disclaimer — Always included (Guideline 1.4.1)
            let disclaimerY = pageRect.height - 30
            var dY = disclaimerY
            drawCustom("Generated using Radflow dictation software. This is a documentation aid only and does not constitute a clinical diagnosis. All content must be reviewed by a qualified medical professional.", at: &dY, x: margin, size: 7, weight: .regular, color: .gray, width: maxWidth, align: .center)

            // ==================== PAGE 2: PATIENT CARE ACTION PLAN ====================
            if let summary = report.patientAdviceSummary, !summary.isEmpty {
                ctx.beginPage()
                y = margin
                
                // Patient Care Banner
                draw("PATIENT CARE SUMMARY & ACTION PLAN", at: &y, size: 15, weight: .heavy, color: themeColor, width: maxWidth)
                draw("मरीज के लिए जांच का संक्षिप्त विवरण एवं जरूरी सलाह (Plain Language Summary)", at: &y, size: 9.5, weight: .medium, color: .darkGray, width: maxWidth)
                y += 4
                drawAccentBar(from: CGPoint(x: margin, y: y), to: CGPoint(x: pageRect.width - margin, y: y), color: themeColor, height: 2)
                y += 14

                // 1. Kya hua hai / Summary Card
                draw("1. WHAT WAS FOUND (जांच में क्या निकला):", at: &y, size: 11, weight: .bold, color: .black, width: maxWidth)
                y += 2
                drawBoxedText(summary, at: &y, margin: margin, width: maxWidth, bg: UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1.0))
                y += 14

                // 2. Advised Tests / Ye test lene hain
                if !report.recommendedTests.isEmpty {
                    draw("2. RECOMMENDED TESTS / NEXT STEPS (ये टेस्ट या कदम जरूरी हैं):", at: &y, size: 11, weight: .bold, color: .black, width: maxWidth)
                    y += 2
                    let testList = report.recommendedTests.map { "• \($0)" }.joined(separator: "\n")
                    drawBoxedText(testList, at: &y, margin: margin, width: maxWidth, bg: UIColor(red: 0.97, green: 0.95, blue: 1.0, alpha: 1.0))
                    y += 14
                }

                // 3. Next Follow-up & Precautions
                if let followUp = report.followUpAdvice, !followUp.isEmpty {
                    draw("3. NEXT APPOINTMENT & PRECAUTIONS (अगली बार कब आएं व सावधानियां):", at: &y, size: 11, weight: .bold, color: .black, width: maxWidth)
                    y += 2
                    let prec = report.medicationsOrPrecautions ?? "Take prescribed medicines and consult your doctor."
                    let adviceText = "Follow-up: \(followUp)\nPrecautions: \(prec)"
                    drawBoxedText(adviceText, at: &y, margin: margin, width: maxWidth, bg: UIColor(red: 0.95, green: 0.99, blue: 0.95, alpha: 1.0))
                    y += 14
                }

                // Disclaimer Box
                let disclaimer = "Note: This summary is generated to help patients understand their findings and does not replace direct consultation with your treating physician."
                var discY = pageRect.height - 60
                drawCustom(disclaimer, at: &discY, x: margin, size: 8, weight: .regular, color: .gray, width: maxWidth, align: .center)
            }
        }
    }

    private static func draw(_ text: String, at y: inout CGFloat, size: CGFloat,
                             weight: UIFont.Weight, color: UIColor, width: CGFloat) {
        drawCustom(text, at: &y, x: 46, size: size, weight: weight, color: color, width: width)
    }

    private static func drawCustom(_ text: String, at y: inout CGFloat, x: CGFloat, size: CGFloat,
                                   weight: UIFont.Weight, color: UIColor, width: CGFloat,
                                   align: NSTextAlignment = .left) {
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let attr = NSAttributedString(string: text + "\n", attributes: attrs)
        let bounds = attr.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], context: nil)
        attr.draw(with: CGRect(x: x, y: y, width: width, height: ceil(bounds.height)),
                  options: [.usesLineFragmentOrigin], context: nil)
        y += ceil(bounds.height) + 2
    }

    private static func drawBoxedText(_ text: String, at y: inout CGFloat, margin: CGFloat, width: CGFloat, bg: UIColor) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.black,
            .paragraphStyle: para
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let bounds = attr.boundingRect(
            with: CGSize(width: width - 16, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], context: nil)
        
        let boxRect = CGRect(x: margin, y: y, width: width, height: ceil(bounds.height) + 16)
        let path = UIBezierPath(roundedRect: boxRect, cornerRadius: 6)
        ctx.setFillColor(bg.cgColor)
        path.fill()
        
        attr.draw(in: CGRect(x: margin + 8, y: y + 8, width: width - 16, height: ceil(bounds.height)))
        y += ceil(bounds.height) + 20
    }

    private static func drawAccentBar(from p1: CGPoint, to p2: CGPoint, color: UIColor, height: CGFloat) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        c.setStrokeColor(color.cgColor)
        c.setLineWidth(height)
        c.move(to: p1); c.addLine(to: p2); c.strokePath()
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
