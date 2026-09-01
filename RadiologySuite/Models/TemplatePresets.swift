import Foundation

/// Curated catalog of built-in report templates — the single source of truth
/// used by the seeder, the template builder's "Load Presets" menu, and the
/// template picker. Includes India "parcha" (prescription pad) styles that
/// clinics can adopt as-is or reshape in the builder.
enum TemplatePresets {

    struct Preset {
        let name: String
        let modality: String
        let headerTitle: String
        let subtitle: String
        let layoutType: String
        let accentColorHex: String
        let backgroundColorHex: String
        let cardTintHex: String
        let borderColorHex: String
        let fontFamily: String
        let borderWidth: Float
        let cornerRadius: Float
        let blocks: [TemplateBlockConfig]
        let macros: [VoiceMacro]

        init(name: String,
             modality: String = "General",
             headerTitle: String,
             subtitle: String,
             layoutType: String = "twoColumnSplit",
             accentColorHex: String,
             backgroundColorHex: String = "#FFFFFF",
             cardTintHex: String,
             borderColorHex: String,
             fontFamily: String = "sans",
             borderWidth: Float = 1.0,
             cornerRadius: Float = 6.0,
             blocks: [TemplateBlockConfig],
             macros: [VoiceMacro] = []) {
            self.name = name
            self.modality = modality
            self.headerTitle = headerTitle
            self.subtitle = subtitle
            self.layoutType = layoutType
            self.accentColorHex = accentColorHex
            self.backgroundColorHex = backgroundColorHex
            self.cardTintHex = cardTintHex
            self.borderColorHex = borderColorHex
            self.fontFamily = fontFamily
            self.borderWidth = borderWidth
            self.cornerRadius = cornerRadius
            self.blocks = blocks
            self.macros = macros
        }
    }

