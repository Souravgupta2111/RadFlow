import Foundation
import SwiftData

@Model final class Patient {
    var name: String
    @Attribute(.unique) var mrn: String
    var arrNumber: String
    var dateOfBirth: Date?
    var sex: String
    var phone: String
    var referringPhysician: String
    var allergiesAlert: String
    var chronicConditions: [String]
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \RadiologyReport.patient)
    var reports: [RadiologyReport] = []

    init(name: String,
         mrn: String = "",
         arrNumber: String = "",
         dateOfBirth: Date? = nil,
         sex: String = "Unknown",
         phone: String = "",
         referringPhysician: String = "",
         allergiesAlert: String = "",
         chronicConditions: [String] = []) {
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.sex = sex
        self.phone = phone
        self.referringPhysician = referringPhysician
        self.allergiesAlert = allergiesAlert
        self.chronicConditions = chronicConditions
        self.createdAt = Date()
        
        if mrn.isEmpty {
            self.mrn = "\(Calendar.current.component(.year, from: Date()))-\(Int.random(in: 100000...999999))"
        } else {
            self.mrn = mrn
        }

        if arrNumber.isEmpty {
            self.arrNumber = "ARR-\(Int.random(in: 10000...99999))"
        } else {
            self.arrNumber = arrNumber
        }
    }
    
    var age: Int {
        guard let dob = dateOfBirth else { return 0 }
        return Calendar.current.dateComponents([.year], from: dob, to: .now).year ?? 0
    }
}

enum ReportStatus: String, Codable { case draft, signed, amended }
enum ReportPriority: String, Codable { case routine, urgent, stat }

@Model final class RadiologyReport {
    var title: String
    var modality: String
    var accessionNumber: String
    var studyDate: Date
    var sections: [ReportSection]
    var status: ReportStatus
    var priority: ReportPriority
    var createdAt: Date
    var updatedAt: Date
    var signedAt: Date?
    var imageItems: [ImageItem]
    var legacyImageMigrated: Bool = false
    
    // Patient Action Plan & Summary (Bilingual / Plain Language)
    var patientAdviceSummary: String?
    var recommendedTests: [String] = []
    var followUpAdvice: String?
    var medicationsOrPrecautions: String?
    var aiDiscrepancyNotes: [String] = []
    var icd10Codes: [String] = []
    var cptCodes: [String] = []
    var patientLanguage: String = "English"
    var localizedPatientSummary: String?
    
    // Legacy support for older schema
    var patientName: String?
    var imageData: Data?

    @Relationship(deleteRule: .nullify)
    var patient: Patient?

    @Relationship(deleteRule: .nullify)
    var template: ReportTemplate?

    init(title: String, modality: String = "Chest XR", accessionNumber: String = "", priority: ReportPriority = .routine) {
        self.title = title
        self.modality = modality
        self.accessionNumber = accessionNumber
        self.studyDate = Date()
        self.sections = []
        self.status = .draft
        self.priority = priority
        self.createdAt = Date()
        self.updatedAt = Date()
        self.imageItems = []
        self.recommendedTests = []
        self.aiDiscrepancyNotes = []
        self.icd10Codes = []
        self.cptCodes = []
        self.patientLanguage = "English"
    }

    var plainText: String {
        sections.map { "\($0.heading)\n\($0.text)" }.joined(separator: "\n\n")
    }
}

@Model final class ClinicProfile {
    var clinicName: String
    var tagline: String
    var address: String
    var cityStateZip: String
    var phone: String
    var email: String
    var website: String
    var doctorName: String
    var doctorQualifications: String
    var doctorRegNumber: String
    var logoData: Data?
    var signatureData: Data?
    var themeColorHex: String
    var templateStyle: String
    var isDefault: Bool
    var createdAt: Date

    init(clinicName: String = "Metro Imaging & Diagnostic Center",
         tagline: String = "Advanced Radiology & Multi-Slice CT Scanning",
         address: String = "104 Healthcare Boulevard, Medical Enclave",
         cityStateZip: String = "New Delhi, DL 110029",
         phone: String = "+91 (011) 4567-8900",
         email: String = "reports@metroimaging.org",
         website: String = "www.metroimaging.org",
         doctorName: String = "Dr. Rajesh Sharma, MD",
         doctorQualifications: String = "MD (Radiodiagnosis), FRCR (London)",
         doctorRegNumber: String = "DMC-84920",
         logoData: Data? = nil,
         signatureData: Data? = nil,
         themeColorHex: String = "#0A84FF",
         templateStyle: String = "modern",
         isDefault: Bool = true) {
        self.clinicName = clinicName
        self.tagline = tagline
        self.address = address
        self.cityStateZip = cityStateZip
        self.phone = phone
        self.email = email
        self.website = website
        self.doctorName = doctorName
        self.doctorQualifications = doctorQualifications
        self.doctorRegNumber = doctorRegNumber
        self.logoData = logoData
        self.signatureData = signatureData
        self.themeColorHex = themeColorHex
        self.templateStyle = templateStyle
        self.isDefault = isDefault
        self.createdAt = Date()
    }
}

