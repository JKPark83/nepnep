import SwiftUI

/// 페이월 (07-m5 §2, 와이어프레임 1i 확정본)
/// 진입 3곳만: 녹음 토글(무료) / 설정 "프로 자세히 보기" / 사용량 초과 알럿. 실행 시 자동 표시 금지.
struct PaywallView: View {
    /// 구매 성공 시 호출 — 토글에서 열렸으면 토글을 켠다 (1i 노트)
    var onPurchased: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var purchase = PurchaseService.shared
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            closeButton
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleSection
                    freeCard
                    proCard
                }
                .padding(.horizontal, DesignTokens.margin)
                .padding(.top, 6)
            }
            footer
        }
        .background(DesignTokens.background)
        .task { await purchase.loadProductIfNeeded() }
        .alert("구매 오류", isPresented: .constant(errorMessage != nil)) {
            Button("확인") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var closeButton: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(DesignTokens.card, in: Circle())
            }
        }
        .padding(.horizontal, DesignTokens.margin)
        .padding(.top, 12)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("더 정확한 회의록이\n필요할 때만")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("기기 안 처리는 계속 무료입니다. 프로는 클라우드 고품질 처리를 더해요.")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    // 무료 카드를 먼저 — 잃는 것이 없다는 점을 보여준다 (1i 노트 2)
    private var freeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("무료")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                Text("현재 사용 중")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DesignTokens.textSecondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            featureRow("온디바이스 녹음·전사·요약 무제한", accent: false)
            featureRow("Notion · Google Docs 자동 내보내기", accent: false)
        }
        .padding(16)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
    }

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("프로")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.accent)
                Spacer()
                Text(priceText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            featureRow("클라우드 고품질 STT · 요약 월 20시간", accent: true)
            featureRow("이름·전문 용어·외래어 인식 향상", accent: true)
            featureRow("무료 기능은 그대로 포함", accent: true)
        }
        .padding(16)
        .background(DesignTokens.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius)
                .strokeBorder(DesignTokens.accent, lineWidth: 1.5)
        }
    }

    private func featureRow(_ text: String, accent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(accent ? DesignTokens.accent : DesignTokens.textSecondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(accent ? DesignTokens.textPrimary : DesignTokens.textSecondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            // 암호화·미저장 문구는 구매 버튼 바로 위 (1i 노트 3)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: "lock")
                    .font(.caption2)
                Text("클라우드 처리 시 오디오는 전송 구간에서 암호화되며 서버에 저장되지 않습니다.")
                    .font(.caption)
            }
            .foregroundStyle(DesignTokens.textSecondary.opacity(0.8))
            .padding(.horizontal, 4)

            Button {
                startPurchase()
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text("프로 시작하기").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: DesignTokens.buttonHeight)
                .background(DesignTokens.accent)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(isPurchasing)

            HStack(spacing: 20) {
                Button("구매 복원") {
                    Task {
                        await purchase.restore()
                        if purchase.isPro {
                            onPurchased()
                            dismiss()
                        }
                    }
                }
                Text("·").foregroundStyle(DesignTokens.textSecondary.opacity(0.5))
                Link("약관", destination: AppReviewSupport.eulaURL)
                Text("·").foregroundStyle(DesignTokens.textSecondary.opacity(0.5))
                Link("개인정보", destination: AppReviewSupport.privacyPolicyURL)
            }
            .font(.footnote)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.horizontal, DesignTokens.margin)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var priceText: String {
        if let product = purchase.product {
            return "월 \(product.displayPrice)"
        }
        return "월 6,900원"
    }

    private func startPurchase() {
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                if try await purchase.purchase() {
                    onPurchased()
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
