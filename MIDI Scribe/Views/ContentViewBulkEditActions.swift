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

extension ContentView {
    private var iPhoneBulkEditPanelWidth: CGFloat { 340 }
    private var bulkEditActionButtonWidth: CGFloat { 80 }
    private var iPhoneBulkEditPanelLeadingGap: CGFloat { 10 }
    private var iPhoneBulkEditHiddenOffset: CGFloat {
        // Shift far enough left so the full panel starts behind the sidebar.
        iPhoneBulkEditPanelWidth + iPhoneBulkEditPanelLeadingGap + 8
    }

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
                bulkEditActionButton(
                    context: BasicButtonContext(
                        action: {
                            mergeSilenceMsText = "0"
                            isPresentingMergeDialog = true
                        },
                        label: "Merge",
                        systemImage: "arrow.triangle.merge",
                        size: .extraLarge,
                        contentWidth: bulkEditActionButtonWidth
                    )
                )
                .disabled(viewModel.isTakeActionInProgress)
            }

            bulkEditActionButton(
                context: BasicButtonContext(
                    action: {
                        viewModel.toggleStarForSelectedTakes()
                        clearBulkSelection()
                    },
                    label: viewModel.allSelectedAreStarred ? "Unstar" : "Star",
                    systemImage: viewModel.allSelectedAreStarred ? "star.slash" : "star",
                    size: .extraLarge,
                    backgroundColor: .yellow,
                    foregroundColor: .black,
                    contentWidth: bulkEditActionButtonWidth

                )
            )
            .disabled(viewModel.isTakeActionInProgress)

            bulkEditActionButton(
                context: BasicButtonContext(
                    action: { beginBulkDeleteConfirmation() },
                    label: "Delete",
                    systemImage: "trash",
                    role: .destructive,
                    size: .extraLarge,
                    contentWidth: bulkEditActionButtonWidth
                )
            )
            .disabled(viewModel.isTakeActionInProgress)
        }
    }

    private func bulkEditActionButton(context: BasicButtonContext) -> some View {
        BasicButton(context: context)
    }

    @ViewBuilder
    func iPhoneBulkActionPanel(_ content: some View) -> some View {
#if os(iOS)
        content
            .overlay(alignment: .center) {
                iPhoneBulkActionPanelOverlay
            }
#else
        content
#endif
    }

#if os(iOS)
    var iPhoneBulkActionPanelOverlay: some View {
        GeometryReader { _ in
            HStack {
                Spacer(minLength: SidebarLayoutDefaults.defaultSidebarWidth + iPhoneBulkEditPanelLeadingGap)
                iPhoneBulkEditFloatingPanel
                    .frame(width: iPhoneBulkEditPanelWidth)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .ignoresSafeArea(edges: .bottom)
        .mask(alignment: .leading) {
            HStack(spacing: 0) {
                Color.clear.frame(width: SidebarLayoutDefaults.defaultSidebarWidth + 8)
                Rectangle()
            }
        }
        .offset(x: showsiPhoneBulkEditFloatingPanel ? 0 : -iPhoneBulkEditHiddenOffset)
        .opacity(showsiPhoneBulkEditFloatingPanel ? 1 : 0)
        .allowsHitTesting(showsiPhoneBulkEditFloatingPanel)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showsiPhoneBulkEditFloatingPanel)
    }
#else
    var iPhoneBulkActionPanelOverlay: some View {
        EmptyView()
    }
#endif

#if os(iOS)
    private var iPhoneBulkEditFloatingPanel: some View {
        VStack(spacing: 28) {
            Text(BulkEditCopy.panelTitle)
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)

            if hasBulkEditSelection {
                VStack(spacing: 16) {
                    bulkEditActionButtonContent
                }
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
