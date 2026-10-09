import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var journal: JournalStore
    @EnvironmentObject private var health: HealthStore
    @State private var date = Calendar.current.startOfDay(for: Date.now)
    var edit: (Date) -> Void
    private var days: [Date] {
        let recent = HealthMath.completedDays(count: 56) + [Calendar.current.startOfDay(for: .now)]
        return Array(Set(recent + journal.records.map(\.day))).sorted(by: >)
    }
    private var rows: [DailyHealth] {
        HealthMath.resolve(days: days, weights: health.weights, sleep: health.sleep, manual: journal.records).filter { row in
            row.weight != nil || row.sleepMinutes != nil || journal.records.contains { $0.day == row.day }
        }
    }
    /// 今日は途中の値（1時間ごとの合計）、それ以前は1日の値。
    private func steps(on day: Date) -> Double? {
        if let value = health.stepsDaily[day] { return value }
        guard day == Calendar.current.startOfDay(for: .now) else { return nil }
        return HealthMath.dailyTotals(health.stepsHourly)[day]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Surface {
                    DatePicker("記録する日", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                    Button { edit(Calendar.current.startOfDay(for: date)) } label: {
                        Label("この日の記録を開く", systemImage: "square.and.pencil")
                    }.buttonStyle(PrimaryButtonStyle())
                }
                if rows.isEmpty {
                    ContentUnavailableView("最初の1日を残そう", systemImage: "book.closed",
                        description: Text("自動で読み込んだ記録も、手入力もここに並びます。"))
                }
                ForEach(rows) { row in
                    Button { edit(row.day) } label: {
                        Surface {
                            SectionLabel(title: row.day.formatted(.dateTime.month().day().weekday()), detail: "編集 ›")
                            Text("体重 \(row.weight.map { String(format: "%.1f kg", $0) } ?? "—")  ·  睡眠 \(HealthMath.duration(row.sleepMinutes))")
                                .font(.subheadline).multilineTextAlignment(.leading)
                            if let steps = steps(on: row.day) {
                                Text("歩数 \(steps.formatted(.number.precision(.fractionLength(0))))歩").font(.subheadline)
                            }
                            Text("体重：\(row.weight == nil ? "未記録" : row.weightSource) / 睡眠：\(row.sleepMinutes == nil ? "未記録" : row.sleepSource)")
                                .font(.caption).foregroundStyle(Palette.secondary)
                            if let manual = journal.records.first(where: { $0.day == row.day }) {
                                if let minutes = manual.screenMinutes { Text("スマホ \(HealthMath.duration(minutes))（手入力）").font(.subheadline) }
                                if !manual.note.isEmpty { Text(manual.note).font(.footnote).foregroundStyle(Palette.secondary).multilineTextAlignment(.leading) }
                            }
                        }
                    }.buttonStyle(.plain)
                }
                Notice(text: "自動取得は過去56日と今日。手入力は以前の記録も残ります。自動スクリーンタイムは振り返り画面で確認できます。")
            }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(Palette.background).navigationTitle("記録")
    }
}

struct EntryView: View {
    @EnvironmentObject private var journal: JournalStore
    @Environment(\.dismiss) private var dismiss
    let day: Date
    @State private var weight = ""
    @State private var sleepHours = ""
    @State private var sleepMinutes = ""
    @State private var screenHours = ""
    @State private var screenMinutes = ""
    /// v1.1までの体調の値。入力欄はなくしたが、保存時に消さないよう引き継ぐ。
    @State private var mood: Int?
    @State private var note = ""
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                Text(day.formatted(.dateTime.year().month().day().weekday()))
                Text("手入力した項目を優先します。空欄で保存すると、その項目はヘルスケアの値に戻ります。")
                    .font(.footnote).foregroundStyle(Palette.secondary)
            }
            Section("体重") {
                HStack { TextField("例：68.5", text: $weight).keyboardType(.decimalPad).accessibilityLabel("体重"); Text("kg") }
            }
            Section("睡眠時間") {
                DurationFields(hours: $sleepHours, minutes: $sleepMinutes, label: "睡眠")
            }
            Section {
                DurationFields(hours: $screenHours, minutes: $screenMinutes, label: "スマホ")
            } header: { Text("スマホ時間・任意") } footer: {
                Text("Appleの自動レポートとは別の手入力記録です。合算されません。")
            }
            Section("メモ") {
                TextField("例：夜のスマホを早めに切り上げた", text: $note, axis: .vertical).lineLimit(3...6)
                Text("\(note.count)/500文字").font(.caption).foregroundStyle(Palette.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("save-error") } }
            if let error = journal.loadError { Section { Text(error).foregroundStyle(.red) } }
            if journal.records.contains(where: { $0.day == day }) {
                Section {
                    Button("この日の手入力を削除", role: .destructive) { confirmDelete = true }
                        .disabled(journal.loadError != nil)
                }
            }
        }.navigationTitle("記録を入力").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(journal.loadError != nil) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("入力を閉じる") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }.onAppear(perform: load)
            .confirmationDialog("この日の手入力とメモを削除しますか？ ヘルスケアの記録は残ります。", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("手入力を削除", role: .destructive) {
                    do { try journal.delete(day: day); dismiss() } catch { self.error = error.localizedDescription }
                }
            }
    }

    private func load() {
        guard let record = journal.records.first(where: { $0.day == day }) else { return }
        weight = record.weight.map { String(format: "%.1f", $0) } ?? ""
        sleepHours = record.sleepMinutes.map { String($0 / 60) } ?? ""
        sleepMinutes = record.sleepMinutes.map { String($0 % 60) } ?? ""
        screenHours = record.screenMinutes.map { String($0 / 60) } ?? ""
        screenMinutes = record.screenMinutes.map { String($0 % 60) } ?? ""
        mood = record.mood; note = record.note
    }

    private func number(_ text: String) -> String {
        text.applyingTransform(.fullwidthToHalfwidth, reverse: false)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    private func duration(hours: String, minutes: String, label: String) throws -> Int? {
        let h = number(hours), m = number(minutes)
        if h.isEmpty && m.isEmpty { return nil }
        guard let hour = Int(h.isEmpty ? "0" : h), let minute = Int(m.isEmpty ? "0" : m),
              (0...24).contains(hour), (0...59).contains(minute), hour * 60 + minute <= 1440 else {
            throw JournalStore.StoreError.message("\(label)の時間・分を確認してください（0〜24時間、分は0〜59）。")
        }
        return hour * 60 + minute
    }

    private func save() {
        do {
            let rawWeight = number(weight).replacingOccurrences(of: ",", with: ".")
            let kg = rawWeight.isEmpty ? nil : Double(rawWeight)
            if !rawWeight.isEmpty && kg == nil { throw JournalStore.StoreError.message("体重を数字で入力してください。") }
            let record = DayRecord(day: day, weight: kg,
                sleepMinutes: try duration(hours: sleepHours, minutes: sleepMinutes, label: "睡眠"),
                screenMinutes: try duration(hours: screenHours, minutes: screenMinutes, label: "スマホ"),
                mood: mood, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            try journal.upsert(record)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct DurationFields: View {
    @Binding var hours: String
    @Binding var minutes: String
    var label: String
    var body: some View {
        HStack {
            TextField("0", text: $hours).keyboardType(.numberPad).accessibilityLabel("\(label)の時間")
            Text("時間")
            TextField("0", text: $minutes).keyboardType(.numberPad).accessibilityLabel("\(label)の分")
            Text("分")
        }
    }
}
