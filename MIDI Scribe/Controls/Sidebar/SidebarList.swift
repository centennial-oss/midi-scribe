//
//  SidebarList.swift
//  MIDI Scribe
//
//  Created by James Ranson on 4/23/26.
//

import SwiftUI

struct SidebarList<Data: RandomAccessCollection, ID: Hashable, Selection: Hashable, RowContent: View>: View {
    let data: Data
    let id: KeyPath<Data.Element, ID>
    @Binding var selection: Selection?
    let header: SidebarListHeader?
    let isMultiSelecting: Bool
    let disabledMultiSelectionIDs: Set<ID>
    @Environment(\.sidebarUsesCustomLayout) private var isCustom
    @State private var multiSelectedIDs: Set<ID> = []
    private var externalMultiSelectedIDs: Binding<Set<ID>>?
    private var onMultiSelectionChange: (([Data.Element]) -> Void)?
    @ViewBuilder let rowContent: (Data.Element) -> RowContent

    init(
        data: Data,
        id: KeyPath<Data.Element, ID>,
        selection: Binding<Selection?>,
        header: SidebarListHeader? = nil,
        isMultiSelecting: Bool = false,
        multiSelectedIDs: Binding<Set<ID>>? = nil,
        disabledMultiSelectionIDs: Set<ID> = [],
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) {
        self.data = data
        self.id = id
        self._selection = selection
        self.header = header
        self.isMultiSelecting = isMultiSelecting
        self.disabledMultiSelectionIDs = disabledMultiSelectionIDs
        self.externalMultiSelectedIDs = multiSelectedIDs
        self.onMultiSelectionChange = nil
        self.rowContent = rowContent
    }

    var body: some View {
        Group {
            if isCustom {
                VStack(alignment: .leading, spacing: 0) {
                    if let header {
                        headerView(header)
                            .padding(.leading, 4)
                            .padding(.bottom, 2)
                    }
                    ForEach(data, id: id) { item in
                        rowContent(item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let header {
                        headerView(header)
                            .padding(.leading, 4)
                            .padding(.bottom, 4)
                    }
                    rows
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .environment(\.sidebarMultiSelectContext, SidebarMultiSelectContext(
            isEnabled: isMultiSelecting,
            isValueSelected: { value in
                guard let valueID = value.base as? ID else {
                    return false
                }
                return selectedIDs.contains(valueID)
            },
            isValueDisabled: { value in
                guard let valueID = value.base as? ID else {
                    return false
                }
                return disabledMultiSelectionIDs.contains(valueID)
            },
            toggleValue: { value in
                guard let valueID = value.base as? ID else {
                    return
                }
                toggleSelection(for: valueID)
            }
        ))
        .onChange(of: isMultiSelecting) { _, newValue in
            if !newValue {
                selectedIDs = []
                onMultiSelectionChange?([])
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(data, id: id) { item in
            rowContent(item)
        }
    }

    private func toggleSelection(for id: ID) {
        var nextSelection = selectedIDs
        if nextSelection.contains(id) {
            nextSelection.remove(id)
        } else {
            nextSelection.insert(id)
        }
        selectedIDs = nextSelection
        onMultiSelectionChange?(selectedElements)
    }

    private var selectedElements: [Data.Element] {
        data.filter { selectedIDs.contains($0[keyPath: id]) }
    }

    private var selectedIDs: Set<ID> {
        get {
            externalMultiSelectedIDs?.wrappedValue ?? multiSelectedIDs
        }
        nonmutating set {
            if let externalMultiSelectedIDs {
                externalMultiSelectedIDs.wrappedValue = newValue
            } else {
                multiSelectedIDs = newValue
            }
        }
    }

    func onMultiSelectionChange(_ action: @escaping ([Data.Element]) -> Void) -> Self {
        var copy = self
        copy.onMultiSelectionChange = action
        return copy
    }

    private func headerView(_ header: SidebarListHeader) -> some View {
        HStack {
            Text(header.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            HStack {
                ForEach(Array(header.buttons.enumerated()), id: \.offset) { _, button in
                    button
                }
            }
        }
    }
}
