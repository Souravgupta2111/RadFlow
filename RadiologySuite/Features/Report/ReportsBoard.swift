import SwiftUI
import SwiftData

/// Reports tab — every report grouped patient-wise, with an optional modality
/// filter. Tap any study to open it in the report builder.
struct ReportsBoard: View {
    @Binding var openReport: RadiologyReport?
    var onBack: () -> Void

    @Query(sort: \RadiologyReport.createdAt, order: .reverse) private var reports: [RadiologyReport]
    @State private var filter = "All"

    private var filters: [String] { ["All"] + ImagingModality.allCases.map(\.rawValue) }

    private var filtered: [RadiologyReport] {
        filter == "All" ? reports : reports.filter { $0.modality == filter }
    }

    /// Reports grouped by patient, newest group first. Reports with no linked
    /// patient fall into the "Unlinked" group at the end.
    private var groups: [(name: String, detail: String, reports: [RadiologyReport])] {
        let relevant = filtered
        var byPatient: [String: [RadiologyReport]] = [:]

        for report in relevant {
            let name = report.patient?.name ?? report.patientName ?? ""
            let key = name.isEmpty ? "Unlinked" : name
            byPatient[key, default: []].append(report)
        }

        return byPatient
            .map { key, value -> (name: String, detail: String, reports: [RadiologyReport]) in
                let patient = value.first?.patient
                let detail: String
                if let patient {
                    detail = "MRN \(patient.mrn)"
                } else {
                    detail = key == "Unlinked" ? "No patient linked" : "Legacy entry"
                }
                return (key, detail, value)
            }
            .sorted {
                ($0.reports.first?.createdAt ?? .distantPast) > ($1.reports.first?.createdAt ?? .distantPast)
            }
    }

    private func count(_ f: String) -> Int {
        f == "All" ? reports.count : reports.filter { $0.modality == f }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                chipRow

                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups, id: \.name) { group in
                        patientSection(group)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 130)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openReport) { report in
            ReportBuilderView(report: report)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(DS.subAdaptive)
                    .padding(.trailing, 4)
            }
            Text("Reports")
                .font(DS.display(44))
                .tracking(-1.6)
                .foregroundStyle(DS.inkAdaptive)
            Spacer()
            Text("\(reports.count)")
                .font(.system(size: 44, weight: .light))
                .monospacedDigit()
                .foregroundStyle(DS.subAdaptive)
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(filters, id: \.self) { f in
                    Chip(label: f,
                         count: count(f),
                         selected: filter == f) {
                        withAnimation(.snappy) { filter = f }
                    }
                }
            }
        }
    }

    // MARK: - Patient Section

    private func patientSection(_ group: (name: String, detail: String, reports: [RadiologyReport])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(initials(for: group.name))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(DS.coralGradient()))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DS.inkAdaptive)
                        .lineLimit(1)
                    Text("\(group.detail) · \(group.reports.count) \(group.reports.count == 1 ? "study" : "studies")")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.subAdaptive)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(group.reports) { report in
                    Button { openReport = report } label: {
                        ReportTile(report: report)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func initials(for name: String) -> String {
        String(name.split(separator: " ").compactMap(\.first).prefix(2)).uppercased()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Tile(height: 180) {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 34))
                    .foregroundStyle(DS.subAdaptive)
                Text("Nothing here")
                    .font(.system(size: 17, weight: .semibold))
                Text("Dictate a study and it lands on this board.")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.subAdaptive)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
        }
    }
}
