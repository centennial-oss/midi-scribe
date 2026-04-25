import SwiftUI

extension ContentView {
    private static let sidebarQuickActionIconSize: CGFloat = BuildInfo.isMac ? 16 : 24

    @ViewBuilder
    func sidebarRowQuickActions(for take: RecordedTakeListItem) -> some View {
        HStack(spacing: 24) {
            Button {
                withAnimation { swipeRevealedTakeID = nil }
                beginRename(take)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: Self.sidebarQuickActionIconSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: Self.sidebarQuickActionIconSize, height: Self.sidebarQuickActionIconSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { swipeRevealedTakeID = nil }
                viewModel.toggleStar(takeID: take.id)
            } label: {
                Image(systemName: take.isStarred ? "star.fill" : "star")
                    .font(.system(size: Self.sidebarQuickActionIconSize, weight: .medium))
                    .foregroundStyle(.yellow)
                    .frame(width: Self.sidebarQuickActionIconSize, height: Self.sidebarQuickActionIconSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { swipeRevealedTakeID = nil }
                beginDeleteTake(id: take.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: Self.sidebarQuickActionIconSize, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: Self.sidebarQuickActionIconSize, height: Self.sidebarQuickActionIconSize)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 4)
    }
}
