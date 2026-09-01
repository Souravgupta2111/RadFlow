# RadiologySuite — Complete End-to-End Implementation Plan

> Native iOS 17 + iPadOS 17 · SwiftUI + SwiftData · MedASR CoreML · GPT-4o Vision
> No mock data, no placeholders, no stubs. Everything ships real.

---

## Current state snapshot

| Layer | What exists | What's missing |
|---|---|---|
| ASR | AppleStreamingEngine (working), MedASREngine (wired, needs model bundle) | Model conversion, vocab bundle, 16kHz resample ✓ done |
| Data model | Patient, RadiologyReport, ReportSection, ReportTemplate | Relationships, DOB, accession#, referring physician, image array |
| Report builder | Section cards, AI insights (mock-gated), PDF export | Template picker, per-section AI polish, voice macros |
| Template system | TemplateSeeder (4 hardcoded), ReportTemplate model | Template builder UI, custom headings, section macros |
| Imaging | PhotosPicker + GPT-4o-mini call | GPT-4o vision payload, multi-image, DICOM placeholder |
| Patient mgmt | Add/list (MRN, age, sex) | DOB, referring physician, accession, per-patient report history |
| LLM | OpenAICompatibleService, MockLLMService | Vision payload, streaming, error handling, model routing |
| iPad layout | Phone layout stretched to iPad | NavigationSplitView, keyboard shortcuts, drag-and-drop |
| Export | PDF via UIGraphicsPDFRenderer | HL7, structured PDF with hospital header, print via UIPrintInteractionController |
| Settings | API key, model ID, MedASR status | Provider picker, LLM endpoint, font/layout prefs, export header config |
| Onboarding | None | First-launch setup: provider key, hospital name, radiologist name |

---

## Phase 1 — Data model foundation (do first, everything else depends on it)

### 1.1 Rebuild Store.swift with proper relationships

**File:** `RadiologySuite/Models/Store.swift`

Replace the current flat model:

```swift
@Model final class Patient {
    var name: String
    var mrn: String                         // Medical Record Number
    var dateOfBirth: Date?
    var sex: String                         // "M" | "F" | "Other"
    var phone: String
    var referringPhysician: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \RadiologyReport.patient)
    var reports: [RadiologyReport] = []
}

@Model final class RadiologyReport {
    var title: String
    var modality: String                    // XR | CT | MR | US | NM | FL | MG
    var accessionNumber: String             // auto-generated if blank
    var studyDate: Date
    var sections: [ReportSection]
    var status: ReportStatus                // draft | signed | amended
    var priority: ReportPriority            // routine | urgent | stat
    var createdAt: Date
    var updatedAt: Date
    var signedAt: Date?
    var imageItems: [ImageItem]             // replaces single imageData

    @Relationship(deleteRule: .nullify)
    var patient: Patient?

    @Relationship(deleteRule: .nullify)
    var template: ReportTemplate?
}

enum ReportStatus: String, Codable { case draft, signed, amended }
enum ReportPriority: String, Codable { case routine, urgent, stat }

@Model final class ImageItem {
    var data: Data
    var caption: String
    var addedAt: Date
    var analysisResult: String              // cached AI analysis text
}

struct ReportSection: Codable, Hashable, Identifiable {
    var id = UUID()
    var heading: String
    var text: String
    var isLocked: Bool = false              // signed sections become read-only
    var macroExpanded: Bool = false
}

@Model final class ReportTemplate {
    var name: String
    var modality: String
    var headings: [String]
    var macros: [VoiceMacro]               // "no acute" → fills Impression
    var isBuiltIn: Bool
    var createdAt: Date
}

struct VoiceMacro: Codable, Hashable, Identifiable {
    var id = UUID()
    var trigger: String                     // spoken phrase e.g. "no acute"
    var expansion: String                   // text to insert
    var targetHeading: String               // which section to fill
}

@Model final class DictationSession {
    var startedAt: Date
    var endedAt: Date?
    var engineUsed: String                  // "MedASR" | "Apple"
    var rawTranscript: String
    var wordErrorRate: Float?               // if ground truth available
    var report: RadiologyReport?
}
```

