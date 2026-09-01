import Foundation

/// Fast on-device and AI-assisted ICD-10 and CPT coding engine for radiology & clinical encounters.
struct MedicalCodingService {
    static let shared = MedicalCodingService()

    struct MedicalCode: Identifiable, Hashable {
        let id: String
        let code: String
        let description: String
        let category: String // "ICD-10" or "CPT"
    }

    // Curated High-Frequency Clinical Coding Knowledge Base
    private let icdKnowledgeBase: [MedicalCode] = [
        .init(id: "J18.9", code: "J18.9", description: "Pneumonia, unspecified organism", category: "ICD-10"),
        .init(id: "R91.1", code: "R91.1", description: "Solitary pulmonary nodule", category: "ICD-10"),
        .init(id: "J90", code: "J90", description: "Pleural effusion, not elsewhere classified", category: "ICD-10"),
        .init(id: "J98.11", code: "J98.11", description: "Atelectasis", category: "ICD-10"),
        .init(id: "J93.9", code: "J93.9", description: "Pneumothorax, unspecified", category: "ICD-10"),
        .init(id: "I51.7", code: "I51.7", description: "Cardiomegaly", category: "ICD-10"),
        .init(id: "K80.20", code: "K80.20", description: "Calculus of gallbladder without cholecystitis", category: "ICD-10"),
        .init(id: "K76.0", code: "K76.0", description: "Fatty (change of) liver, not elsewhere classified", category: "ICD-10"),
        .init(id: "N20.0", code: "N20.0", description: "Calculus of kidney (Nephrolithiasis)", category: "ICD-10"),
        .init(id: "M54.50", code: "M54.50", description: "Low back pain, unspecified", category: "ICD-10"),
        .init(id: "M17.9", code: "M17.9", description: "Osteoarthritis of knee, unspecified", category: "ICD-10"),
        .init(id: "S72.001A", code: "S72.001A", description: "Fracture of head of right femur, initial", category: "ICD-10"),
        .init(id: "I63.9", code: "I63.9", description: "Cerebral infarction, unspecified (Ischemic Stroke)", category: "ICD-10"),
        .init(id: "R51.9", code: "R51.9", description: "Headache, unspecified", category: "ICD-10"),
        .init(id: "K35.80", code: "K35.80", description: "Unspecified acute appendicitis", category: "ICD-10"),
        .init(id: "Z01.89", code: "Z01.89", description: "Encounter for other specified pre-procedural exams", category: "ICD-10")
    ]

    private let cptKnowledgeBase: [MedicalCode] = [
        .init(id: "71045", code: "71045", description: "Chest X-Ray; single view (PA/AP)", category: "CPT"),
        .init(id: "71046", code: "71046", description: "Chest X-Ray; 2 views (PA & Lateral)", category: "CPT"),
        .init(id: "70450", code: "70450", description: "CT Head / Brain without contrast", category: "CPT"),
        .init(id: "70470", code: "70470", description: "CT Head / Brain with & without contrast", category: "CPT"),
        .init(id: "71250", code: "71250", description: "CT Thorax / Chest without contrast", category: "CPT"),
        .init(id: "74177", code: "74177", description: "CT Abdomen & Pelvis with contrast", category: "CPT"),
        .init(id: "76700", code: "76700", description: "Ultrasound, abdominal, real-time with image documentation", category: "CPT"),
        .init(id: "76770", code: "76770", description: "Ultrasound, retroperitoneal (KUB / Renal)", category: "CPT"),
        .init(id: "76856", code: "76856", description: "Ultrasound, pelvic (non-obstetric)", category: "CPT"),
        .init(id: "73721", code: "73721", description: "MRI Knee without contrast", category: "CPT"),
        .init(id: "72148", code: "72148", description: "MRI Lumbar Spine without contrast", category: "CPT"),
        .init(id: "70551", code: "70551", description: "MRI Brain without contrast", category: "CPT"),
        .init(id: "99214", code: "99214", description: "Office or outpatient encounter, established patient (30-39 min)", category: "CPT")
    ]

