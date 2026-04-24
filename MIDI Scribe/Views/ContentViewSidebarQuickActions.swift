import SwiftUI

extension ContentView {
    @ViewBuilder
    func sidebarRowQuickActions(for take: RecordedTakeListItem) -> some View {
        HStack(spacing: 24) {
            Button {
                withAnimation { swipeRevealedTakeID = nil }
                beginRename(take)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { swipeRevealedTakeID = nil }
                viewModel.toggleStar(takeID: take.id)
            } label: {
                Image(systemName: take.isStarred ? "star.fill" : "star")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.yellow)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { swipeRevealedTakeID = nil }
                beginDeleteTake(id: take.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 4)
    }
}
