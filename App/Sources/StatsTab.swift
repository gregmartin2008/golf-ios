import CaddieCore
import SwiftUI

/// Statistics over recent rounds.
struct StatsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var limit = 10

    var body: some View {
        let report = model.stats(limit: limit == 0 ? nil : limit)
        NavigationStack {
            List {
                Section {
                    Picker("Rounds", selection: $limit) {
                        Text("Last 5").tag(5)
                        Text("Last 10").tag(10)
                        Text("Last 20").tag(20)
                        Text("All").tag(0)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(coverage(report))
                }
                if report.holes == 0 {
                    Section {
                        Text("Finish a round in Caddie to see statistics. Scores read from GHIN have totals only, so they count toward the handicap but not here.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    scoring(report)
                    gained(report)
                    driving(report)
                    approach(report)
                    putting(report)
                    shortGame(report)
                    clubs(report)
                }
            }
            .navigationTitle("Stats")
        }
    }

    private func coverage(_ report: StatsReport) -> String {
        if report.rounds == 0 { return "" }
        return "\(report.rounds) rounds, \(report.holes) holes."
    }

    private func scoring(_ report: StatsReport) -> some View {
        Section("Scoring") {
            StatRow(label: "Average score", value: Format.one(report.averageScore),
                    detail: report.averageToPar.map { "\(Format.one($0)) over par" } ?? "")
            StatRow(label: "Best / worst", value: bestWorst(report))
            StatRow(label: "Par 3 average", value: Format.two(report.averagePar3))
            StatRow(label: "Par 4 average", value: Format.two(report.averagePar4))
            StatRow(label: "Par 5 average", value: Format.two(report.averagePar5))
            StatRow(label: "Birdies or better", value: share(report.eagles + report.birdies, of: report.holes))
            StatRow(label: "Pars", value: share(report.pars, of: report.holes))
            StatRow(label: "Bogeys", value: share(report.bogeys, of: report.holes))
            StatRow(label: "Doubles or worse", value: share(report.doubles + report.worse, of: report.holes))
            StatRow(label: "Penalties per round", value: Format.one(report.penaltiesPerRound))
        }
    }

    private func bestWorst(_ report: StatsReport) -> String {
        guard let best = report.bestScore, let worst = report.worstScore else { return "–" }
        return "\(best) / \(worst)"
    }

    private func share(_ count: Int, of total: Int) -> String {
        guard total > 0 else { return "–" }
        return "\(Int((Double(count) / Double(total) * 100).rounded()))%"
    }

    @ViewBuilder
    private func gained(_ report: StatsReport) -> some View {
        if report.strokesGainedRounds > 0 {
            Section {
                ForEach(StrokesGained.Category.allCases, id: \.self) { category in
                    StatRow(label: category.label, value: Format.gained(report.strokesGainedPerRound(category)))
                }
                StatRow(label: "Total", value: Format.gained(report.strokesGainedTotalPerRound))
            } header: {
                Text("Strokes gained per round")
            } footer: {
                Text("Against the PGA Tour baseline, so most numbers are negative. The largest negative number is where the most strokes are being lost. Only mapped holes count.")
            }
        }
    }

    private func driving(_ report: StatsReport) -> some View {
        Section("Driving") {
            StatRow(label: "Fairways hit", value: Format.percent(report.fairways), detail: Format.ratio(report.fairways))
            StatRow(label: "Missed left", value: "\(report.missLeft)")
            StatRow(label: "Missed right", value: "\(report.missRight)")
            StatRow(label: "Penalties off the tee", value: "\(report.teePenalties)")
        }
    }

    private func approach(_ report: StatsReport) -> some View {
        Section("Approach") {
            StatRow(label: "Greens in regulation", value: Format.percent(report.greens), detail: Format.ratio(report.greens))
            StatRow(label: "On par 3s", value: Format.percent(report.greensPar3), detail: Format.ratio(report.greensPar3))
            StatRow(label: "On par 4s", value: Format.percent(report.greensPar4), detail: Format.ratio(report.greensPar4))
            StatRow(label: "On par 5s", value: Format.percent(report.greensPar5), detail: Format.ratio(report.greensPar5))
            StatRow(label: "After hitting the fairway", value: Format.percent(report.greensFromFairway))
            StatRow(label: "After missing the fairway", value: Format.percent(report.greensFromMiss))
            StatRow(label: "Misses: short / long", value: "\(report.approachShort) / \(report.approachLong)")
            StatRow(label: "Misses: left / right", value: "\(report.approachLeft) / \(report.approachRight)")
        }
    }

    private func putting(_ report: StatsReport) -> some View {
        Section("Putting") {
            StatRow(label: "Putts per round", value: Format.one(report.puttsPerRound))
            StatRow(label: "Putts per green in regulation", value: Format.two(report.puttsPerGIR))
            StatRow(label: "One-putts", value: Format.percent(report.onePutts))
            StatRow(label: "Three-putts", value: Format.percent(report.threePutts), detail: Format.ratio(report.threePutts))
            StatRow(label: "Average first putt", value: report.averageFirstPuttFeet.map { Format.one($0) + " ft" } ?? "–")
            ForEach(report.puttBuckets) { bucket in
                if bucket.holed.chances > 0 {
                    StatRow(label: "Holed from \(bucket.label)", value: Format.percent(bucket.holed), detail: Format.ratio(bucket.holed))
                }
            }
        }
    }

    private func shortGame(_ report: StatsReport) -> some View {
        Section("Short game") {
            StatRow(label: "Scrambling", value: Format.percent(report.scrambling), detail: Format.ratio(report.scrambling))
            StatRow(label: "Up and down", value: Format.percent(report.upAndDowns), detail: Format.ratio(report.upAndDowns))
            StatRow(label: "Sand saves", value: Format.percent(report.sandSaves), detail: Format.ratio(report.sandSaves))
            StatRow(label: "Chips per round", value: Format.one(report.chipsPerRound))
        }
    }

    @ViewBuilder
    private func clubs(_ report: StatsReport) -> some View {
        if !report.clubs.isEmpty {
            Section {
                ForEach(report.clubs) { club in
                    StatRow(label: club.club,
                            value: Format.distance(yards: club.averageYards, meters: model.settings.useMeters) + " " + Format.unit(model.settings.useMeters),
                            detail: "\(club.shots) shots, longest \(Format.distance(yards: club.longestYards, meters: model.settings.useMeters))")
                }
            } header: {
                Text("Club distances")
            } footer: {
                Text("Average of mapped full shots: from the tee, fairway or rough, more than 60 yards out, with a club chosen.")
            }
        }
    }
}
