import GamePresentation
import SwiftUI

/// The help guide (decision 177): the questions players ask, with their
/// answers in the game's language and the other language below, searchable
/// (``HelpGuide``). Opened from the start screen, the game menu and the
/// settings.
struct HelpView: View {
    let language: DisplayLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        NavigationStack {
            let found = HelpGuide.entries(matching: query)
            List {
                if found.isEmpty {
                    Text(verbatim: language.text("Nothing matches. Try another word.", "找不到相符的內容，換個關鍵字試試。"))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("help.empty")
                }
                ForEach(HelpEntry.Topic.allCases, id: \.self) { topic in
                    let entries = found.filter { $0.topic == topic }
                    if !entries.isEmpty {
                        Section(topic.title(in: language)) {
                            ForEach(entries) { entry in
                                DisclosureGroup(isExpanded: binding(for: entry)) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(verbatim: entry.answer(in: language))
                                        Divider()
                                        Text(verbatim: entry.otherQuestion(than: language))
                                            .font(.footnote.weight(.semibold))
                                        Text(verbatim: entry.otherAnswer(than: language))
                                            .font(.footnote)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .font(.subheadline)
                                    .padding(.vertical, 4)
                                } label: {
                                    Text(verbatim: entry.question(in: language))
                                        .font(.headline)
                                }
                                .accessibilityIdentifier("help.\(entry.id)")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: Text(verbatim: HelpGuide.searchPrompt(in: language)))
            .navigationTitle(language.text("Help", "說明"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Done", "完成")) { dismiss() }
                        .accessibilityIdentifier("help.done")
                }
            }
            // A search that finds one answer opens it.
            .onChange(of: query) { _, _ in
                let found = HelpGuide.entries(matching: query)
                if !query.isEmpty, found.count == 1 { expanded = [found[0].id] }
            }
        }
    }

    private func binding(for entry: HelpEntry) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(entry.id) },
            set: { if $0 { expanded.insert(entry.id) } else { expanded.remove(entry.id) } }
        )
    }
}
