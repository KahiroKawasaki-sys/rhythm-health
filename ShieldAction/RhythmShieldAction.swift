import ManagedSettings
import Foundation

/// シールドのボタン。主「やめておく」は記録して閉じる。副「理由を選んで開く」は通知からRhythmの目的選択へ進ませる。
/// 押した時刻も残し、通知が届かなくても5分以内にRhythmを開けば目的選択が出るようにする。
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
            try? GateFiles.updateShieldPress { $0.record(.stayAway, at: .now) }
            _ = try? GateFiles.append(GateEvent(date: .now, kind: .stayedAway))
            completion(.close)
        case .secondaryButtonPressed:
            try? GateFiles.updateShieldPress { $0.record(.choose, at: .now) }
            GateNotice.postGateRequest { completion(.close) }
        default:
            completion(.none)
        }
    }
}