**Why:** SwiftData relationships enable proper patient → report history, cascade deletes, and real queries. DictationSession provides an audit trail. VoiceMacro is the foundation of the template system.

---

### 1.2 Migration strategy

SwiftData `.automigrateSchema` handles adding new properties with defaults. The only breaking change is moving `imageData: Data?` → `imageItems: [ImageItem]`. Add a computed migration shim:

```swift
// In RadiologyReport: keeps old data readable post-migration
var legacyImageMigrated: Bool = false
```

Run a one-time migration on first launch in `RadiologySuiteApp.body`.

---

## Phase 2 — MedASR CoreML (the accuracy engine)

### 2.1 Model conversion

**File:** `conversion/convert_medasr.py` ✓ already fixed

Run:
```bash
cd conversion
pip install -r requirements.txt
python convert_medasr.py
xcrun coremlcompiler compile MedASR.mlpackage MedASR.mlmodelc
```

Add to Xcode:
- Drag `MedASR.mlmodelc` → `RadiologySuite/Resources/` (Copy items if needed ✓)
- Drag `medasr_vocab.json` → `RadiologySuite/Resources/` (Copy items ✓)

### 2.2 MedASREngine.swift ✓ already fixed

Real mel-spectrogram pipeline, greedy CTC decode, SentencePieceBridge vocab loading.

### 2.3 AudioCapture.swift ✓ already fixed

Linear resampler 44.1/48kHz → 16kHz.

### 2.4 RadLex vocabulary injection into Apple ASR

When MedASR model is not bundled, Apple ASR needs radiology terms injected as contextual strings. Add to `SpeechEngine.swift`:

```swift
// RadiologySuite/Resources/radlex_terms.json
// ~800 high-frequency radiology terms: ["consolidation","pneumothorax",
//  "cardiomegaly","atelectasis","pleural effusion", ...]
// Load into AppleStreamingEngine.contextualStrings at start

extension AppleStreamingEngine {
    static func loadRadLexTerms() -> [String] {
        guard let url = Bundle.main.url(forResource: "radlex_terms", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let terms = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Array(terms.prefix(100)) // SFSpeech accepts max 100
    }
}
```

**File to create:** `RadiologySuite/Resources/radlex_terms.json`
Include: anatomical terms, pathology terms, procedure terms, modifiers.

---

## Phase 3 — LLM service (real, no mocks)

### 3.1 Remove MockLLMService as a fallback

`MockLLMService` stays only as an empty-key safety net. The real service must work end-to-end.

### 3.2 Fix vision payload for GPT-4o

**File:** `RadiologySuite/Core/LLMService.swift`

Current `suggestDifferentials` sends imageData but never puts it in the HTTP payload. Fix:

```swift
func suggestDifferentials(reportText: String, imageData: Data?) async throws -> [String] {
    var content: [[String: Any]] = [
        ["type": "text", "text": reportText.isEmpty ? "Analyze the attached image." : reportText]
    ]
    if let imageData {
        let b64 = imageData.base64EncodedString()
        content.append([
            "type": "image_url",
            "image_url": ["url": "data:image/jpeg;base64,\(b64)", "detail": "high"]
        ])
    }
    let payload: [String: Any] = [
        "model": "gpt-4o",          // vision requires gpt-4o, not mini
        "messages": [
            ["role": "system", "content": radiologySystemPrompt],
            ["role": "user", "content": content]
        ],
        "temperature": 0.2,
        "max_tokens": 500
    ]
    // ... rest of request
}
```

### 3.3 Add streaming support for real-time polish

For the "Polish" button in section cards, use Server-Sent Events:

```swift
func polishStreaming(_ raw: String, section: String,
                     onChunk: @escaping (String) -> Void) async throws
```

