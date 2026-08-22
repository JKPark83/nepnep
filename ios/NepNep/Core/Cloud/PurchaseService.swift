import Foundation
import StoreKit

/// StoreKit 2 구독 상태 (07-m5 §1, F8)
/// 계정 없는 설계 — 사용자 식별자는 originalTransactionID (재설치·복원에도 동일).
@MainActor
@Observable
final class PurchaseService {
    static let shared = PurchaseService()
    static let productID = "com.nepnep.pro.monthly"

    private(set) var isPro = false
    private(set) var product: Product?
    private(set) var originalTransactionID: UInt64?

    private var updatesTask: Task<Void, Never>?

    /// 앱 시작 시 1회 — 상품 로드 + 권한 판정 + Transaction.updates 상시 구독
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await loadProductIfNeeded()
            await refreshEntitlement()
        }
    }

    func loadProductIfNeeded() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    func refreshEntitlement() async {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                isPro = true
                originalTransactionID = transaction.originalID
                return
            }
        }
        isPro = false
        originalTransactionID = nil
    }

    /// true = 구매 완료(프로 전환), false = 취소·보류
    func purchase() async throws -> Bool {
        await loadProductIfNeeded()
        guard let product else { throw PurchaseError.productUnavailable }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PurchaseError.verificationFailed
            }
            await transaction.finish()
            await refreshEntitlement()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// 서버 검증용 JWS (07-m5 §1) — 현재 유효한 구독 트랜잭션의 서명 원문
    func currentJWS() async -> String? {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                return entitlement.jwsRepresentation
            }
        }
        return nil
    }

    /// F8-4 구매 복원
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    enum PurchaseError: LocalizedError {
        case productUnavailable
        case verificationFailed

        var errorDescription: String? {
            switch self {
            case .productUnavailable: return "지금은 상품 정보를 불러올 수 없어요. 잠시 후 다시 시도해 주세요."
            case .verificationFailed: return "구매 확인에 실패했어요. 구매 복원을 시도해 주세요."
            }
        }
    }
}
