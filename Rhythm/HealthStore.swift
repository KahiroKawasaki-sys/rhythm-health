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

    func refresh() async {
        guard hasRequested, !isLoading, HKHealthStore.isHealthDataAvailable() else { return }
        isLoading = true
        defer { isLoading = false }
        // Clear old values: a later refusal must not keep an old HealthKit snapshot visible.
        weights = [:]; sleep = [:]; lastSync = nil; message = nil
        let now = Date.now
        let days = HealthMath.completedDays(count: 56, now: now) + [Calendar.current.startOfDay(for: now)]
        let start = Calendar.current.date(byAdding: .day, value: -1, to: days[0])!
        do {
            let weightSamples = try await samples(type: weightType, start: start, end: now)
            let sleepSamples = try await samples(type: sleepType, start: start, end: now)
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
