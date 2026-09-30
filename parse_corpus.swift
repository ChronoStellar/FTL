import Foundation

struct Email: Codable {
    let messageId: String?
}
let data = try! Data(contentsOf: URL(fileURLWithPath: "FTL/Fixtures/empty-state-corpus.json"))
let emails = try! JSONDecoder().decode([Email].self, from: data)
print("Emails count: \(emails.count)")
