import LocalAuthentication
import Combine

@MainActor final class AppLock: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published var message: String?
    private var generation = 0

    func lock() { generation += 1; isUnlocked = false }

    func unlock() async {
        guard !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        message = nil
        let request = generation
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "キャンセル"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "記録を保護するため、iPhoneの設定でパスコードを有効にしてください。"; return
        }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: "あなたの健康記録を開きます")
            if request == generation { isUnlocked = success }
        } catch { message = "ロック解除を完了できませんでした。もう一度お試しください。" }
    }
}
