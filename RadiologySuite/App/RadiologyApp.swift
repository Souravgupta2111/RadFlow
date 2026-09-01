import SwiftUI
import SwiftData

@main
struct RadiologySuiteApp: App {
    @AppStorage("onboarding.complete") var onboardingComplete = false
    @AppStorage("ui.themeMode") private var themeMode = 0 // 0=System, 1=Light, 2=Dark
    @AppStorage("disclaimer.accepted") private var disclaimerAccepted = false

    /// SwiftData's default store lives in Application Support. On a fresh
    /// install that folder does not exist yet; creating it *before* the
    /// container is built avoids the NSCocoaErrorDomain 512 / sandbox
    /// "file-write-create denied" storm.
    static func ensureApplicationSupport() {
        let fm = FileManager.default
        if let url = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Wipe the SwiftData store (main file plus SQLite WAL / SHM sidecar files)
    /// so a schema mismatch during development never leaves the app stuck in a
    /// broken, empty state.
    static func wipeStore() {
        let fm = FileManager.default
        let url = URL.applicationSupportDirectory.appending(path: "default.store")
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }

    static let sharedContainer: ModelContainer = {
        ensureApplicationSupport()
        let schema = Schema([Patient.self, RadiologyReport.self, ReportTemplate.self, DictationSession.self, ImageItem.self, ClinicProfile.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to load ModelContainer: \(error). Wiping database for fresh start...")
            wipeStore()

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    init() {
        Self.ensureApplicationSupport()
        MedASREngine.shared.preload()
        // Ensure MedASR and audit trail are always on
        if UserDefaults.standard.object(forKey: "dictation.useMedASR") == nil {
            UserDefaults.standard.set(true, forKey: "dictation.useMedASR")
        }
        if UserDefaults.standard.object(forKey: "privacy.auditTrail") == nil {
            UserDefaults.standard.set(true, forKey: "privacy.auditTrail")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !onboardingComplete {
                    OnboardingView()
                } else {
                    RootView()
                }
            }
            .modelContainer(Self.sharedContainer)
            .tint(DS.coral)
            .preferredColorScheme(themeMode == 0 ? nil : (themeMode == 1 ? .light : .dark))
        }
    }
}

/// Tracks whether a report editor is currently on-screen so the root tab bar
/// (Dock) can hide itself instead of overlapping the report's own action bar.
@MainActor
final class ReportOpenState: ObservableObject {
    static let shared = ReportOpenState()
    @Published var isReportOpen = false
}

struct RootView: View {
    enum Tab: String, CaseIterable { case home, patients, wirelessRemote }

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var reportOpen = ReportOpenState.shared
    @State private var tab: Tab = .home
    @State private var showRecorder = false
    @State private var finishedReport: RadiologyReport?
    @State private var boardSelectedReport: RadiologyReport?

    var body: some View {
        content
            .safeAreaInset(edge: .bottom) {
                if !reportOpen.isReportOpen {
                    Dock(selection: $tab, onPlus: { showRecorder = true })
                }
            }
        .fullScreenCover(isPresented: $showRecorder) {
            NavigationStack {
                RecordSheet(
                    onDone: { report in
                        finishedReport = report
                    },
                    onCancel: {
                        showRecorder = false
                    }
                )
                .navigationDestination(item: $finishedReport) { report in
                    ReportBuilderView(report: report)
                        .navigationBarBackButtonHidden(true)
                        .interactiveDismissDisabled(true)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Cancel") {
                                    modelContext.delete(report)
                                    try? modelContext.save()
                                    showRecorder = false
                                }
                                .foregroundStyle(.red)
                            }
                        }
                }
            }
            .modelContext(modelContext)
        }
        .onOpenURL { url in
            switch url.host {
            case "record": showRecorder = true
            case "demo": DemoSeeder.seed(context: modelContext)
            default: break
            }
        }
        .onChange(of: showRecorder) { newValue in
            if !newValue { finishedReport = nil }
        }
        .onAppear {
            TemplateSeeder.seedIfNeeded(context: modelContext)
            ClinicProfileSeeder.seedIfNeeded(context: modelContext)
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--demo") { DemoSeeder.seed(context: modelContext) }
            if args.contains("--record") { showRecorder = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .home: NavigationStack { HomeView(onRecord: { showRecorder = true }) }
        case .patients: NavigationStack { PatientListView() }
        case .wirelessRemote: NavigationStack { WirelessRemoteView() }
        }
    }
}

@MainActor
enum DemoSeeder {
    static func seed(context ctx: ModelContext) {
        guard (try? ctx.fetchCount(FetchDescriptor<Patient>())) == 0 else { return }

        let people = [
            Patient(name: "Ramesh Iyer", mrn: "RN2481", sex: "M"),
            Patient(name: "Sara Khan", mrn: "SK1093", sex: "F")
        ]
        people.forEach { ctx.insert($0) }

        let r1 = RadiologyReport(title: "XR Study · Aug 21", modality: "XR")
        r1.patient = people[0]
        r1.sections = [
            ReportSection(heading: "Clinical History", text: "Cough and fever for ten days."),
            ReportSection(heading: "Findings", text: "Heart size is normal. Bilateral hilar prominence noted. No focal consolidation. Costophrenic angles are sharp."),
            ReportSection(heading: "Impression", text: "No acute cardiopulmonary process.")
        ]
        let r2 = RadiologyReport(title: "CT Study · Aug 20", modality: "CT")
        r2.patient = people[1]
        r2.sections = [
            ReportSection(heading: "Indication", text: "Headache, rule out sinusitis."),
            ReportSection(heading: "Findings", text: "Mucosal thickening in maxillary sinuses. No mass effect. Ventricles are normal."),
            ReportSection(heading: "Impression", text: "Mild paranasal sinus disease.")
        ]
        let r3 = RadiologyReport(title: "US Study · Aug 19", modality: "US")
        r3.patient = people[0]
        r3.sections = [
            ReportSection(heading: "Findings", text: "Liver is normal in size and echotexture. No calculi in gall bladder."),
            ReportSection(heading: "Impression", text: "Normal abdominal sonography.")
        ]
        [r1, r2, r3].forEach { ctx.insert($0) }
        try? ctx.save()
    }
}

struct Dock: View {
    @Binding var selection: RootView.Tab
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            tabBar
            micCircle
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var micCircle: some View {
        Button(action: onPlus) {
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(Circle().fill(DS.coralGradient()))
                .shadow(color: DS.coral.opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            dockPill(.home, icon: selection == .home ? "house.fill" : "house", label: "Home")
            dockPill(.patients, icon: selection == .patients ? "person.2.fill" : "person.2", label: "Patients")
            dockPill(.wirelessRemote, icon: "iphone.radiowaves.left.and.right", label: "Remote")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: 62)
        .background(Capsule().fill(DS.cardAdaptive).shadow(color: .black.opacity(0.08), radius: 24, y: 12))
    }

    private func dockPill(_ tab: RootView.Tab, icon: String, label: String) -> some View {
        Button {
            DS.haptic(.light)
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundStyle(selection == tab ? DS.coral : DS.inkAdaptive)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                Capsule().fill(selection == tab ? DS.coral.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

@MainActor
enum ClinicProfileSeeder {
    static func seedIfNeeded(context ctx: ModelContext) {
        let count = (try? ctx.fetchCount(FetchDescriptor<ClinicProfile>())) ?? 0
        guard count == 0 else { return }
        ctx.insert(ClinicProfile())
        try? ctx.save()
    }
}


@MainActor
enum TemplateSeeder {
    /// Seeds the built-in templates from the shared `TemplatePresets` catalog.
    /// Idempotent: inserts only presets whose name is not already in the store,
    /// so app updates can ship new presets without duplicating existing ones.
    static func seedIfNeeded(context ctx: ModelContext) {
        let existingNames = (try? ctx.fetch(FetchDescriptor<ReportTemplate>()))?.map(\.name) ?? []
        var inserted = false

        for preset in TemplatePresets.all where !existingNames.contains(preset.name) {
            let template = ReportTemplate(
                name: preset.name,
                modality: preset.modality,
                headings: preset.blocks.map(\.title),
                macros: preset.macros,
                isBuiltIn: true,
                layoutType: preset.layoutType,
                accentColorHex: preset.accentColorHex,
                backgroundColorHex: preset.backgroundColorHex,
                cardTintHex: preset.cardTintHex,
                borderColorHex: preset.borderColorHex,
                fontFamily: preset.fontFamily,
                borderWidth: preset.borderWidth,
                cornerRadius: preset.cornerRadius,
                headerTitle: preset.headerTitle,
                subtitle: preset.subtitle,
                blocks: preset.blocks
            )
            ctx.insert(template)
            inserted = true
        }

        guard inserted else { return }
        try? ctx.save()
        UserDefaults.standard.set(true, forKey: "templates.seeded.v3")
    }
}
