import SwiftUI
import SwiftData

struct PatientListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Patient.createdAt, order: .reverse) private var patients: [Patient]
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newMRN = ""
    @State private var newAge = ""
    @State private var newDOB: Date? = nil
    @State private var newSex = "M"
    @State private var searchText = ""

    @State private var newARR = ""
    @State private var newPhone = ""
    @State private var newReferring = ""
    @State private var newAllergies = ""

    var filteredPatients: [Patient] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            return patients
        } else {
            return patients.filter { p in
                p.name.localizedCaseInsensitiveContains(q) ||
                p.mrn.localizedCaseInsensitiveContains(q) ||
                p.arrNumber.localizedCaseInsensitiveContains(q) ||
                p.phone.localizedCaseInsensitiveContains(q) ||
                p.createdAt.formatted().localizedCaseInsensitiveContains(q) ||
                p.reports.contains(where: {
                    $0.accessionNumber.localizedCaseInsensitiveContains(q) ||
                    $0.title.localizedCaseInsensitiveContains(q) ||
                    $0.studyDate.formatted().localizedCaseInsensitiveContains(q)
                })
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Patients")
                            .font(DS.display(40))
                            .tracking(-1.6)
                            .foregroundStyle(DS.inkAdaptive)
                        Spacer()
                        CircleButton(systemName: "plus") { showAdd = true }
                    }
                    Text("Search by Phone, MRN, Name or Date")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.subAdaptive)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(DS.subAdaptive)
                        .font(.system(size: 16, weight: .semibold))
                    TextField("Search Phone, MRN, Name, or Date…", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.inkAdaptive)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DS.subAdaptive)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(DS.card)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )
                
                if filteredPatients.isEmpty {
                    Tile(height: 170) {
                        VStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 34))
                                .foregroundStyle(DS.subAdaptive)
                            Text("No matching patients found").font(.system(size: 16, weight: .semibold))
                            Text("Try searching with partial phone number or MRN").font(.system(size: 12)).foregroundStyle(DS.subAdaptive)
                        }
                        .frame(maxWidth: .infinity, minHeight: 130)
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredPatients) { p in
                            patientRow(p)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .background(DS.paperAdaptive.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAdd) {
            addSheet
                .modelContext(context)
        }
    }

    private func patientRow(_ p: Patient) -> some View {
        NavigationLink(destination: PatientDetailView(patient: p)) {
            Tile {
                HStack(spacing: 12) {
                    Text(String(p.name.split(separator: " ").compactMap(\.first).prefix(2)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(DS.coralGradient()))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.inkAdaptive)
                            .lineLimit(1)
                        
                        let ageText = p.age > 0 ? "\(p.age)y · " : ""
                        let sexText = p.sex != "Unknown" ? "\(p.sex) · " : ""
                        Text("\(ageText)\(sexText)\(p.mrn)")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.subAdaptive)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(p.reports.count)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.coral)
                        Text(p.reports.count == 1 ? "study" : "studies")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.subAdaptive)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                context.delete(p)
                try? context.save()
            } label: {
                Label("Delete Patient", systemImage: "trash")
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Patient Details") {
                    TextField("Full name", text: $newName)
                    TextField("MRN / Patient ID (optional)", text: $newMRN)
                    TextField("Phone Number (e.g. +91 9876543210)", text: $newPhone)
                        .keyboardType(.phonePad)
                    DatePicker("Date of Birth", selection: Binding(
                        get: { newDOB ?? Date() },
                        set: { newDOB = $0 }
                    ), displayedComponents: .date)
                    Picker("Sex", selection: $newSex) {
                        ForEach(["M", "F", "Other"], id: \.self) { Text($0) }
                    }
                }
                
                Section("Clinical Context") {
                    TextField("Referring Doctor / Hospital", text: $newReferring)
                }
            }
            .navigationTitle("New Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAdd = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let pat = Patient(name: newName, mrn: newMRN,
                                          dateOfBirth: newDOB, sex: newSex,
                                          phone: newPhone, referringPhysician: newReferring)
                        context.insert(pat)
                        do {
                            try context.save()
                        } catch {
                            print("Failed to save patient: \(error)")
                        }
                        newName = ""; newMRN = ""; newAge = ""; newPhone = ""; newReferring = ""
                        showAdd = false
                    }
                    .fontWeight(.semibold)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
