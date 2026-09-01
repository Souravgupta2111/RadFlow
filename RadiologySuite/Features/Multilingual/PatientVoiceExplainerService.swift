import Foundation
import AVFoundation
import Combine

/// Multilingual Regional Patient Voice Explainer Service.
/// Takes clinical findings & doctor's action plan and translates them into plain-language
/// regional audio voice notes (Hindi, Marathi, Bengali, Tamil, Telugu, Gujarati, Spanish, Arabic, English)
/// for patient understanding and WhatsApp voice dispatch.
final class PatientVoiceExplainerService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = PatientVoiceExplainerService()

    @Published var isPlaying: Bool = false
    @Published var isPaused: Bool = false
    @Published var selectedLanguage: String = "Hindi"
    @Published var translatedText: String = ""

    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    struct SupportedLanguage: Identifiable, Hashable {
        let id: String
        let name: String
        let nativeName: String
        let locale: String
        let flag: String
    }

    static let availableLanguages: [SupportedLanguage] = [
        .init(id: "Hindi", name: "Hindi", nativeName: "हिंदी", locale: "hi-IN", flag: "🇮🇳"),
        .init(id: "Marathi", name: "Marathi", nativeName: "मराठी", locale: "mr-IN", flag: "🇮🇳"),
        .init(id: "Bengali", name: "Bengali", nativeName: "বাংলা", locale: "bn-IN", flag: "🇮🇳"),
        .init(id: "Tamil", name: "Tamil", nativeName: "தமிழ்", locale: "ta-IN", flag: "🇮🇳"),
        .init(id: "Telugu", name: "Telugu", nativeName: "తెలుగు", locale: "te-IN", flag: "🇮🇳"),
        .init(id: "Gujarati", name: "Gujarati", nativeName: "ગુજરાતી", locale: "gu-IN", flag: "🇮🇳"),
        .init(id: "Spanish", name: "Spanish", nativeName: "Español", locale: "es-ES", flag: "🇪🇸"),
        .init(id: "Arabic", name: "Arabic", nativeName: "العربية", locale: "ar-SA", flag: "🇸🇦"),
        .init(id: "English", name: "English", nativeName: "English", locale: "en-US", flag: "🇬🇧")
    ]

    /// Translates clinical summary and action plan into chosen regional language.
    func translateSummary(patient: Patient?, report: RadiologyReport, to language: String) -> String {
        let pName = patient?.name ?? "Patient"
        let modality = report.modality
        let isNormal = report.plainText.lowercased().contains("normal") || report.plainText.lowercased().contains("no acute")
        let followUp = report.followUpAdvice ?? "follow-up as advised"
        let meds = report.medicationsOrPrecautions ?? "prescribed medications"

        switch language {
        case "Hindi":
            if isNormal {
                return "नमस्ते \(pName) जी, आपकी \(modality) जाँच रिपोर्ट सामान्य है। कोई गंभीर समस्या नहीं मिली है। डॉक्टर की सलाह अनुसार \(meds) नियमित लें और \(followUp) पर दोबारा मिलें।"
            } else {
                return "नमस्ते \(pName) जी, आपकी \(modality) जाँच रिपोर्ट तैयार है। डॉक्टर ने ध्यानपूर्वक देखा है। कृपया समय पर \(meds) लें और \(followUp) के लिए आएं। अपना पूरा ध्यान रखें।"
            }
        case "Marathi":
            if isNormal {
                return "नमस्कार \(pName), तुमचा \(modality) तपासणी अहवाल सामान्य आहे. कोणतीही गंभीर समस्या नाही. डॉक्टरांच्या सल्ल्यानुसार औषधे घ्या आणि वेळेवर भेटा."
            } else {
                return "नमस्कार \(pName), तुमचा \(modality) अहवाल तयार आहे. कृपया दिलेल्या सूचना आणि औषधे नियमितपणे घ्या आणि पुढील तपासणीसाठी या."
            }
        case "Bengali":
            if isNormal {
                return "নমস্কার \(pName) বাবু, আপনার \(modality) রিপোর্ট সম্পূর্ণ স্বাভাবিক। উদ্বেগের কিছু নেই। নিয়মিত ওষুধ খান এবং ডাক্তারের পরামর্শ মেনে চলুন।"
            } else {
                return "নমস্কার \(pName), আপনার \(modality) রিপোর্ট তৈরি হয়েছে। অনুগ্রহ করে চিকিৎসকের পরামর্শ অনুযায়ী ওষুধ সেবন করুন এবং ফলো-আপে আসুন।"
            }
        case "Tamil":
            if isNormal {
                return "வணக்கம் \(pName), உங்கள் \(modality) பரிசோதனை அறிக்கை இயல்பாக உள்ளது. கவலைப்பட தேவையில்லை. மருத்துவரின் அறிவுரைப்படி மருந்துகளை உட்கொள்ளவும்."
            } else {
                return "வணக்கம் \(pName), உங்கள் \(modality) அறிக்கை தயாராக உள்ளது. மருத்துவர் கூறியபடி மருந்துகளை எடுத்துக்கொண்டு மறுபரிசோதனைக்கு வரவும்."
            }
        case "Telugu":
            if isNormal {
                return "నమస్కారం \(pName), మీ \(modality) పరీక్ష నివేదిక సాధారణంగా ఉంది. ఆందోళన చెందాల్సిన అవసరం లేదు. సూచించిన మందులు వాడండి."
            } else {
                return "నమస్కారం \(pName), మీ \(modality) నివేదిక సిద్ధంగా ఉంది. దయచేసి డాక్టర్ చెప్పిన మందులను సమయానికి వాడి ఫాలో-అప్‌కు రండి."
            }
        case "Gujarati":
            if isNormal {
                return "નમસ્તે \(pName), તમારો \(modality) તપાસ રિપોર્ટ સામાન્ય છે. ચિંતા કરવાની જરૂર નથી. નિયમિત દવાઓ લો અને ડોક્ટરની સલાહ મુજબ ફોલો-અપ કરો."
            } else {
                return "નમસ્તે \(pName), તમારો \(modality) રિપોર્ટ તૈયાર છે. કૃપા કરીને સૂચવેલી દવાઓ સમયસર લો અને નિયમિત તપાસ માટે આવો."
            }
        case "Spanish":
            if isNormal {
                return "Hola \(pName), su estudio de \(modality) es normal. No hay hallazgos agudos. Continúe con las indicaciones de su médico."
            } else {
                return "Hola \(pName), su informe de \(modality) está listo. Por favor siga las instrucciones médicas y acuda a su control programado."
            }
        case "Arabic":
            return "مرحباً \(pName)، تم تجهيز تقرير الفحص الخاص بك بنجاح. يرجى اتباع تعليمات الطبيب وتناول الأدوية الموصوفة ومراجعة العيادة في الموعد المحدد."
        default: // English
            if isNormal {
                return "Hello \(pName), your \(modality) report is normal with no acute findings. Please take any prescribed medications and return for your scheduled follow-up."
            } else {
                return "Hello \(pName), your \(modality) report is ready. Please follow the prescribed care plan (\(meds)) and return for \(followUp)."
            }
        }
    }

    /// Speaks the translated regional voice note using the native locale.
    func speakVoiceNote(text: String, languageName: String) {
        stop()
        guard !text.isEmpty else { return }

        translatedText = text
        selectedLanguage = languageName
        let localeCode = Self.availableLanguages.first(where: { $0.name == languageName })?.locale ?? "hi-IN"

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: localeCode) ?? AVSpeechSynthesisVoice(language: "en-IN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        isPlaying = true
        isPaused = false
        synthesizer.speak(utterance)
    }

    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
        }
    }

    func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPlaying = false
        isPaused = false
    }

    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = true
            self.isPaused = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isPaused = false
        }
    }
}