    static let all: [Preset] = [
        // 1. Outpatient chart — full clinical note
        Preset(
            name: "Medical Chart (Outpatient)",
            modality: "General",
            headerTitle: "MEDICAL CHART",
            subtitle: "OUTPATIENT CLINICAL & PROGRESS NOTE",
            layoutType: "twoColumnSplit",
            accentColorHex: "#0F172A",
            cardTintHex: "#FFF1F2",
            borderColorHex: "#E2E8F0",
            cornerRadius: 4.0,
            blocks: [
                TemplateBlockConfig(title: "VITALS & DEMOGRAPHICS", placeholder: "BP: 120/80 | T: 98.6F | P: 72 | R: 16 | Ht: 5'10 | Wt: 70kg | BMI: 22.4 | O2: 99%", column: .fullWidth, blockType: .vitalsGrid, minHeight: 65),
                TemplateBlockConfig(title: "HISTORY OF PRESENT ILLNESS", placeholder: "Onset, duration, character, aggravating and relieving factors…", column: .left, minHeight: 120),
                TemplateBlockConfig(title: "PAST MEDICAL HISTORY", placeholder: "Hypertension, Diabetes, prior hospitalizations…", column: .left, minHeight: 80),
                TemplateBlockConfig(title: "ALLERGIES / MEDICATION HISTORY", placeholder: "Known drug allergies, current prescriptions…", column: .left, minHeight: 80),
                TemplateBlockConfig(title: "FAMILY HISTORY", placeholder: "Cardiovascular, malignancy, hereditary conditions…", column: .left, minHeight: 70),
                TemplateBlockConfig(title: "SOCIAL HISTORY", placeholder: "Tobacco, alcohol, occupation, lifestyle…", column: .left, minHeight: 70),
                TemplateBlockConfig(title: "PHYSICAL EXAM", placeholder: "General appearance, chest, CVS, abdomen, CNS findings…", column: .right, minHeight: 120),
                TemplateBlockConfig(title: "DIAGNOSIS", placeholder: "Primary and differential clinical diagnoses…", column: .right, minHeight: 90),
                TemplateBlockConfig(title: "PLAN & MEDICATIONS", placeholder: "Investigations, therapeutic regimen, lifestyle advice…", column: .right, minHeight: 140),
                TemplateBlockConfig(title: "FOLLOW UP", placeholder: "Review after 1 week / SOS if symptoms worsen", column: .right, blockType: .checkbox, minHeight: 50)
            ],
            macros: [
                VoiceMacro(trigger: "vitals normal", expansion: "BP 120/80 mmHg, Pulse 72/min, Resp 16/min, Temp 98.4F, SpO2 99%", targetHeading: "VITALS & DEMOGRAPHICS"),
                VoiceMacro(trigger: "exam normal", expansion: "Patient is conscious, oriented. Chest clear, S1 S2 normal, per abdomen soft, non-tender.", targetHeading: "PHYSICAL EXAM")
            ]
        ),

        // 2. Parcha — the classic Indian prescription pad, digitized
        Preset(
            name: "Clinic Parcha (Prescription Pad)",
            modality: "General",
            headerTitle: "OPD PRESCRIPTION",
            subtitle: "पर्चा · OUTPATIENT SLIP",
            layoutType: "twoColumnSplit",
            accentColorHex: "#0F766E",
            cardTintHex: "#F0FDFA",
            borderColorHex: "#99F6E4",
            cornerRadius: 6.0,
            blocks: [
                TemplateBlockConfig(title: "PATIENT DETAILS", placeholder: "Name | Age/Sex | Weight | BP | Pulse | Temp | SpO2", column: .fullWidth, blockType: .vitalsGrid, minHeight: 60),
                TemplateBlockConfig(title: "CHIEF COMPLAINTS (C/O)", placeholder: "Complaints with duration — e.g. fever x 3 days, cough…", column: .left, minHeight: 90),
                TemplateBlockConfig(title: "ON EXAMINATION (O/E)", placeholder: "General exam, systemic findings…", column: .left, minHeight: 110),
                TemplateBlockConfig(title: "PAST HISTORY & ALLERGIES", placeholder: "DM/HTN/TB…, drug allergies…", column: .left, minHeight: 70),
                TemplateBlockConfig(title: "DIAGNOSIS (Dx)", placeholder: "Provisional / final diagnosis…", column: .right, minHeight: 70),
                TemplateBlockConfig(title: "Rx — MEDICATIONS", placeholder: "Tab/Cap/Syrup — dose — frequency — duration…", column: .right, minHeight: 140),
                TemplateBlockConfig(title: "ADVICE & PRECAUTIONS", placeholder: "Diet, fluids, rest, warning signs…", column: .right, minHeight: 80),
                TemplateBlockConfig(title: "FOLLOW UP", placeholder: "Review after ___ days / SOS", column: .right, blockType: .checkbox, minHeight: 50)
            ],
            macros: [
                VoiceMacro(trigger: "advice routine", expansion: "Take plenty of fluids, light diet, and complete the full course. Return immediately if symptoms worsen.", targetHeading: "ADVICE & PRECAUTIONS"),
                VoiceMacro(trigger: "vitals normal", expansion: "BP 120/80 mmHg, Pulse 76/min, Temp 98.2F, SpO2 98%", targetHeading: "PATIENT DETAILS")
            ]
        ),

        // 3. Parcha — quick single-page OPD slip
        Preset(
            name: "OPD Quick Slip",
            modality: "General",
            headerTitle: "OPD SLIP",
            subtitle: "QUICK CONSULTATION NOTE",
            layoutType: "singleColumn",
            accentColorHex: "#B45309",
            cardTintHex: "#FFFBEB",
            borderColorHex: "#FDE68A",
            cornerRadius: 4.0,
            blocks: [
                TemplateBlockConfig(title: "VITALS", placeholder: "BP | Pulse | Temp | SpO2 | Weight", column: .fullWidth, blockType: .vitalsGrid, minHeight: 55),
                TemplateBlockConfig(title: "C/O", placeholder: "Complaints with duration…", column: .fullWidth, minHeight: 70),
                TemplateBlockConfig(title: "O/E", placeholder: "Examination findings…", column: .fullWidth, minHeight: 100),
                TemplateBlockConfig(title: "DIAGNOSIS", placeholder: "Diagnosis…", column: .fullWidth, minHeight: 60),
                TemplateBlockConfig(title: "Rx — MEDICATIONS", placeholder: "Medications — dose — frequency — duration…", column: .fullWidth, minHeight: 120),
                TemplateBlockConfig(title: "FOLLOW UP", placeholder: "Review after ___ days", column: .fullWidth, blockType: .checkbox, minHeight: 50)
            ],
            macros: [
                VoiceMacro(trigger: "rx full course", expansion: "Complete the full course of medications as prescribed.", targetHeading: "Rx — MEDICATIONS")
            ]
        ),

        // 4. Structured radiology report
        Preset(
            name: "RSNA Structured Radiology",
            modality: "XR",
            headerTitle: "RADIOLOGY CONSULTATION REPORT",
            subtitle: "DIAGNOSTIC IMAGING EVALUATION",
            layoutType: "twoColumnSplit",
            accentColorHex: "#0284C7",
            cardTintHex: "#F0F9FF",
            borderColorHex: "#BAE6FD",
            cornerRadius: 6.0,
            blocks: [
                TemplateBlockConfig(title: "CLINICAL INDICATION", placeholder: "Reason for study, presenting complaints, clinical question to answer…", column: .left, minHeight: 90),
                TemplateBlockConfig(title: "TECHNIQUE & PROTOCOL", placeholder: "Modality, slice thickness, IV contrast timing, views taken…", column: .left, minHeight: 80),
                TemplateBlockConfig(title: "COMPARISON", placeholder: "Compared with prior scan dated…", column: .left, minHeight: 70),
                TemplateBlockConfig(title: "FINDINGS", placeholder: "Lungs, Pleura, Mediastinum, Heart, Bones, Soft Tissues…", column: .right, minHeight: 180),
                TemplateBlockConfig(title: "IMPRESSION", placeholder: "1. Primary diagnostic conclusions…", column: .right, minHeight: 110),
                TemplateBlockConfig(title: "RADS / FLEISCHNER RECOMMENDATION", placeholder: "Guidelines-based follow-up interval or next imaging test…", column: .right, minHeight: 65)
            ],
            macros: [
                VoiceMacro(trigger: "normal chest", expansion: "Lungs are clear bilaterally without focal consolidation, pneumothorax, or effusion. Cardiomediastinal silhouette is normal.", targetHeading: "FINDINGS"),
                VoiceMacro(trigger: "no acute", expansion: "No acute cardiopulmonary disease.", targetHeading: "IMPRESSION")
            ]
        ),

        // 5. Patient-facing bilingual action plan
        Preset(
            name: "Patient Care & Action Plan",
            modality: "General",
            headerTitle: "PATIENT CARE SUMMARY & ACTION PLAN",
            subtitle: "मरीज के लिए जांच का विवरण एवं जरूरी सलाह",
            layoutType: "twoColumnSplit",
            accentColorHex: "#059669",
            cardTintHex: "#ECFDF5",
            borderColorHex: "#A7F3D0",
            cornerRadius: 8.0,
            blocks: [
                TemplateBlockConfig(title: "EXECUTIVE DIAGNOSTIC SUMMARY", placeholder: "Key diagnosis and major findings explained clearly…", column: .fullWidth, minHeight: 90),
                TemplateBlockConfig(title: "WHAT WAS FOUND (जांच में क्या निकला)", placeholder: "Simple language explanation without alarming jargon…", column: .left, minHeight: 110),
                TemplateBlockConfig(title: "ADVISED TESTS (ये टेस्ट करवाने हैं)", placeholder: "Actionable next investigations (e.g. repeat USG, blood panel)…", column: .left, minHeight: 90),
                TemplateBlockConfig(title: "MEDICATIONS & PRECAUTIONS (दवाइयां व परहेज)", placeholder: "Prescribed drugs, dietary precautions, activity modifications…", column: .right, minHeight: 110),
                TemplateBlockConfig(title: "NEXT APPOINTMENT (अगली बार कब आएं)", placeholder: "Specific date or interval for follow-up review…", column: .right, minHeight: 90)
            ]
        ),

        // 6. Ultrasound organ matrix
        Preset(
            name: "Ultrasound Organ Matrix",
            modality: "US",
            headerTitle: "ULTRASONOGRAPHY REPORT",
            subtitle: "ABDOMINAL & PELVIC SCAN",
            layoutType: "twoColumnSplit",
            accentColorHex: "#6366F1",
            cardTintHex: "#F5F3FF",
            borderColorHex: "#DDD6FE",
            cornerRadius: 6.0,
            blocks: [
                TemplateBlockConfig(title: "LIVER & BILIARY TREE", placeholder: "Size, echotexture, surface, focal lesions, IHBR status…", column: .left, minHeight: 80),
                TemplateBlockConfig(title: "GALLBLADDER", placeholder: "Lumen, wall thickness, calculi, pericholecystic fluid…", column: .left, minHeight: 70),
                TemplateBlockConfig(title: "SPLEEN & PANCREAS", placeholder: "Spleen size/texture, pancreas head/body/tail, MPD…", column: .left, minHeight: 70),
                TemplateBlockConfig(title: "KIDNEYS (BILATERAL)", placeholder: "Right and left kidney size, CMD, cortical thickness, calculi, hydronephrosis…", column: .right, minHeight: 90),
                TemplateBlockConfig(title: "URINARY BLADDER & PELVIS", placeholder: "Distension, wall thickness, pre/post void volume, uterus/ovaries/prostate…", column: .right, minHeight: 90),
                TemplateBlockConfig(title: "IMPRESSION & ADVICE", placeholder: "Final sonographic impression and recommended correlation…", column: .right, minHeight: 90)
            ],
            macros: [
                VoiceMacro(trigger: "usg normal", expansion: "Liver, gallbladder, pancreas, spleen, and bilateral kidneys are normal in size and architecture. No calculus or hydronephrosis.", targetHeading: "LIVER & BILIARY TREE")
            ]
        ),

        // 7. Emergency STAT note
        Preset(
            name: "Emergency STAT Note",
            modality: "CT",
            headerTitle: "STAT EMERGENCY CLINICAL NOTE",
            subtitle: "IMMEDIATE CRITICAL ACTION REQUIRED",
            layoutType: "twoColumnSplit",
            accentColorHex: "#E11D48",
            cardTintHex: "#FFF1F2",
            borderColorHex: "#FECDD3",
            fontFamily: "mono",
            borderWidth: 1.5,
            cornerRadius: 4.0,
            blocks: [
                TemplateBlockConfig(title: "STAT TRIAGE & PRIMARY SURVEY", placeholder: "Airway, breathing, hemodynamics, Glasgow Coma Scale (GCS)…", column: .fullWidth, minHeight: 75),
                TemplateBlockConfig(title: "CRITICAL IMAGING FINDINGS", placeholder: "Hemorrhage, pneumothorax, visceral injury, fractures…", column: .left, minHeight: 120),
                TemplateBlockConfig(title: "URGENT CLINICAL ACTIONS", placeholder: "Chest tube, blood transfusion, emergent surgical consultation…", column: .right, minHeight: 120),
                TemplateBlockConfig(title: "DOCTOR NOTIFICATION LOG", placeholder: "Treating consultant informed via phone at [time] by Dr. [Name]", column: .fullWidth, minHeight: 60)
            ]
        )
    ]
}
