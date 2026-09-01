import SwiftData
@Model class Patient { var id: String = "" }
func test(context: ModelContext) {
    try? context.delete(model: Patient.self)
}
