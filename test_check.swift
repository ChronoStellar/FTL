import Foundation
func check(_ message: String, _ actual: Any, _ expected: Any) {
    if "\(actual)" == "\(expected)" {
        print("✓ \(message): \(actual)")
    } else {
        print("✗ \(message): \(actual) — expected \(expected)")
    }
}
check("every row flagged unverified", 45, 95)