Use `URLSession.bytes(for:)` and parse `data: {...}` SSE lines.

### 3.4 Add MedGemma integration option

Per Google's own recommendation: MedASR → text → MedGemma for clinical insights.
Add `MedGemmaService` using Google AI SDK (Vertex AI or Gemini API):

```swift
final class MedGemmaService: LLMService {
    // Uses https://generativelanguage.googleapis.com/v1beta/models/medgemma-27b-it
    // Falls back to gpt-4o if no Gemini key set
}
```

**Settings:** Let radiologist choose OpenAI or Google as backend.

### 3.5 Add AI transcript correction

After dictation ends, auto-run a polish pass on each section:

```swift
// In DictationViewModel.sendToReport:
// After saving, launch background Task to polish each section
// Update sections in-place; show subtle "AI-corrected" badge
```

---

## Phase 4 — Template builder (complete UI)

### 4.1 TemplateBuilderView

**File:** `RadiologySuite/Features/Templates/TemplateBuilderView.swift`

```
TemplateBuilderView
├── Header: template name field + modality picker
├── HeadingList: drag-to-reorder (List with .onMove)
│   └── Each row: heading name (editable) + delete button
├── AddHeadingButton: inline text field → append
├── MacroSection
│   └── VoiceMacroRow: trigger phrase → expansion → target heading
└── SaveButton: inserts/updates ReportTemplate in SwiftData
```

Trigger phrases are matched case-insensitively against the live transcript in `parseSections`. When a macro fires, insert the expansion at the right section and skip further parsing of that phrase.

### 4.2 Template picker in RecordSheet

Before starting dictation, show a template picker row (if templates exist):

```
[Template: Chest XR  ▾]   ← tap to pick from list
```

Selected template headings drive `parseSections()` instead of the hardcoded list.

### 4.3 Wire template → DictationViewModel

```swift
// DictationViewModel
var selectedTemplate: ReportTemplate?

private func parseSections(from raw: String) -> [ReportSection] {
    let headings = selectedTemplate?.headings ?? defaultHeadings
    // parse using headings from template, apply macros
}
```

---

## Phase 5 — Report builder (complete)

### 5.1 Per-section AI polish button

Each section card gets a small wand icon. Tapping it:
1. Calls `llm.polish(section.text, section: section.heading)` with streaming
2. Text animates in character by character via `onChunk`
3. Shows "AI-polished" badge on section header (small coral dot)

### 5.2 Section reorder + add/delete

- Long-press → drag handle appears → `.onMove` reorders
- "+" button between sections → insert new blank section
- Swipe-to-delete on section rows

### 5.3 Voice macro expansion in report

After dictation, scan the full transcript for registered macro triggers.
Replace matches before section parsing so they land in the right section automatically.

### 5.4 Signing workflow

```swift
// ReportBuilderView toolbar: "Sign Report" button
// Shows confirmation sheet: "Sign as Dr. [name] at [timestamp]?"
// On confirm: sets report.status = .signed, report.signedAt = Date()
// Signed sections become read-only (isLocked = true)
// Shows green "Signed" badge in report header
```

### 5.5 Amendment workflow

Signed reports can be amended:
- "Amend" button appears in toolbar for signed reports
- Creates a new section "Amendment" with current date/time header
- Sets status = .amended
- Original sections remain locked

### 5.6 Priority + urgency badge

```swift
// In headerCard: priority selector [Routine | Urgent | STAT]
// STAT reports get a red banner at top of ReportBuilderView
// ReportTile shows priority badge in grid
```

---

## Phase 6 — Patient management (complete)

### 6.1 PatientDetailView

**File:** `RadiologySuite/Features/Patients/PatientDetailView.swift`

