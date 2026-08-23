import SwiftUI

@main
struct NepNepWatchApp: App {
    init() {
        // 아이폰이 목록을 내려주거나 파일 전송이 끝났다고 알려줄 때 델리게이트가 이미 붙어 있어야 한다
        WatchSessionClient.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
