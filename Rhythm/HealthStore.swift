import HealthKit
import Foundation
import Combine

@MainActor final class HealthStore: ObservableObject {
    @Published private(set) var weights: [Date: Double] = [:]
    @Published private(set) var sleep: [Date: Int] = [:]
    /// 1時間ごとの歩数（開始時刻→歩）。過去30日と今日。
    @Published private(set) var stepsHourly: [Date: Double] = [:]
    @Published private(set) var lastSync: Date?
    @Published private(set) var isLoading = false
    @Published var message: String?
    @Published private(set) var hasRequested = UserDefaults.standard.bool(forKey: "healthRequested")
    @Published private(set) var loadedStart: Date?
    private var wantedStart: Date?
    private let store = HKHealthStore()
    private var weightType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    /// v1.2で歩数を追加。接続済みの人にも一度だけ歩数の許可を尋ねる。
    private var stepsRequested: Bool {
        get { UserDefaults.standard.bool(forKey: "healthStepsRequested") }
        set { UserDefaults.standard.set(newValue, forKey: "healthStepsRequested") }
    }

    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "この端末ではAppleヘルスケアを利用できません。iPhone実機でお試しください。"; return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [weightType, sleepType, stepType])
            hasRequested = true
            stepsRequested = true
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
        if !stepsRequested {
            stepsRequested = true
            try? await store.requestAuthorization(toShare: [], read: [stepType])
        }
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
        weights = [:]; sleep = [:]; stepsHourly = [:]; lastSync = nil; loadedStart = nil; message = nil
        let now = Date.now
        let days = HealthMath.days(from: first, through: now)
        let start = Calendar.current.date(byAdding: .day, value: -1, to: days[0])!
        do {
            async let weightQuery = samples(type: weightType, start: start, end: now)
            async let sleepQuery = samples(type: sleepType, start: start, end: now)
            let (weightSamples, sleepSamples) = try await (weightQuery, sleepQuery)
            // 歩数は未許可でも体重・睡眠を消さないよう、失敗を切り離す。
            let today = Calendar.current.startOfDay(for: now)
            stepsHourly = (try? await hourlySteps(start: Calendar.current.date(byAdding: .day, value: -30, to: today) ?? today,
                end: now)) ?? [:]
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
            if weights.isEmpty && sleep.isEmpty && stepsHourly.isEmpty {
                message = "読み取れるデータがありません。ヘルスケアに記録があるか、体重・睡眠・歩数の読み取りが許可されているか確認してください。"
            }
        } catch { message = "取得できませんでした。端末のロックを解除して、もう一度更新してください。\(error.localizedDescription)" }
    }

    private func hourlySteps(start: Date, end: Date) async throws -> [Date: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: stepType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []),
                options: .cumulativeSum, anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: DateComponents(hour: 1))
            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                var values: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity() { values[statistics.startDate] = sum.doubleValue(for: .count()) }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
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
