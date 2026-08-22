import SwiftData
import SwiftUI

/// 할 일 행 (와이어프레임 1e: 22pt 체크박스 + 취소선 + 담당자·기한 배지)
struct TodoRowView: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            checkbox
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.text)
                    .font(.system(size: 15))
                    .strikethrough(todo.isDone)
                    .foregroundStyle(todo.isDone
                                     ? DesignTokens.textSecondary
                                     : DesignTokens.textPrimary)
                if todo.assignee != nil || todo.due != nil {
                    HStack(spacing: 6) {
                        if let assignee = todo.assignee {
                            badge(assignee)
                        }
                        if let due = todo.due {
                            badge(due)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            todo.isDone.toggle()
            try? modelContext.save()
        }
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(todo.isDone ? DesignTokens.accent : .clear)
            .frame(width: 22, height: 22)
            .overlay {
                if todo.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(DesignTokens.textSecondary.opacity(0.35), lineWidth: 2)
                }
            }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(DesignTokens.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(DesignTokens.textSecondary.opacity(0.1))
            .clipShape(Capsule())
    }
}
