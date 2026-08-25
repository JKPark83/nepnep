import SwiftUI

/// 설정 > 회의 용어 (#21 후속)
///
/// 여기 적어 둔 단어는 요약 프롬프트에 실려, 전사가 흘려 들은 고유명사를
/// 요약·제목·안건에서 바로잡는 데 쓰인다. 전사 원문 자체는 바뀌지 않는다 —
/// 그 이유는 `TranscriptionGlossary` 주석에 적어 뒀다.
struct GlossarySection: View {
    @AppStorage(TranscriptionGlossary.storageKey) private var rawText = ""

    private var count: Int { TranscriptionGlossary.parse(rawText).count }

    var body: some View {
        Section {
            TextEditor(text: $rawText)
                .frame(minHeight: 108)
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textPrimary)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            HStack {
                Text("등록된 용어")
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Text("\(count)개")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(count >= TranscriptionGlossary.maxTerms
                                     ? .red : DesignTokens.textSecondary)
            }
        } header: {
            Text("회의 용어")
        } footer: {
            Text("자주 나오는 이름·제품명·기술 용어를 줄바꿈이나 쉼표로 구분해 적어 두세요. 요약에서 이 표기로 적힙니다. 영어 용어는 '레디스'로 적어 두셔도 요약에는 'Redis'처럼 알파벳으로 나옵니다. 전사 원문은 그대로이고, 다음 요약부터 최대 \(TranscriptionGlossary.maxTerms)개까지 쓰입니다.")
        }
    }
}