```
PatientDetailView
├── Header card: avatar initials, name, MRN, DOB, sex, phone
├── Stats row: total reports | this year | last study date
├── Referring physician field
├── ReportHistory list (sorted by studyDate desc)
│   └── Each row: modality chip + title + date + status badge
└── Quick-dictate button (opens RecordSheet pre-linked to this patient)
```

### 6.2 Real MRN generation

If no MRN entered:
```swift
// Auto-generate: year + 6 random digits
let mrn = "\(Calendar.current.component(.year, from: Date()))-\(Int.random(in: 100000...999999))"
```

### 6.3 Age computed from DOB

```swift
// Remove `var age: Int`, replace with:
var dateOfBirth: Date?
var age: Int {
    guard let dob = dateOfBirth else { return 0 }
    return Calendar.current.dateComponents([.year], from: dob, to: .now).year ?? 0
}
```

### 6.4 Patient search

Add `@Query` with predicate filter in PatientListView:
```swift
@State private var searchText = ""
// filter: name CONTAINS searchText OR mrn CONTAINS searchText
```

Use `.searchable(text: $searchText)` modifier.

---

## Phase 7 — Imaging pipeline (complete)

### 7.1 Multi-image support

Replace `report.imageData: Data?` with `report.imageItems: [ImageItem]`.
`XrayAttachView` stores each image as a separate `ImageItem` with:
- JPEG at 80% quality
- Caption (editable)
- Analysis result (cached)

### 7.2 GPT-4o Vision — real payload

Fix `OpenAICompatibleService.suggestDifferentials` to include base64 image in the message content array (see Phase 3.2).

Auto-run analysis when images are added (not just on button tap):
```swift
.onChange(of: report.imageItems) {
    if !report.imageItems.isEmpty {
        Task { await runAnalysis() }
    }
}
```

### 7.3 Image viewer

Tapping a thumbnail opens a full-screen image viewer:
- Pinch to zoom
- Swipe between images
- Annotate caption inline

### 7.4 Attach analysis to specific section

Instead of always appending to "Findings", let the radiologist pick which section to inject into:

```swift
// Analysis card bottom: "Inject into: [Findings ▾]" picker
// Then: "Attach to report"
```

---

## Phase 8 — iPad layout (NavigationSplitView)

### 8.1 Adaptive root layout

**File:** `RadiologySuite/App/RadiologyApp.swift`

```swift
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            iPadLayout()
        } else {
            iPhoneLayout()  // existing Dock-based layout
        }
    }
}

struct iPadLayout: View {
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Sidebar: patients list with search
            PatientListView()
        } content: {
            // Middle: reports for selected patient (or all reports)
            ReportsBoard(openReport: $finishedReport)
        } detail: {
            // Detail: ReportBuilderView or welcome card
            ReportDetailPlaceholder()
        }
        .navigationSplitViewStyle(.balanced)
    }
}
```

### 8.2 Keyboard shortcuts (iPadOS)

```swift
.keyboardShortcut("n", modifiers: .command)   // New dictation
.keyboardShortcut("s", modifiers: .command)   // Save report
.keyboardShortcut("e", modifiers: [.command, .shift])  // Export PDF
```

### 8.3 Drag-and-drop

On iPad, drag an image from Photos into XrayAttachView:
```swift
.dropDestination(for: Data.self) { items, _ in
    // load dropped image data into imageItems
}
```

---

## Phase 9 — Export engine (complete)

### 9.1 Branded PDF renderer

**File:** `RadiologySuite/Features/Report/ReportRenderer.swift` — upgrade:

```
PDF Layout:
┌─────────────────────────────────────────┐
│  [HOSPITAL LOGO]   RADIOLOGY REPORT     │
│  Hospital: [from Settings]              │
│  ─────────────────────────────────────  │
│  Patient: Name · MRN · DOB · Sex · Age  │
│  Accession: [auto] · Study Date: [date] │
│  Modality: [XR/CT/MR/US] · Priority: ─  │
│  Referring: [physician name]            │
│  ─────────────────────────────────────  │
│  CLINICAL HISTORY                       │
│  [text]                                 │
│  TECHNIQUE                              │
│  [text]                                 │
│  FINDINGS                               │
│  [text]                                 │
│  IMPRESSION                             │
│  [text]                                 │
│  ─────────────────────────────────────  │
│  Electronically signed: Dr. [name]      │
│  [timestamp]         [QR code? future]  │
└─────────────────────────────────────────┘
```

