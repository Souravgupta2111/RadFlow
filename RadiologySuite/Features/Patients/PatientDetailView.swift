import SwiftUI
import SwiftData

struct PatientDetailView: View {
    @Environment(\.modelContext) private var context
    let patient: Patient
    
    @Query private var reports: [RadiologyReport]
    @ObservedObject private var audioBriefing = AudioDoctorBriefingService.shared
    
    @State private var showNewDictation = false
    
    init(patient: Patient) {
        self.patient = patient
        let patientId = patient.persistentModelID
        self._reports = Query(filter: #Predicate<RadiologyReport> { report in
            report.patient?.persistentModelID == patientId
        }, sort: \RadiologyReport.studyDate, order: .reverse)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Card with Demographics & ARR
                Tile {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 16) {
                            Text(String(patient.name.split(separator: " ").compactMap(\.first).prefix(2)).uppercased())
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(DS.coralGradient()))
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(patient.name)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(DS.inkAdaptive)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("MRN: \(patient.mrn)")
                                    Text("ARR: \(patient.arrNumber)")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.coral)
                                
                                HStack(spacing: 12) {
                                    if patient.age > 0 {
                                        Label("\(patient.age) yrs", systemImage: "person.text.rectangle")
                                    }
                                    if patient.sex != "Unknown" {
                                        Label(patient.sex, systemImage: "figure.stand")
                                    }
                                    if !patient.phone.isEmpty {
                                        Label(patient.phone, systemImage: "phone.fill")
                                    }
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(DS.subAdaptive)
                            }
                            Spacer()
                        }

                        // Clinical Alerts Banner
                        if !patient.allergiesAlert.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text("Alert: \(patient.allergiesAlert)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.red)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
                        }
                    }
                }

                // Doctor's Voice Audio Briefing Player Card ("Heard by Voice")
                Tile {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Doctor Audio Briefing", systemImage: "headphones")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(DS.inkAdaptive)
                            Spacer()
                            Text("Voice AI")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DS.coral.opacity(0.15)))
                                .foregroundStyle(DS.coral)
                        }

                        Text("Listen to synthesized clinical history, past visit comparisons, and active impression.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DS.subAdaptive)

                        HStack(spacing: 12) {
                            Button {
                                if audioBriefing.isSpeaking && !audioBriefing.isPaused {
                                    audioBriefing.pause()
                                } else if audioBriefing.isPaused {
                                    audioBriefing.resume()
                                } else {
                                    audioBriefing.speakBriefing(for: patient, latestReport: reports.first)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: audioBriefing.isSpeaking && !audioBriefing.isPaused ? "pause.fill" : "play.fill")
                                    Text(audioBriefing.isSpeaking && !audioBriefing.isPaused ? "Pause Briefing" : "Play Doctor Briefing")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(DS.coral))
                            }

                            if audioBriefing.isSpeaking || audioBriefing.isPaused {
                                Button {
                                    audioBriefing.stop()
                                } label: {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(DS.subAdaptive)
                                }
                            }

                            Spacer()

                            if audioBriefing.isSpeaking {
                                HStack(spacing: 2) {
                                    ForEach(0..<4, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(DS.coral)
                                            .frame(width: 3, height: 12)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Stats Row
                HStack(spacing: 12) {
                    StatBox(title: "Total Visits", value: "\(reports.count)")
                    StatBox(title: "This Year", value: "\(reports.filter { Calendar.current.isDate($0.studyDate, equalTo: Date(), toGranularity: .year) }.count)")
                    StatBox(title: "Last Study", value: reports.first?.studyDate.formatted(.dateTime.month().day().year()) ?? "N/A")
                }
                
                // Longitudinal Progress Timeline & Trial Records
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Longitudinal Encounter Trail")
                                .font(.system(size: 18, weight: .bold))
                            Text("Full visit history, past diagnoses & progression")
                                .font(.system(size: 11))
                                .foregroundStyle(DS.subAdaptive)
                        }
                        Spacer()
                        Button {
                            showNewDictation = true
                        } label: {
                            Label("New Dictation", systemImage: "mic.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DS.coral)
                        }
                    }
                    .padding(.top, 6)
                    
                    if reports.isEmpty {
                        Tile(height: 100) {
                            Text("No scan history for this patient.")
                                .foregroundStyle(DS.subAdaptive)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    } else {
                        ForEach(reports) { report in
                            NavigationLink(destination: ReportBuilderView(report: report)) {
                                Tile {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(spacing: 10) {
                                            Chip(label: report.modality, selected: true) {}
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(report.title)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(DS.inkAdaptive)
                                                Text(report.studyDate.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(DS.subAdaptive)
                                            }
                                            
                                            Spacer()
                                            
                                            StatusBadge(status: report.status)
                                        }
                                        
                                        // Impression snippet
                                        if let imp = report.sections.first(where: { $0.heading.lowercased() == "impression" })?.text, !imp.isEmpty {
                                            Text("Impression: \(imp)")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(DS.inkAdaptive)
                                                .lineLimit(2)
                                                .padding(6)
                                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.04)))
                                        }

                                        // Patient Advice snippet if present
                                        if let advice = report.patientAdviceSummary, !advice.isEmpty {
                                            HStack(spacing: 4) {
                                                Image(systemName: "person.crop.circle.badge.checkmark")
                                                    .foregroundStyle(.blue)
                                                    .font(.system(size: 10))
                                                Text("Patient Plan: \(advice)")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.blue)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    context.delete(report)
                                    try? context.save()
                                } label: {
                                    Label("Delete Report", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 100)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .navigationTitle("Patient Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewDictation = true
                } label: {
                    Label("Quick Dictate", systemImage: "mic.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .fullScreenCover(isPresented: $showNewDictation) {
            RecordSheet(preselectedPatient: patient) { _ in
                showNewDictation = false
            } onCancel: {
                showNewDictation = false
            }
            .modelContext(context)
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.subAdaptive)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DS.inkAdaptive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(DS.cardAdaptive))
    }
}

struct StatusBadge: View {
    let status: ReportStatus
    
    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
    
    var color: Color {
        switch status {
        case .draft: return DS.subAdaptive
        case .signed: return .green
        case .amended: return .orange
        }
    }
}
