import SwiftUI
import SwiftData

struct HomeView: View {
    var onRecord: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \RadiologyReport.createdAt, order: .reverse) private var reports: [RadiologyReport]
    @Query private var patients: [Patient]
    @State private var openReport: RadiologyReport?
    @State private var showSettings = false
    @State private var showReports = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statRow
                sectionLabel("Clinic setup")
                setupRow
                sectionLabel("Recent studies")
                recentGrid
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 140)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DS.paperAdaptive.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openReport) { report in
            ReportBuilderView(report: report)
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .navigationDestination(isPresented: $showReports) {
            ReportsBoard(openReport: $openReport, onBack: { showReports = false })
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            Text("Overview")
                .font(DS.display(44))
                .tracking(-1.6)
                .foregroundStyle(DS.inkAdaptive)
            Spacer()
            CircleButton(systemName: "ellipsis") {
                showSettings = true
            }
        }
    }

    private var statRow: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            CoralTile(height: 150) {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: onRecord) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.white.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Dictate")
                        .font(.system(size: 27, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                    Text("Start a new study")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Button {
                showReports = true
            } label: {
                Tile(height: 150) {
                    VStack(alignment: .leading, spacing: 0) {
                        CornerTag("Reports")
                        Spacer()
                        bigNumber(reports.count)
                        caption("all time")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .buttonStyle(.plain)

            NavigationLink(destination: PatientListView()) {
                Tile(height: 118) {
                    VStack(alignment: .leading, spacing: 0) {
                        CornerTag("Patients")
                        Spacer()
                        bigNumber(patients.count, size: 40)
                        caption("registered")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .buttonStyle(.plain)

            Tile(height: 118) {
                VStack(alignment: .leading, spacing: 0) {
                    CornerTag("This week")
                    Spacer()
                    bigNumber(weekCount, size: 40)
                    caption("studies dictated")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var setupRow: some View {
        VStack(spacing: 12) {
            NavigationLink(destination: TemplatesListView()) {
                setupTile(icon: "rectangle.split.2x1", title: "Templates", subtitle: "Print & PDF layouts")
            }
            .buttonStyle(.plain)

            NavigationLink(destination: ClinicBrandingSettingsView()) {
                setupTile(icon: "paintpalette.fill", title: "Letterhead", subtitle: "Name, logo & signature")
            }
            .buttonStyle(.plain)
        }
    }

    private func setupTile(icon: String, title: String, subtitle: String) -> some View {
        Tile(height: 92) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.coral)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(DS.coral.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.inkAdaptive)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.subAdaptive)
                }
                Spacer()
                ArrowBadge()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bigNumber(_ n: Int, size: CGFloat = 56) -> some View {
        Text("\(n)")
            .font(.system(size: size, weight: .light))
            .monospacedDigit()
            .foregroundStyle(DS.inkAdaptive)
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(DS.subAdaptive)
    }

    private var weekCount: Int {
        let week = Date.now.addingTimeInterval(-7 * 86400)
        return reports.filter { $0.createdAt > week }.count
    }

    @ViewBuilder
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.subAdaptive)
            .textCase(nil)
            .padding(.top, 4)
    }

    @ViewBuilder
    private var recentGrid: some View {
        if reports.isEmpty {
            Tile(height: 170) {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 34))
                        .foregroundStyle(DS.subAdaptive)
                    Text("No studies yet")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Tap Dictate to create your first report.")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.subAdaptive)
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            }
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(reports.prefix(4))) { report in
                    Button { openReport = report } label: {
                        ReportTile(report: report)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ReportTile: View {
    let report: RadiologyReport

    var body: some View {
        Tile(height: 172) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    CornerTag((report.patientName?.isEmpty ?? true) ? (report.patient?.name ?? "Unlinked") : (report.patientName ?? "Unlinked"))
                    Spacer()
                    if report.status == .draft {
                        Text("DRAFT")
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.orange))
                    }
                    ArrowBadge()
                }
                Spacer()
                Text(report.title)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(DS.inkAdaptive)
                    .lineLimit(3)
                    .minimumScaleFactor(0.65)
                Text("\(report.modality) · \(report.updatedAt.formatted(.dateTime.day().month()))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.subAdaptive)
                    .padding(.top, 6)
            }
        }
    }
}
