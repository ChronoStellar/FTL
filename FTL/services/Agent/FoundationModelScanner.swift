import Foundation
import FoundationModels
import CoreGraphics

@available(iOS 27.0, macOS 27.0, *)
@Generable
struct ScannedBill: Sendable {
    @Guide(description: "The name of the merchant as it appears on the bill.")
    var merchant: String

    @Guide(description: "The total amount of the bill in the local currency. Return only the integer numbers.")
    var amount: Int
    
    @Guide(description: "A short sentence describing what this bill was for, if apparent.")
    var notes: String
    
    @Guide(description: "The date on the receipt in yyyy-MM-dd format, if present.")
    var date: String?
    
    @Guide(description: "The most likely spending category (e.g., food, transport, shopping, utilities) in lowercase.")
    var category: String?
}

@available(iOS 27.0, macOS 27.0, *)
nonisolated struct FoundationModelScanner: Sendable {
    private let options = GenerationOptions(temperature: 0.1)

    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func parse(ocrText: String) async throws -> ScannedBill? {
        guard Self.isAvailable else { return nil }

        let prompt = Prompt {
            "Extract the merchant name, total amount, and a short description of the purchase from this raw OCR text of a receipt:"
            ocrText
        }

        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: prompt,
            generating: ScannedBill.self,
            options: options
        )
        return response.content
    }

    private static let instructions = """
    You are an AI assistant that reads receipts and bills.
    Given raw OCR text from a receipt, extract the exact merchant name, the total final amount, the date, and infer the most likely category.
    Ensure the amount is just an integer (e.g., 50000).
    Provide a short summary in the notes field.
    """
}
