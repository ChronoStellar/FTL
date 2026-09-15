import AppIntents

struct MyShortcut: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddSpendIntent(),
            phrases: [
                "Check budget"
            ],
            shortTitle: "Check Daily Budget",
            systemImageName: "dollarsign.circle"
        )
    }
}
