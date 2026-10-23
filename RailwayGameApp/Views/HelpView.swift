import GamePresentation
import SwiftUI

/// The help guide (decision 177): the questions players ask, with their
/// answers, in the game's language only; the search also finds the other
/// language's words (``HelpGuide``). Opened from the start screen, the game menu and the
/// settings. Since decision 381 its first row opens the data sources and
/// licences, whose start screen capsule went.
struct HelpView: View {
    let language: DisplayLanguage
    /// The launcher the data sources read their files' problems from;
    /// without one there is no data sources row.
    var launcher: GameLauncher? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showsDataSources = false
    @State private var query = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        NavigationStack {
            let found = HelpGuide.entries(matching: query)
            let showsDataSourcesRow = launcher != nil && DataSourcesEntry.shows(matching: query)
            List {
                if showsDataSourcesRow {
                    Section {
                        Button {
                            showsDataSources = true
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: DataSourcesEntry.title(in: language))
                                        .font(.headline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(verbatim: DataSourcesEntry.detail(in: language))
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            } icon: {
                                Image(systemName: "info.circle")
                            }
                        }
                        .accessibilityIdentifier(DataSourcesEntry.helpIdentifier)
                    }
                }
                if found.isEmpty && !showsDataSourcesRow {
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
                                    Text(verbatim: entry.shownText(in: language).answer)
                                        .font(.subheadline)
                                        .padding(.vertical, 4)
                                } label: {
                                    Text(verbatim: entry.shownText(in: language).question)
                                        .font(.headline)
                                }
                                .accessibilityIdentifier("help.\(entry.id)")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .sheet(isPresented: $showsDataSources) {
                if let launcher {
                    DataSourcesView(launcher: launcher)
                }
            }
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
