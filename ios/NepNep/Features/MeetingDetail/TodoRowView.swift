import SwiftData
import SwiftUI

/// 할 일 행 (와이어프레임 1e: 22pt 체크박스 + 취소선)
///
/// 담당자·기한·상태 배지는 걷어냈다 (#21). 모델이 기한 칸에 "완료"를 넣어
/// 같은 배지가 나란히 두 번 붙는 등 값 자체를 믿기 어려웠고, 화면에서 필요한 건
/// 할 일 목록 그 자체였다. 값은 계속 저장돼 내보내기에는 그대로 실린다.
struct TodoRowView: View {
    @Bindable var todo: TodoItem
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            checkbox
            Text(todo.text)
                .font(.system(size: 15))
                .strikethrough(todo.isDone)
                .foregroundStyle(todo.isDone
                                 ? DesignTokens.textSecondary
                                 : DesignTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
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
}
