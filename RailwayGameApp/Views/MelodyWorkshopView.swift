import GameCore
import GamePresentation
import SwiftUI

/// Decision 883: the melody workshop (decision 219, stage 4): a piano
/// roll of four bars of 3/4 in eighths across and the C major scale from
/// C7 to C5 down the side (`MelodyDraft`), the length of the next note,
/// the official melodies' tunes to start from, a play button, and save.
/// The draft is the sheet's own until it is saved through `GameSession`.
struct MelodyWorkshopView: View {
    let session: GameSession
    @State var draft: MelodyDraft
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeletion = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// One cell of the roll: a finger's width.
    @ScaledMetric(relativeTo: .body) private var cell: CGFloat = 44

    var body: some View {
        let language = session.language
        NavigationStack {
            Group {
                // A phone on its side has room for two or three rows of
                // the roll under the controls: they go beside it instead.
                if verticalSizeClass == .compact {
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 12) {
                                nameField
                                lengthPicker(segmented: false)
                                actions(stacked: true)
                                hint
                            }
                        }
                        .frame(width: 240)
                        roll
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        nameField
                        ScrollView(.horizontal) { lengthPicker(segmented: true) }
                        actions(stacked: false)
                        roll
                        hint
                    }
                }
            }
            .padding()
            .background(Theme.background)
            .navigationTitle(Text(verbatim: MelodyDraft.title(in: language)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("Cancel", "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Save", "儲存")) {
                        if session.saveMelody(draft) != nil { dismiss() }
                    }
                    .disabled(!draft.canSave)
                    .accessibilityIdentifier("melody.save")
                }
                if let id = draft.melody {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(language.text("Delete", "刪除"), systemImage: "trash", role: .destructive) {
                            confirmingDeletion = true
                        }
                        .confirmationDialog(
                            Text(verbatim: language.text("Delete \(draft.name)?", "刪除「\(draft.name)」？")),
                            isPresented: $confirmingDeletion, titleVisibility: .visible
                        ) {
                            Button(language.text("Delete", "刪除"), role: .destructive) {
                                session.deleteMelody(id)
                                dismiss()
                            }
                        } message: {
                            Text(verbatim: language.text("Stations playing it go back to each line's own.", "用這首的車站會改回依路線。"))
                        }
                    }
                }
            }
        }
    }

    private var nameField: some View {
        TextField(text: $draft.name) {
            Text(verbatim: session.language.text("Name", "名稱"))
        }
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("melody.name")
    }

    private var hint: some View {
        Text(verbatim: MelodyDraft.note(in: session.language))
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
    }

    /// The length of the next note: segments where there is room, else a
    /// menu.
    @ViewBuilder private func lengthPicker(segmented: Bool) -> some View {
        let picker = Picker(selection: $draft.length) {
            ForEach(MelodyDraft.NoteLength.allCases, id: \.self) { length in
                Text(verbatim: length.title(in: session.language)).tag(length)
            }
        } label: {
            Text(verbatim: session.language.text("Note length", "音符長度"))
        }
        .accessibilityIdentifier("melody.length")
        if segmented {
            picker.pickerStyle(.segmented).fixedSize()
        } else {
            LabeledContent {
                picker.pickerStyle(.menu)
            } label: {
                Text(verbatim: session.language.text("Note length", "音符長度"))
            }
        }
    }

    /// The play button, the tunes to start from and clearing: in a row,
    /// or one under another beside the roll.
    private func actions(stacked: Bool) -> some View {
        let language = session.language
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button(language.text("Play", "試聽"), systemImage: "play.fill") {
                session.playMelodyPreview(draft.notes)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.notes.isEmpty)
            .accessibilityIdentifier("melody.play")
            Menu {
                ForEach(DepartureMelody.allCases, id: \.self) { melody in
                    Button(melody.title(in: language)) { draft.start(from: melody) }
                }
            } label: {
                Label(language.text("Start from", "從現有旋律開始"), systemImage: "music.note.list")
            }
            .accessibilityIdentifier("melody.startFrom")
            Button(language.text("Clear", "清除"), systemImage: "eraser") {
                draft.clear()
            }
            .disabled(draft.notes.isEmpty)
        }
        .buttonStyle(.bordered)
        .frame(minHeight: 44)
    }

    /// The roll: the note names stay at the left while the bars scroll.
    private var roll: some View {
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 2) {
                    ForEach(MelodyDraft.rows.indices, id: \.self) { row in
                        Text(verbatim: MelodyDraft.rowTitle(row))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MelodyDraft.rows[row] % 12 == 0 ? Theme.textPrimary : Theme.textSecondary)
                            .frame(minWidth: 28, minHeight: cell, alignment: .trailing)
                    }
                }
                .accessibilityHidden(true)
                ScrollView(.horizontal) {
                    Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                        ForEach(MelodyDraft.rows.indices, id: \.self) { row in
                            GridRow {
                                ForEach(0..<MelodyDraft.columns, id: \.self) { column in
                                    cellButton(row: row, column: column)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier("melody.roll")
    }

    private func cellButton(row: Int, column: Int) -> some View {
        let language = session.language
        let sounds = draft.sounds(row: row, column: column)
        let starts = draft.starts(row: row, column: column)
        let bar = column / MelodyDraft.columnsPerBar + 1
        let beat = column % MelodyDraft.columnsPerBar / 2 + 1
        let half = column % 2 == 0 ? "" : language.text(" and", "後半")
        return Button {
            draft.tap(row: row, column: column)
        } label: {
            RoundedRectangle(cornerRadius: starts ? 6 : 2)
                .fill(sounds ? Theme.primary : column / MelodyDraft.columnsPerBar % 2 == 0 ? Theme.chip : Theme.panel)
                .overlay(alignment: .leading) {
                    if starts {
                        Rectangle().fill(Theme.onPrimary.opacity(0.6)).frame(width: 3)
                    }
                }
                .frame(width: cell, height: cell)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(MelodyDraft.rowTitle(row)), "
            + language.text("bar \(bar) beat \(beat)\(half)", "第 \(bar) 小節第 \(beat) 拍\(half)")))
        .accessibilityValue(Text(verbatim: sounds ? language.text("Note", "有音") : language.text("Empty", "空")))
        .accessibilityAddTraits(sounds ? .isSelected : [])
    }
}

/// Decision 883: a workshop the station panel opens: a new melody, or one
/// to rewrite (`sheet(item:)`).
struct MelodyWorkshopSheet: Identifiable {
    let id: Int
    let draft: MelodyDraft
}
