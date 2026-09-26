extension ApprovalQueueViewModel {
    func addCategory(name: String, for entry: ProvisionalEntry) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let slug = trimmed.replacingOccurrences(of: " ", with: "_")
        let categoryID = CategoryID(rawValue: slug)
        let cat = SpendCategory(id: categoryID, name: trimmed, parentID: CategoryID(rawValue: "total"))
        do {
            try await budgets.addCategory(cat, under: CategoryID(rawValue: "total"))
            await retag(entry, to: TagOption(id: categoryID, name: trimmed))
        } catch {
            actionError = "Failed to add category: \(error.localizedDescription)"
        }
    }

    func setNote(_ entry: ProvisionalEntry, note: String) async {
        var copy = entry
        copy.notes = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await store.update(copy)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
