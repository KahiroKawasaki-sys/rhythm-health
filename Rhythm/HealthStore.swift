import HealthKit
import Foundation
import Combine

@MainActor final class HealthStore: ObservableObject {
    @Published private(set) var weights: [Date: Double] = [:]
    @Published private(set) var sleep: [Date: Int] = [:]
    @Published private(set) var lastSync: Date?
    @Published private(set) var isLoading = false
    @Published var message: String?
    @Published private(set) var hasRequested = UserDefaults.standard.bool(forKey: "healthRequested")
    @Published private(set) var loadedStart: Date?
    private var wantedStart: Date?
    private let store = HKHealthStore()
    private var weightType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "この端末ではAppleヘルスケアを利用できません。iPhone実機でお試しください。"; return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [weightType, sleepType])
            hasRequested = true
            UserDefaults.standard.set(true, forKey: "healthRequested")
            await refresh()
        } catch { message = "ヘルスケアの接続を完了できませんでした。\(error.localizedDescription)" }
    }

    /// 選んだ期間に必要な範囲まで広げる。狭い期間に戻しても取得済みの範囲は保つ。
    func ensureLoaded(_ period: ReviewPeriod) async {
        let needed = HealthMath.fetchStart(period)
        if let loadedStart, loadedStart <= needed { return }
        await refresh(from: needed)
    }

    func refresh(from requested: Date? = nil) async {
        wantedStart = [requested, wantedStart, HealthMath.fetchStart(.month)].compactMap { $0 }.min()
        guard hasRequested, HKHealthStore.isHealthDataAvailable() else { return }
        // A wider request during loading is kept and run afterwards instead of being dropped.
        guard !isLoading else { return }
        isLoading = true
        var start: Date
        repeat {
            start = wantedStart!
            await load(from: start)
        } while loadedStart != nil && wantedStart! < start
        isLoading = false
    }

    private func load(from first: Date) async {
        // Clear old values: a later refusal must not keep an old HealthKit snapshot visible.
        weights = [:]; sleep = [:]; lastSync = nil; loadedStart = nil; message = nil
        let now = Date.now
        let days = HealthMath.days(from: first, through: now)
        let start = Calendar.current.date(byAdding: .day, value: -1, to: days[0])!
        do {
            async let weightQuery = samples(type: weightType, start: start, end: now)
            async let sleepQuery = samples(type: sleepType, start: start, end: now)
            let (weightSamples, sleepSamples) = try await (weightQuery, sleepQuery)
            weights = HealthMath.latestWeights(weightSamples.compactMap { sample in
                guard let value = sample as? HKQuantitySample else { return nil }
                return TimedWeight(date: value.startDate, kilograms: value.quantity.doubleValue(for: .gramUnit(with: .kilo)))
            })
            let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue]
            let spans = sleepSamples.compactMap { sample -> SleepSpan? in
                guard let value = sample as? HKCategorySample, asleepValues.contains(value.value) else { return nil }
                return SleepSpan(start: value.startDate, end: value.endDate)
            }
            sleep = HealthMath.sleepByDay(spans, days: days)
            lastSync = now
            loadedStart = days[0]
            if weights.isEmpty && sleep.isEmpty {
                message = "読み取れるデータがありません。ヘルスケアに記録があるか、体重・睡眠の読み取りが許可されているか確認してください。"
            }
        } catch { message = "取得できませんでした。端末のロックを解除して、もう一度更新してください。\(error.localizedDescription)" }
    }

    private func samples(type: HKSampleType, start: Date, end: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }
}
