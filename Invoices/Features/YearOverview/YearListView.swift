import SwiftData
import SwiftUI

/// The years with issued invoices, newest first, each with what the year
/// added up to. Picking one fills the detail column with its table.
struct YearListView: View {
    @Binding var selection: Int?

    @Query(sort: [SortDescriptor(\Invoice.sequence)]) private var invoices: [Invoice]
    @Query private var profiles: [BusinessProfile]

    private var years: [Int] { YearOverview.availableYears(in: invoices) }

    var body: some View {
        Group {
            if years.isEmpty {
                ContentUnavailableView {
                    Label("No invoices issued", systemImage: "tablecells")
                } description: {
                    Text("The overview lists invoices once the first one has been issued.")
                }
            } else {
                List(selection: $selection) {
                    ForEach(years, id: \.self) { year in
                        YearRow(overview: YearOverview.make(year: year, invoices: invoices, profile: profiles.first))
                            .tag(year)
                    }
                }
            }
        }
        .navigationTitle("Overview")
        // The newest year with invoices, until one is picked. Falling back
        // to the current year would show an empty table every January.
        .onChange(of: years, initial: true) {
            if selection.map({ !years.contains($0) }) ?? true {
                selection = years.first
            }
        }
    }
}

private struct YearRow: View {
    let overview: YearOverview

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: String(overview.year))
                    .font(.headline)
                    .monospacedDigit()
                Text(Formatting.invoiceCount(overview.countedRows.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Formatting.money(overview.total, currencyCode: overview.currencyCode))
                .font(.body.weight(.medium))
                .monospacedDigit()
                .sensitiveValue()
        }
        .padding(.vertical, 3)
    }
}