@Model final class ImageItem {
    var data: Data
    var caption: String
    var addedAt: Date
    var analysisResult: String

    init(data: Data, caption: String = "", analysisResult: String = "") {
        self.data = data
        self.caption = caption
        self.addedAt = Date()
        self.analysisResult = analysisResult
    }
}

enum BlockColumn: String, Codable { case left, right, fullWidth }
enum BlockType: String, Codable { case text, vitalsGrid, checkbox, pencilKitDrawing }

struct TemplateBlockConfig: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var placeholder: String
    var column: BlockColumn
    var blockType: BlockType
    var defaultContent: String
    var isRequired: Bool
    var minHeight: CGFloat

    init(title: String, placeholder: String = "", column: BlockColumn = .fullWidth,
         blockType: BlockType = .text, defaultContent: String = "",
         isRequired: Bool = false, minHeight: CGFloat = 80) {
        self.title = title
        self.placeholder = placeholder
        self.column = column
        self.blockType = blockType
        self.defaultContent = defaultContent
        self.isRequired = isRequired
        self.minHeight = minHeight
    }
}

struct ReportSection: Codable, Hashable, Identifiable {
    var id = UUID()
    var heading: String
    var text: String
    var isLocked: Bool = false
    var macroExpanded: Bool = false
    var isAIPolished: Bool = false
    var column: String = "fullWidth" // "left", "right", "fullWidth"
    var blockType: String = "text"   // "text", "vitalsGrid", "checkbox", "pencilKitDrawing"
    var drawingData: Data? = nil      // Stores Apple Pencil drawings
}

struct VoiceMacro: Codable, Hashable, Identifiable {
    var id = UUID()
    var trigger: String
    var expansion: String
    var targetHeading: String
}

@Model final class ReportTemplate {
    var name: String
    var modality: String
    var headings: [String]
    var macros: [VoiceMacro]
    var isBuiltIn: Bool
    var createdAt: Date

    // Modular Canva-Style Layout & Design Properties
    var layoutType: String         // "twoColumnSplit", "singleColumn", "vitalsGrid", "matrix"
    var accentColorHex: String     // Primary color e.g. "#0F172A", "#0A84FF"
    var backgroundColorHex: String // Paper color e.g. "#FFFFFF"
    var cardTintHex: String        // Subtle box fill e.g. "#FFF1F2" (pastel rose), "#F0FDF4", "#F8FAFC"
    var borderColorHex: String     // Box outline e.g. "#CBD5E1", "#FDA4AF"
    var fontFamily: String         // "sans", "serif", "mono"
    var borderWidth: Float         // 1.0, 1.5, 2.0
    var cornerRadius: Float        // 0 (crisp), 8, 12, 16
    var headerTitle: String        // "MEDICAL CHART", "RADIOLOGY REPORT"
    var subtitle: String           // "CLINICAL EVALUATION NOTE"
    var blocks: [TemplateBlockConfig]

    init(name: String,
         modality: String = "General",
         headings: [String] = [],
         macros: [VoiceMacro] = [],
         isBuiltIn: Bool = false,
         layoutType: String = "twoColumnSplit",
         accentColorHex: String = "#0F172A",
         backgroundColorHex: String = "#FFFFFF",
         cardTintHex: String = "#FFF1F2",
         borderColorHex: String = "#E2E8F0",
         fontFamily: String = "sans",
         borderWidth: Float = 1.0,
         cornerRadius: Float = 6.0,
         headerTitle: String = "MEDICAL CHART",
         subtitle: String = "CLINICAL EVALUATION & PROGRESS NOTE",
         blocks: [TemplateBlockConfig] = []) {
        self.name = name
        self.modality = modality
        self.headings = headings.isEmpty ? blocks.map(\.title) : headings
        self.macros = macros
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
        self.layoutType = layoutType
        self.accentColorHex = accentColorHex
        self.backgroundColorHex = backgroundColorHex
        self.cardTintHex = cardTintHex
        self.borderColorHex = borderColorHex
        self.fontFamily = fontFamily
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.headerTitle = headerTitle
        self.subtitle = subtitle
        self.blocks = blocks
    }
}

@Model final class DictationSession {
    var startedAt: Date
    var endedAt: Date?
    var engineUsed: String
    var rawTranscript: String
    var wordErrorRate: Float?
    var report: RadiologyReport?
    
    init(engineUsed: String) {
        self.startedAt = Date()
        self.engineUsed = engineUsed
        self.rawTranscript = ""
    }
}

