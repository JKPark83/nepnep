import SwiftUI

/// 시작 스플래시 — AppBootstrap.load() 동안 표시.
/// LaunchScreen.storyboard와 같은 배경색·같은 이미지·같은 맞춤(aspect fit)을 써서
/// 런치 스크린 → 이 화면 전환이 끊겨 보이지 않게 한다.
struct SplashView: View {
    var body: some View {
        Color("SplashBackground")
            .overlay {
                Image("SplashArt")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .overlay(alignment: .bottom) {
                ProgressView()
                    .padding(.bottom, 32)
            }
            .ignoresSafeArea()
    }
}
