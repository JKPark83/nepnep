import Foundation
import Security

/// 전사 서비스 API 키 보관 (#21 후속).
///
/// engines.yml에는 `apiKeyRef: groq`처럼 이름만 적고 실제 키는 여기 넣는다.
/// YAML은 파일 앱에서 보이고 백업에도 실려 나가므로 키를 적어 둘 자리가 아니다.
enum EngineKeychain {
    private static let service = "com.nepnep.engine"

    static func key(for ref: String) -> String? {
        var query = baseQuery(ref)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return nil
        }
        return text
    }

    static func hasKey(for ref: String) -> Bool { key(for: ref) != nil }

    /// 빈 문자열을 주면 지운다 — 설정 화면에서 칸을 비우는 것이 곧 삭제다.
    @discardableResult
    static func setKey(_ value: String, for ref: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deleteKey(for: ref) }

        let data = Data(trimmed.utf8)
        let query = baseQuery(ref)
        let update = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        // 기기가 잠겨 있어도 백그라운드 처리가 키를 읽어야 한다. 다만 백업으로
        // 다른 기기에 딸려 가지는 않게 ThisDeviceOnly로 둔다.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func deleteKey(for ref: String) -> Bool {
        let status = SecItemDelete(baseQuery(ref) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(_ ref: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
    }
}