Pull hospital name and radiologist name from Settings (`@AppStorage`).

### 9.2 Print via AirPrint

```swift
Button("Print") {
    let printInfo = UIPrintInfo(dictionary: nil)
    printInfo.jobName = report.title
    printInfo.outputType = .general
    let controller = UIPrintInteractionController.shared
    controller.printInfo = printInfo
    controller.printingItem = ReportRenderer.pdf(for: report)
    controller.present(animated: true)
}
```

### 9.3 Share as plain text

Add plain-text export alongside PDF:
```swift
Button("Copy text") {
    UIPasteboard.general.string = report.plainText
}
```

### 9.4 HL7 / structured export (foundation)

Add a `ReportExporter.hl7(for report:)` that produces a minimal HL7 ORU^R01 message.
This isn't hospital integration, but gives a structured export some EMR systems accept.

---

## Phase 10 — AI insights (real, complete)

### 10.1 Report summary (streaming)

Use SSE streaming so the summary types in live instead of appearing all at once.

### 10.2 Differential suggestions with confidence

Return structured JSON from LLM:
```json
[
  {"finding": "Pneumonia", "confidence": "high", "basis": "right lower lobe consolidation"},
  {"finding": "Lung malignancy", "confidence": "low", "basis": "requires follow-up CT"}
]
```

Show confidence as colored dots: green/yellow/red.

### 10.3 X-ray findings with anatomy labeling

When an image is attached:
- GPT-4o Vision analyzes the image
- Returns findings mapped to anatomical regions
- XrayAttachView shows a findings list with region tags: `[Left lung] [Pleural space]`

### 10.4 Critical findings alert

If AI detects critical terms (pneumothorax, aortic dissection, intracranial hemorrhage):
- Show a red banner: "⚠ Critical finding detected — verify immediately"
- This is decision support, not a diagnosis — include disclaimer

### 10.5 Patient questionnaire (real use)

Improve `generateQuestionnaire` to produce questions that actually make sense for the modality:
- XR chest → respiratory symptoms
- MR knee → pain, instability, activity level
- CT head → headache, focal neuro symptoms

Generate a shareable questionnaire link (URL scheme: `radiology://questionnaire/[id]`) that opens the app and shows the questions.

---

## Phase 11 — Onboarding (first launch)

### 11.1 OnboardingView

**File:** `RadiologySuite/Features/Onboarding/OnboardingView.swift`

3-step sheet on first launch:
```
Step 1: "Welcome to RadiologySuite"
        Radiologist name field
        Hospital / practice name field

Step 2: "Connect AI"
        OpenAI API key field (with secure entry)
        OR Google Gemini API key
        Test button → calls API, shows green checkmark

Step 3: "Your dictation engine"
        Shows MedASR status: bundled or not
        If not bundled: shows instructions for conversion
        If bundled: shows "Ready — 6.6% WER on radiology"
        Apple fallback: always available
```

```swift
// App checks on launch:
@AppStorage("onboarding.complete") var onboardingComplete = false
// Show OnboardingView as .fullScreenCover if !onboardingComplete
```

---

## Phase 12 — Settings (complete, real)

### 12.1 Rebuild SettingsView

