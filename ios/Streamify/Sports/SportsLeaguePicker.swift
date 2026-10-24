import SwiftUI

/// Matches Android's league filter: edits remain a draft until Apply filters.
struct SportsLeaguePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Set<SportsLeague>
    let apply: (Set<SportsLeague>) -> Void

    init(selected: Set<SportsLeague>, apply: @escaping (Set<SportsLeague>) -> Void) {
        _draft = State(initialValue: selected == Set(SportsLeague.allCases) ? [] : selected)
        self.apply = apply
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose leagues to filter games and calendar dots. Leave everything unchecked to show all leagues.")
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                    Button("Show all leagues") { draft.removeAll() }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("sports-clear-leagues")
                    VStack(spacing: 8) {
                        ForEach(SportsLeague.allCases) { league in
                            Button {
                                if draft.contains(league) { draft.remove(league) }
                                else { draft.insert(league) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image("league-\(league.rawValue)").resizable().scaledToFit().frame(width: 24, height: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(league.title).font(.subheadline.weight(.semibold))
                                        Text(league.subtitle).font(.caption).foregroundStyle(AppTheme.muted)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: draft.contains(league) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(draft.contains(league) ? AppTheme.foreground : AppTheme.muted)
                                }.padding(12).frame(minHeight: 52).streamifyControlSurface()
                            }.buttonStyle(HapticPlainButtonStyle())
                                .accessibilityLabel(league.title)
                                .accessibilityValue(draft.contains(league) ? "Selected" : "Not selected")
                                .accessibilityAddTraits(draft.contains(league) ? .isSelected : [])
                                .accessibilityIdentifier("sports-league-option-\(league.rawValue)")
                        }
                    }
                    Button { apply(draft.isEmpty ? Set(SportsLeague.allCases) : draft) } label: {
                        Text("Apply filters").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("sports-apply-leagues")
                }.padding(20)
            }.background(AppTheme.canvas).foregroundStyle(AppTheme.foreground)
                .navigationTitle("Filter leagues").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .accessibilityElement(children: .contain).accessibilityIdentifier("sports-league-sheet")
    }
}
