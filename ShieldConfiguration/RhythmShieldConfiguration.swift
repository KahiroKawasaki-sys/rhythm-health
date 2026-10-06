import ManagedSettings
import ManagedSettingsUI
import UIKit

/// シールドの見た目。「開く前に、ひと呼吸」と今日の回数を出す。
final class RhythmShieldConfiguration: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration { make() }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { make() }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { make() }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { make() }

    private func make() -> ShieldConfiguration {
        let green = UIColor(red: 17/255, green: 90/255, blue: 54/255, alpha: 1)
        let ink = UIColor(red: 26/255, green: 41/255, blue: 35/255, alpha: 1)
        let secondary = UIColor(red: 89/255, green: 102/255, blue: 94/255, alpha: 1)
        let background = UIColor(red: 245/255, green: 246/255, blue: 242/255, alpha: 1)
        let subtitle: String
        if let events = try? GateFiles.loadEvents() {
            let counts = GateMath.todayCounts(.now, events)
            subtitle = "今日 開いた\(counts.opened)回・やめた\(counts.stayedAway)回"
        } else {
            subtitle = "今日の回数は、Rhythmで確かめられます。"
        }
        return ShieldConfiguration(backgroundBlurStyle: .systemUltraThinMaterialLight, backgroundColor: background,
            icon: UIImage(systemName: "leaf"),
            title: .init(text: "開く前に、ひと呼吸", color: ink),
            subtitle: .init(text: subtitle, color: secondary),
            primaryButtonLabel: .init(text: "やめておく", color: .white), primaryButtonBackgroundColor: green,
            secondaryButtonLabel: .init(text: "理由を選んで開く", color: green))
    }
}