```
IDENTITY
  Radiologist name     [text field]
  Credentials          [e.g. "MD, FRCR"]
  Hospital name        [text field]
  Department           [text field]

AI ENGINE
  Provider             [OpenAI | Google Gemini]
  API key              [secure field — stored in Keychain, not UserDefaults]
  Model                [gpt-4o | gpt-4o-mini | gemini-2.5-pro]
  Test connection      [button → async ping]

ON-DEVICE SPEECH
  MedASR status        [Not bundled | Ready]
  Bundle instructions  [expandable if not bundled]
  Apple ASR fallback   [always on]

REPORT DEFAULTS
  Default modality     [XR | CT | MR | US]
  Auto-sign after      [toggle + minutes picker]
  PDF header logo      [photo picker for hospital logo]

EXPORT
  Default format       [PDF | Plain text | Both]
  Include AI insights  [toggle]
  Include disclaimer   [toggle — on by default]

PRIVACY
  Audit trail          [DictationSession history on/off]
  Data stays on device [informational, always true for MedASR]
```

### 12.2 Keychain for API key

Replace `@AppStorage("llm.apiKey")` with a Keychain wrapper:

```swift
enum Keychain {
    static func save(key: String, value: String) { ... }
    static func load(key: String) -> String? { ... }
    static func delete(key: String) { ... }
}
// Use SecItemAdd / SecItemCopyMatching / SecItemDelete
```

Never store API keys in UserDefaults — they're unencrypted.

---

## Phase 13 — UI polish and accessibility

### 13.1 Remaining design system components needed

- `StatusBadge` — draft (gray) | signed (green) | amended (amber) | stat (red)
- `PriorityBanner` — full-width red/amber bar for STAT/urgent reports
- `ConfidenceDot` — green/yellow/red for AI differential confidence
- `StreamingText` — animates LLM output character by character
- `SignatureCard` — shows signed-by name, timestamp, green checkmark

### 13.2 Haptics

```swift
// Recording start: UIImpactFeedbackGenerator(.medium).impactOccurred()
// Section saved: UIImpactFeedbackGenerator(.light).impactOccurred()
// Signing: UINotificationFeedbackGenerator().notificationOccurred(.success)
// Critical finding: UINotificationFeedbackGenerator().notificationOccurred(.warning)
```

### 13.3 Accessibility

- All tappable elements: `.accessibilityLabel`, `.accessibilityHint`
- `Waveform` view: `.accessibilityLabel("Recording in progress, tap to pause")`
- Section cards: VoiceOver reads heading + content
- Dynamic Type: use `.font(DS.bodyFont)` everywhere (already relative)
- Minimum tap target: 44×44pt (already enforced by CircleButton/Chip)

### 13.4 Dark mode

Currently `Screen` modifier forces `.preferredColorScheme(.light)`.
Add a Settings toggle for Auto / Light / Dark.
Add dark-mode color variants to `DS`:
```swift
static let paperDark = Color(hex: 0x1C1A16)
static let cardDark  = Color(hex: 0x242018)
static let inkDark   = Color(hex: 0xF2EFE9)
```

---

## Phase 14 — Performance and reliability

### 14.1 Background audio session

Handle interruptions (phone call, Siri):
```swift
NotificationCenter.default.addObserver(
    forName: AVAudioSession.interruptionNotification, ...
) { notification in
    // pause recording, show resume prompt
}
```

### 14.2 MedASR inference on background thread

Already done in `MedASREngine.inferenceQueue`. Verify it never blocks main thread.
Add a `@MainActor` check in DictationViewModel to confirm UI updates come from main.

### 14.3 Large report handling

If a report has >10 000 characters, chunk the AI summarize call:
```swift
// Split into 4000-token chunks, summarize each, then summarize the summaries
```

### 14.4 Error recovery

- If LLM call fails: show inline error with "Retry" button (not just a toast)
- If MedASR inference throws: fall back to Apple ASR, show silent badge change
- If audio session fails: show clear error modal with exact reason

### 14.5 SwiftData performance

Add `@Query` predicates instead of filtering arrays in view layer.
Add indices on frequently queried fields:
```swift
// Store.swift: add @Attribute(.unique) to mrn
// Add @Attribute to studyDate for sort performance
```

---

