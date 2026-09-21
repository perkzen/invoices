import SwiftUI

/// Which column holds what. Guessed from the headings; shown for the user
/// to confirm or correct when a required one could not be found.
struct ImportColumnsStep: View {
    @Bindable var session: ImportSession

    var body: some View {
        Form {
            Section("Required") {
                ForEach(InvoiceImport.Field.allCases.filter(\.isRequired)) { field in
                    picker(for: field)
                }
            }
            Section {
                ForEach(InvoiceImport.Field.allCases.filter { !$0.isRequired }) { field in
                    picker(for: field)
                }
            } header: {
                Text("Filled in when missing")
            } footer: {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("The first rows of the file") {
                FilePreview(rows: session.previewRows, columns: session.columns)
                    .frame(height: 176)
            }
        }
        .formStyle(.grouped)
    }

    private func picker(for field: InvoiceImport.Field) -> some View {
        Picker(field.title, selection: binding(for: field)) {
            Text("Not in the file")
                .tag(Int?.none)
            Divider()
            ForEach(session.columns) { column in
                Text(label(for: column)).tag(Int?.some(column.index))
            }
        }
    }

    private var footer: String {
        let missing = session.mapping.missingFields
        if missing.isEmpty {
            return String(localized: "A missing due date is filled in from the payment term, a missing date of service from the invoice date, and an invoice without a payment date is recorded as unpaid.")
        }
        return String(localized: "Still to match: \(missing.map(\.title).joined(separator: ", ")). Without them a row cannot be recorded as an issued invoice.")
    }

    /// "B · Invoice no.  (2026-001)" — letter, heading, and a value under it,
    /// so a column can be told apart even when the headings say nothing.
    private func label(for column: InvoiceImport.Column) -> String {
        var parts = [column.letter]
        if !column.heading.isEmpty { parts.append(column.heading) }
        var label = parts.joined(separator: " · ")
        if !column.sample.isEmpty { label += "  (\(column.sample))" }
        return label
    }

    private func binding(for field: InvoiceImport.Field) -> Binding<Int?> {
        Binding(
            get: { session.mapping.columns[field] },
            set: { column in
                // One column means one thing: choosing it here takes it away
                // from whichever field held it.
                if let column, let holder = session.mapping.columns.first(where: { $0.value == column })?.key,
                   holder != field {
                    session.mapping.columns[holder] = nil
                }
                session.mapping.columns[field] = column
            }
        )
    }
}

/// The top of the file as a table, headed by the column letters, with the
/// heading row set in bold.
private struct FilePreview: View {
    let rows: [ImportSession.PreviewRow]
    let columns: [InvoiceImport.Column]

    var body: some View {
        Table(rows) {
            TableColumnForEach(columns) { column in
                TableColumn(column.letter) { row in
                    Text(row.values.indices.contains(column.index) ? row.values[column.index] : "")
                        .fontWeight(row.isHeader ? .semibold : .regular)
                        .lineLimit(1)
                }
                .width(min: 60, ideal: max(60, CGFloat(min(column.sample.count, 32)) * 7 + 24))
            }
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
    }
}
