# Invoices

An invoicing app for one Slovenian sole trader: drafting, issuing and tracking invoices,
and handing the year's figures to the accountant. Slovenian is the language of the printed
documents; English is the language of the code.

## Language

**Invoice**:
A request for payment addressed to a client. Editable while a draft; issuing gives it a
number and fixes its content.
_Avoid_: bill, document

**Draft**:
An invoice not yet issued — unnumbered, editable, and the only kind that may be deleted.

**Issuing**:
Giving a draft the next number in the year's unbroken sequence and locking it.
_Avoid_: sending, publishing

**Cancellation**:
Voiding an issued invoice. It keeps its number, stays in the year overview, and is not
counted.
_Avoid_: deleting, voiding

**Payment reference**:
The reference the client quotes when paying — by default the SI00 model over the invoice
number.

**Client**:
The counterparty an invoice is addressed to. An invoice keeps no copy of it, so a client
with issued invoices stays.
_Avoid_: customer, counterparty

**Business profile**:
The issuer — the one sole proprietor using the app.
_Avoid_: account, user, company

**Line item**:
One row of an invoice: description, quantity, unit, unit price, discount and VAT rate.
_Avoid_: item, row

**VAT registered**:
An issuer that charges VAT. Otherwise invoices carry the exemption clause and no VAT ID.

**Service period**:
The day or the span of days the invoice charges for. Its end decides the month the intro
sentence names.

**Ledger**:
The book of invoices and clients — the one place an invoice's life changes: drafting,
issuing, payment, cancellation, and the rules on what may be deleted.

**Printed invoice**:
Everything the printed invoice shows, fixed as plain values: sentences resolved, columns
chosen, totals computed. The PDF, the live preview and the settings sample are all
rendered from it.

**Invoice template**:
The issuer's own wording and artwork on the printed invoice: logo, line of business, the
three sentences with placeholders, signature.

**Placeholder**:
A `{token}` in a template sentence, filled from the invoice: month, year, client, number,
IBAN, reference, due date.

**Year overview**:
Every issued invoice of one calendar year, as the accountant's spreadsheet lists it.

**Export**:
Saving a rendered document — the PDF of one invoice or the XLSX of a year — through the
save panel.
