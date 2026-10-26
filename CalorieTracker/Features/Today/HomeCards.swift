import SwiftUI

/// The selected day's week. Filled circle for the selected day, solid ring for days with food logged,
/// dashed for days without. Swipe sideways for other weeks.
struct WeekStrip: View {
    @Binding var selection: Date
    let loggedDays: Set<Date>

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        HStack(spacing: 4) {
            ForEach(CalendarGrid.week(containing: selection), id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selection)
                let isFuture = day > today
                let isLogged = loggedDays.contains(day)
                Button {
                    selection = day
                } label: {
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(day.formatted(.dateTime.day()))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(isSelected ? Color(UIColor.systemBackground) : Color.primary)
                            .background {
                                if isSelected {
                                    Circle().fill(Color.primary)
                                } else {
                                    Circle().strokeBorder(Color.primary.opacity(isLogged ? 0.8 : 0.25),
                                                          style: StrokeStyle(lineWidth: 1.5, dash: isLogged ? [] : [3, 3]))
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(isFuture ? 0.35 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                .accessibilityValue(isLogged ? "Food logged" : "Nothing logged")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -60 { shiftWeek(by: 1) }
            if value.translation.width > 60 { shiftWeek(by: -1) }
        })
    }

    /// Moves a week, never past today.
    private func shiftWeek(by weeks: Int) {
        guard let moved = Calendar.current.date(byAdding: .day, value: weeks * 7, to: selection) else { return }
        withAnimation(.snappy) { selection = min(moved, .now) }
    }
}

/// What's left of the day's calories, with a ring.
struct CalorieCard: View {
    let eaten: Double
    let goal: Double?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                if let goal, goal > 0 {
                    let left = goal - eaten
                    Text(Format.kcal(abs(left)))
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(left >= 0 ? "Calories left" : "Calories over")
                        .font(.subheadline.weight(.medium))
                    Text("\(Format.kcal(eaten)) eaten of \(Format.kcal(goal))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(Format.kcal(eaten))
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                    Text("Calories eaten")
                        .font(.subheadline.weight(.medium))
                    Text("Set a goal in Settings to see what's left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            ProgressRing(progress: goal.map { $0 > 0 ? eaten / $0 : 0 } ?? 0, lineWidth: 10) {
                Image(systemName: "flame.fill")
                    .font(.title2)
            }
            .frame(width: 96, height: 96)
        }
        .card(padding: 20)
        .accessibilityElement(children: .combine)
    }
}

/// One macro: grams left (or eaten, without a goal) and a small ring.
struct MacroCard: View {
    let kind: MacroKind
    let eaten: Double
    let goal: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let goal, goal > 0 {
                let left = goal - eaten
                Text(Format.grams(abs(left)))
                    .font(.title3.bold())
                    .monospacedDigit()
                Text("\(kind.title) \(left >= 0 ? "left" : "over")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(Format.grams(eaten))
                    .font(.title3.bold())
                    .monospacedDigit()
                Text("\(kind.title) eaten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressRing(progress: goal.map { $0 > 0 ? eaten / $0 : 0 } ?? 0, lineWidth: 6) {
                Image(systemName: kind.symbol)
                    .font(.subheadline)
            }
            .frame(width: 58, height: 58)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Carb cycling: which target today uses, switchable for this one day.
struct GymDayCard: View {
    @Binding var isTraining: Bool

    var body: some View {
        Toggle(isOn: $isTraining) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isTraining ? "Gym day" : "Rest day")
                        .font(.subheadline.weight(.semibold))
                    Text(isTraining ? "Higher carb target today" : "Lower carb target today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: isTraining ? "dumbbell.fill" : "bed.double.fill")
            }
        }
        .tint(.primary)
        .card(padding: 14)
    }
}

/// A logged food: photo or source icon, time, calories and macros.
struct FoodCard: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(data: entry.thumbnail, symbol: symbol)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.foodName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.quiet, in: .capsule)
                }
                HStack(alignment: .firstTextBaseline) {
                    Label("\(Format.kcal(entry.kcal)) kcal", systemImage: "flame.fill")
                        .font(.headline)
                    Spacer(minLength: 4)
                    Text(AmountText.describe(grams: entry.grams, entered: entry.entered,
                                             liquid: entry.foodItem?.isLiquid ?? false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .monospacedDigit()
                HStack(spacing: 12) {
                    ForEach(MacroKind.allCases) { kind in
                        Label(Format.grams(kind.value(entry.macros)), systemImage: kind.symbol)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .card(padding: 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the entry to edit it")
    }

    private var symbol: String {
        switch entry.source {
        case .ai: "sparkles"
        case .off: "barcode"
        case .manual: "square.and.pencil"
        }
    }
}

/// An estimate in progress, ready to review, or failed.
struct AnalyzingCard: View {
    let job: AnalysisCenter.Job
    let onReview: () -> Void
    let onRetry: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(data: job.thumbnail, symbol: "sparkles")
                .overlay {
                    if case .working = job.state {
                        RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.35))
                        ProgressView().tint(.white)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(job.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                switch job.state {
                case .working:
                    Text("Analyzing…")
                        .font(.headline)
                    PlaceholderBars()
                case .ready(let estimate):
                    let total = Macros.total(estimate.items.map(\.macros))
                    Label("\(Format.kcal(total.kcal)) kcal", systemImage: "flame.fill")
                        .font(.headline)
                    Text("Ready. Tap to review and log")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                    HStack {
                        Button("Try again", action: onRetry)
                        Button("Discard", role: .destructive, action: onDiscard)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.primary)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 10)
        .contentShape(.rect)
        .onTapGesture {
            if case .ready = job.state { onReview() }
        }
        .contextMenu {
            Button("Discard", systemImage: "trash", role: .destructive, action: onDiscard)
        }
    }
}

/// Grey bars that pulse while the estimate runs.
private struct PlaceholderBars: View {
    @State private var dim = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                Capsule().fill(Theme.quiet).frame(width: index == 0 ? 60 : 40, height: 8)
            }
        }
        .opacity(dim ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.8).repeatForever(), value: dim)
        .onAppear { dim = true }
        .accessibilityHidden(true)
    }
}

/// Meal photo, or a grey square with a symbol when there isn't one.
struct Thumbnail: View {
    let data: Data?
    let symbol: String

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.quiet)
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityHidden(true)
    }
}

/// Saved meals in a row, each logged with one tap.
struct QuickAddStrip: View {
    let meals: [SavedMeal]
    let onLog: (SavedMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved meals")
                .font(.title3.bold())
                .padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(meals) { saved in
                        Button {
                            onLog(saved)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(saved.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(Format.kcal(saved.totals.kcal)) kcal")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                Image(systemName: "plus")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color(UIColor.systemBackground))
                                    .frame(width: 26, height: 26)
                                    .background(Color.primary, in: .circle)
                            }
                            .padding(.leading, 14)
                            .padding(.trailing, 10)
                            .padding(.vertical, 10)
                            .frame(maxWidth: 220)
                            .background(Theme.card, in: .capsule)
                            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Log \(saved.name), \(Format.kcal(saved.totals.kcal)) kcal")
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }
}
