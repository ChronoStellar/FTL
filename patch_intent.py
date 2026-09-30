import re

with open("FTL/services/Intents/AddSpendIntent.swift", "r") as f:
    content = f.read()

# Remove BucketOptionsProvider
content = re.sub(r'// MARK: - Bucket options.*?struct BucketOptionsProvider: DynamicOptionsProvider \{.*?\n\}\n', '', content, flags=re.DOTALL)

# Add SpendCategoryEntity and SpendCategoryEntityQuery
entity_code = """// MARK: - App Entities

struct SpendCategoryEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
    static var defaultQuery = SpendCategoryEntityQuery()
    
    let id: String
    let name: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(stringLiteral: name)
    }
}

struct SpendCategoryEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [SpendCategoryEntity] {
        let environment = AppEnvironment.shared
        guard environment.auth.isSignedIn else { return [] }
        let categories = try? await environment.ledger.categories()
        return identifiers.compactMap { id in
            guard let cat = categories?.first(where: { $0.id.rawValue == id }) else { return nil }
            return SpendCategoryEntity(id: cat.id.rawValue, name: cat.name)
        }
    }
    
    @MainActor
    func suggestedEntities() async throws -> [SpendCategoryEntity] {
        let environment = AppEnvironment.shared
        guard environment.auth.isSignedIn else { return [] }
        let categories = try? await environment.ledger.categories()
        return categories?.map { SpendCategoryEntity(id: $0.id.rawValue, name: $0.name) } ?? []
    }
    
    @MainActor
    func entities(matching string: String) async throws -> [SpendCategoryEntity] {
        let environment = AppEnvironment.shared
        guard environment.auth.isSignedIn else { return [] }
        let categories = try? await environment.ledger.categories()
        return categories?
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map { SpendCategoryEntity(id: $0.id.rawValue, name: $0.name) } ?? []
    }
}
"""

content = content.replace("// MARK: - Errors", entity_code + "\n// MARK: - Errors")

# Update AddSpendIntent property
content = re.sub(
    r'@Parameter\(title: "Bucket", optionsProvider: BucketOptionsProvider\(\)\)\n\s*var bucket: String',
    '@Parameter(title: "Bucket")\n    var bucket: SpendCategoryEntity',
    content
)

# Update perform method to use entity
content = re.sub(
    r'let categories = try await environment\.ledger\.categories\(\)\n\s*guard let category = categories\.first\(where: \{\n\s*\$0\.name\.caseInsensitiveCompare\(bucket\) == \.orderedSame\n\s*\|\| \$0\.id == CategoryID\(rawValue: bucket\)\n\s*\}\) else \{\n\s*throw AddSpendIntentError\.unknownBucket\(bucket\)\n\s*\}',
    'let categoryID = CategoryID(rawValue: bucket.id)',
    content
)
# We also need to fix `category.name` and `category.id` references
content = re.sub(r'category\.id', 'categoryID', content)
content = re.sub(r'category\.name', 'bucket.name', content)

# Remove the unknownBucket error case since it's no longer used
content = re.sub(r'case unknownBucket\(String\)\n', '', content)
content = re.sub(r'case \.unknownBucket\(let name\):\n\s*"There\'s no bucket called \\\(name\) in your sheet\."\n', '', content)


with open("FTL/services/Intents/AddSpendIntent.swift", "w") as f:
    f.write(content)
