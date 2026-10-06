import DeviceActivity
import Foundation

/// 解除の終わりにシールドを戻し、対象アプリの合計が到達ラインを越えたことを記録する。
final class RhythmMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == .rhythmUnlock else { return }
        GateShield.restoreIfDue()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == .rhythmDaily, let minutes = event.reachMinutes else { return }
        let now = Date.now
        // 記録は完全保護のため、iPhoneがロック中なら書けずに見送る（おおよその値として扱う）。
        _ = try? GateFiles.append(GateEvent(date: now, kind: .reach, minutes: minutes)) {
            !GateMath.shouldRecordReach(minutes, at: now, $0)
        }
    }
}
