import Foundation

struct HL7Exporter {
    static func generateORU(for report: RadiologyReport) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyyMMddHHmmss"
        let msgTime = dateFmt.string(from: Date())
        let studyTime = dateFmt.string(from: report.studyDate)
        
        let msgControlID = UUID().uuidString.prefix(10).uppercased()
        let patientName = report.patient?.name.replacingOccurrences(of: " ", with: "^") ?? "UNKNOWN^PATIENT"
        let mrn = report.patient?.mrn ?? "UNKNOWN"
        var dob = ""
        if let d = report.patient?.dateOfBirth {
            let dFmt = DateFormatter()
            dFmt.dateFormat = "yyyyMMdd"
            dob = dFmt.string(from: d)
        }
        let sex = report.patient?.sex.prefix(1).uppercased() ?? "U"
        
        var hl7 = ""
        // MSH Segment
        hl7 += "MSH|^~\\&|RadiologySuite|Hospital|||M\(msgTime)||ORU^R01|M\(msgControlID)|P|2.5\n"
        
        // PID Segment
        hl7 += "PID|1||\(mrn)|||\(patientName)||\(dob)|\(sex)\n"
        
        // OBR Segment
        let accession = report.accessionNumber.isEmpty ? "ACC\(msgControlID)" : report.accessionNumber
        hl7 += "OBR|1||\(accession)|\(report.modality)^RADIOLOGY^LN|||\(studyTime)||||||||||||||||||F\n"
        
        // OBX Segments for each section
        var obxIndex = 1
        for section in report.sections {
            hl7 += "OBX|\(obxIndex)|TX|\(section.heading)^L||"
            let escapedText = section.text.replacingOccurrences(of: "\n", with: "~")
            hl7 += "\(escapedText)||||||F\n"
            obxIndex += 1
        }
        
        return hl7
    }
}
