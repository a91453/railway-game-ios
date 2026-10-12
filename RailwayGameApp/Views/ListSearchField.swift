import GamePresentation
import SwiftUI

/// A search field over a list of stations, lines or trains (decision 184):
/// a magnifier, what the player types, and a button that clears it. What
/// matches is ``ListSearch``'s rule, in GamePresentation.
struct ListSearchField: View {
    /// How many rows a list has before it offers the field: a short list
    /// is read at a glance, and its rows stay where they were.
    static let minimumRows = 6

    @Binding var search: ListSearch
    let prompt: String
    let identifier: String
    let language: DisplayLanguage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField(text: $search.query, prompt: Text(verbatim: prompt)) {
                Text(verbatim: prompt)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .accessibilityIdentifier(identifier)
            if !search.query.isEmpty {
                Button {
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: language.text("Clear search", "清除搜尋")))
                .accessibilityIdentifier("\(identifier).clear")
            }
        }
    }
}

/// "No line matches "Taipei"." under a search that keeps no row.
struct ListSearchEmpty: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }
}