## Phase 15 — Widget + Shortcuts (bonus, post-MVP)

### 15.1 Lock screen widget

Show today's report count and last activity time.
`WidgetKit` with `TimelineEntry` updated on each new report.

### 15.2 Siri shortcut

"Hey Siri, start a new radiology dictation"
→ opens app directly to RecordSheet via `onOpenURL { url in ... }` (already wired).

### 15.3 Spotlight indexing

Index patient names and report titles via `CoreSpotlight`:
```swift
CSSearchableItem(uniqueIdentifier: report.id.uuidString,
                 domainIdentifier: "com.radstudio.reports",
                 attributeSet: attrs)
```

---

## Build order (recommended sequence)

```
Week 1  │ Phase 1 (data model) → Phase 12.2 (Keychain) → Phase 11 (onboarding)
Week 2  │ Phase 2 (MedASR bundle) → Phase 3 (LLM real) → Phase 13.1 design tokens
Week 3  │ Phase 4 (template builder) → Phase 5 (report builder complete)
Week 4  │ Phase 6 (patient detail) → Phase 7 (imaging pipeline)
Week 5  │ Phase 8 (iPad layout) → Phase 9 (export complete)
Week 6  │ Phase 10 (AI insights real) → Phase 13 (polish + accessibility)
Week 7  │ Phase 14 (reliability) → Phase 15 (widgets, optional)
        │ → TestFlight beta
```

---

## Files to create (net new, not yet in codebase)

```
RadiologySuite/
├── Features/
│   ├── Onboarding/
│   │   └── OnboardingView.swift
│   ├── Templates/
│   │   └── TemplateBuilderView.swift
│   ├── Patients/
│   │   └── PatientDetailView.swift
│   └── Report/
│       └── ReportSignatureView.swift
├── Core/
│   ├── KeychainService.swift
│   ├── MedGemmaService.swift
│   └── ExportService.swift          (HL7, AirPrint, copy-text)
└── Resources/
    └── radlex_terms.json            (~800 radiology terms for Apple ASR context)
```

## Files to significantly modify

```
RadiologySuite/Models/Store.swift              ← full rebuild (Phase 1)
RadiologySuite/Core/LLMService.swift           ← vision payload, streaming, Gemini (Phase 3)
RadiologySuite/Core/MedASREngine.swift         ✓ done
RadiologySuite/Core/AudioCapture.swift         ✓ done
RadiologySuite/Core/SpeechEngine.swift         ← RadLex injection (Phase 2.4)
RadiologySuite/Features/Dictation/DictationViewModel.swift  ← template wiring (Phase 4)
RadiologySuite/Features/Report/ReportBuilderView.swift      ← polish, sign, amend (Phase 5)
RadiologySuite/Features/Report/ReportRenderer.swift         ← branded PDF (Phase 9)
RadiologySuite/Features/Report/SettingsView.swift           ← complete rebuild (Phase 12)
RadiologySuite/Features/Imaging/XrayAttachView.swift        ← multi-image, real vision (Phase 7)
RadiologySuite/Features/Patients/PatientListView.swift      ← search, detail nav (Phase 6)
RadiologySuite/App/RadiologyApp.swift                       ← iPad split, onboarding (Phase 8)
```

---

## What "no mock data" means concretely

| Was mock | Real replacement |
|---|---|
| `MockLLMService` | Only used if API key is blank — onboarding forces key entry |
| `DemoSeeder` | Kept for dev/screenshot builds only; removed from production target |
| Hardcoded template headings | Driven by `ReportTemplate` from SwiftData |
| `patientName: String` on report | `patient: Patient?` relationship — real SwiftData object |
| `imageData: Data?` single image | `imageItems: [ImageItem]` array |
| Static MedASR status badge | Live `MedASREngine.isLoaded` + `MedASREngine.lastError` |
| Mock differentials in `MockLLMService` | Blocked behind real API key — no key = prompt to add one |
