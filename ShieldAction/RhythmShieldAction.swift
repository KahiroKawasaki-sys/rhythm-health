import ManagedSettings
import Foundation

/// シールドのボタン。主「やめておく」は記録して閉じる。副「理由を選んで開く」は通知からRhythmの目的選択へ進ませる。
final class RhythmShieldAction: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) { respond(action, completionHandler) }
    override func handle(action: ShieldAction, for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) { respond(action, completionHandler) }
    override func handle(action: ShieldAction, for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) { respond(action, completionHandler) }

    private func respond(_ action: ShieldAction, _ completion: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            _ = try? GateFiles.append(GateEvent(date: .now, kind: .stayedAway))
            completion(.close)
        case .secondaryButtonPressed:
            GateNotice.postGateRequest { completion(.close) }
        @unknown default:
            completion(.none)
        }
    }
}
