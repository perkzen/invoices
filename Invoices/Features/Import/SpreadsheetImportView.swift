import SwiftData
import SwiftUI

/// The import sheet: a spreadsheet of issued invoices on its way into the
/// ledger, in up to three steps — match the columns, add the clients the
/// book does not know, review what will be recorded. Steps with nothing to
/// do are skipped, so the app's own export goes straight to the review.
///
/// A sheet rather than a screen because the last step writes to the book in
/// bulk: the user is meant to look before that happens, and nothing else in
/// the window should change under them while they do.
struct SpreadsheetImportView: View {
    @State private var session: ImportSession
    let onFinish: ([Invoice]) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    init(file: SpreadsheetFile, existing: InvoiceImport.Existing, onFinish: @escaping ([Invoice]) -> Void) {
        _session = State(initialValue: ImportSession(filename: file.name, grid: file.grid, existing: existing))
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 900, height: 680)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Import invoices")
                    .font(.title2.weight(.semibold))
                Label(session.filename, systemImage: "tablecells")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 24)
            StepIndicator(steps: session.steps, current: session.step)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch session.step {
        case .columns:
            ImportColumnsStep(session: session)
        case .clients:
            ImportClientsStep(session: session)
        case .review:
            ImportReviewStep(session: session)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if session.previousStep != nil {
                Button("Back") { session.goBack() }
            }
            if session.nextStep != nil {
                Button("Continue") { session.goForward() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.canProceed)
            } else {
                Button(importTitle, action: record)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.canProceed)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var importTitle: String {
        let count = session.plan.rows.count
        return count == 0 ? String(localized: "Import") : String(localized: "Import \(count) invoices")
    }

    private func record() {
        let recorded = Ledger(context).record(
            session.plan.rows,
            newClients: session.newClients,
            lineDescription: session.lineDescription
        )
        dismiss()
        onFinish(recorded)
    }
}

/// Where the user is in the sheet. The numbers are the order the steps
/// happen in, which is the one thing a first-time importer wants to know.
private struct StepIndicator: View {
    let steps: [ImportSession.Step]
    let current: ImportSession.Step

    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(steps.enumerated()), id: \.element) { offset, step in
                HStack(spacing: 7) {
                    marker(for: step, number: offset + 1)
                    Text(step.title)
                        .font(.callout.weight(step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(current.title)"))
    }

    @ViewBuilder
    private func marker(for step: ImportSession.Step, number: Int) -> some View {
        let done = step < current
        ZStack {
            Circle()
                .fill(step == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: String(number))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(step == current ? .white : .secondary)
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// A picked file, read into a grid — what opens the sheet.
struct SpreadsheetFile: Identifiable {
    let id = UUID()
    var name: String
    var grid: Spreadsheet.Grid
}