    /// Analyzes the report text and suggests relevant ICD-10 diagnostic codes.
    func suggestICD10(for reportText: String) -> [MedicalCode] {
        let lower = reportText.lowercased()
        var matches: [MedicalCode] = []

        if lower.contains("pneumonia") || lower.contains("consolidation") || lower.contains("infiltrate") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "J18.9" }) { matches.append(code) }
        }
        if lower.contains("nodule") || lower.contains("mass") || lower.contains("coin lesion") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "R91.1" }) { matches.append(code) }
        }
        if lower.contains("effusion") || lower.contains("fluid") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "J90" }) { matches.append(code) }
        }
        if lower.contains("atelectasis") || lower.contains("collapse") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "J98.11" }) { matches.append(code) }
        }
        if lower.contains("pneumothorax") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "J93.9" }) { matches.append(code) }
        }
        if lower.contains("cardiomegaly") || lower.contains("enlarged cardiac") || lower.contains("heart enlarged") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "I51.7" }) { matches.append(code) }
        }
        if lower.contains("gallstone") || lower.contains("cholelithiasis") || lower.contains("calculus of gallbladder") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "K80.20" }) { matches.append(code) }
        }
        if lower.contains("fatty liver") || lower.contains("steatosis") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "K76.0" }) { matches.append(code) }
        }
        if lower.contains("kidney stone") || lower.contains("nephrolithiasis") || lower.contains("renal calculus") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "N20.0" }) { matches.append(code) }
        }
        if lower.contains("back pain") || lower.contains("lumbar") || lower.contains("disc") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "M54.50" }) { matches.append(code) }
        }
        if lower.contains("osteoarthritis") || lower.contains("degenerative joint") || lower.contains("knee pain") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "M17.9" }) { matches.append(code) }
        }
        if lower.contains("fracture") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "S72.001A" }) { matches.append(code) }
        }
        if lower.contains("infarct") || lower.contains("ischemia") || lower.contains("stroke") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "I63.9" }) { matches.append(code) }
        }
        if lower.contains("appendicitis") {
            if let code = icdKnowledgeBase.first(where: { $0.code == "K35.80" }) { matches.append(code) }
        }

        if matches.isEmpty {
            if let defaultCode = icdKnowledgeBase.first(where: { $0.code == "Z01.89" }) { matches.append(defaultCode) }
        }

        return matches
    }

    /// Analyzes modality & anatomy to suggest CPT procedure codes.
    func suggestCPT(for modality: String, title: String) -> [MedicalCode] {
        let combined = "\(modality) \(title)".lowercased()
        var matches: [MedicalCode] = []

        if combined.contains("chest") || combined.contains("cxr") || combined.contains("xr") {
            if combined.contains("2 view") || combined.contains("lateral") {
                if let code = cptKnowledgeBase.first(where: { $0.code == "71046" }) { matches.append(code) }
            } else {
                if let code = cptKnowledgeBase.first(where: { $0.code == "71045" }) { matches.append(code) }
            }
        }
        if combined.contains("ct") && combined.contains("head") {
            if let code = cptKnowledgeBase.first(where: { $0.code == "70450" }) { matches.append(code) }
        }
        if combined.contains("ct") && (combined.contains("chest") || combined.contains("thorax")) {
            if let code = cptKnowledgeBase.first(where: { $0.code == "71250" }) { matches.append(code) }
        }
        if combined.contains("ct") && (combined.contains("abdomen") || combined.contains("pelvis")) {
            if let code = cptKnowledgeBase.first(where: { $0.code == "74177" }) { matches.append(code) }
        }
        if combined.contains("ultrasound") || combined.contains("usg") || combined.contains("us") {
            if combined.contains("abdomen") {
                if let code = cptKnowledgeBase.first(where: { $0.code == "76700" }) { matches.append(code) }
            } else if combined.contains("kub") || combined.contains("renal") {
                if let code = cptKnowledgeBase.first(where: { $0.code == "76770" }) { matches.append(code) }
            } else {
                if let code = cptKnowledgeBase.first(where: { $0.code == "76856" }) { matches.append(code) }
            }
        }
        if combined.contains("mri") {
            if combined.contains("knee") {
                if let code = cptKnowledgeBase.first(where: { $0.code == "73721" }) { matches.append(code) }
            } else if combined.contains("lumbar") || combined.contains("spine") {
                if let code = cptKnowledgeBase.first(where: { $0.code == "72148" }) { matches.append(code) }
            } else {
                if let code = cptKnowledgeBase.first(where: { $0.code == "70551" }) { matches.append(code) }
            }
        }

        if matches.isEmpty {
            if let defaultCode = cptKnowledgeBase.first(where: { $0.code == "99214" }) { matches.append(defaultCode) }
        }

        return matches
    }
}
