//
//  ContentViewBulkEditActions.swift
//  MIDI Scribe
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

extension ContentView {
    var hasBulkEditSelection: Bool {
        !viewModel.multiSelection.isEmpty
    }

    var canMergeSelectedTakes: Bool {
        viewModel.multiSelection.count >= 2
    }

    @ViewBuilder
    var bulkEditActionButtons: some View {
        HStack(spacing: 16) {
            if canMergeSelectedTakes {
                BasicButton(
                    context: BasicButtonContext(
                        action: {
                            mergeSilenceMsText = "0"
                            isPresentingMergeDialog = true
                        },
                        label: "Merge",
                        systemImage: "arrow.triangle.merge"
                    )
                )
                .disabled(viewModel.isTakeActionInProgress)
            }

            BasicButton(
                context: BasicButtonContext(
                    action: { viewModel.toggleStarForSelectedTakes() },
                    label: viewModel.allSelectedAreStarred ? "Unstar" : "Star",
                    systemImage: viewModel.allSelectedAreStarred ? "star.slash" : "star",
                    backgroundColor: .yellow,
                    foregroundColor: .black
                )
            )
            .disabled(viewModel.isTakeActionInProgress)

            BasicButton(
                context: BasicButtonContext(
                    action: { beginBulkDeleteConfirmation() },
                    label: "Delete",
                    systemImage: "trash",
                    role: .destructive
                )
            )
            .disabled(viewModel.isTakeActionInProgress)
        }
    }

    @ViewBuilder
    func bottomBulkEditActionRowContent(_ content: some View) -> some View {
#if os(iOS)
        content
            .safeAreaInset(edge: .bottom) {
                if showsNarrowiPhoneBulkEditActionRow {
                    HStack(spacing: 12) {
                        bulkEditActionButtons
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .background(.ultraThinMaterial)
                }
            }
#else
        content
#endif
    }

#if os(iOS)
    var showsNarrowiPhoneBulkEditActionRow: Bool {
        isNarrowiPhone && isEditingList && hasBulkEditSelection
    }

    private var isNarrowiPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && horizontalSizeClass == .compact
    }
#endif
}
