//
//  ContentViewBulkEditActions.swift
//  MIDI Scribe
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum BulkEditCopy {
    static let panelTitle = "Manage Saved Takes"
    static let emptySelectionInstruction = "Select one or more Takes in the sidebar to make changes."
}

#if os(iOS)
private let defaultSidebarWidth: CGFloat = 380
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
            bulkEditActionButtonContent
        }
    }

    @ViewBuilder
    var bulkEditActionButtonsStack: some View {
        VStack(spacing: 16) {
            bulkEditActionButtonContent
        }
    }

    @ViewBuilder
    private var bulkEditActionButtonContent: some View {
        if hasBulkEditSelection {
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
            .overlay(alignment: .center) {
                if showsiPhoneBulkEditFloatingPanel {
                    GeometryReader { geometry in
                        HStack {
                            Spacer(minLength: defaultSidebarWidth + 10)
                            iPhoneBulkEditFloatingPanel
                                .frame(width: 340)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
#else
        content
#endif
    }

#if os(iOS)
    private var iPhoneBulkEditFloatingPanel: some View {
        VStack(spacing: 28) {
            Text(BulkEditCopy.panelTitle)
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)

            if hasBulkEditSelection {
                bulkEditActionButtonsStack
                    .frame(maxWidth: .infinity)
            } else {
                Text(BulkEditCopy.emptySelectionInstruction)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground).opacity(0.9))
        )
    }

    var showsiPhoneBulkEditFloatingPanel: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && isEditingList
    }
#endif
}
