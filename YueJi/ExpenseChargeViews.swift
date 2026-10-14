import SwiftUI

struct ExpenseChargeFields: View {
    @Binding var enabled: Bool
    @Binding var subtotal: String
    @Binding var sst: String
    @Binding var service: String
    let currency: String
    let actualMinor: Int?
    let applyTotal: (Int) -> Void
    var sharedFocus: FocusState<ExpenseInputField?>.Binding? = nil
    @FocusState private var localFocus: ExpenseInputField?
    private var focus: FocusState<ExpenseInputField?>.Binding { sharedFocus ?? $localFocus }
    private var draft: ExpenseCharges? { try? ExpenseCharges.draft(currency: currency, subtotal: subtotal, sst: sst, service: service) }
    var body: some View {
        Section {
            Toggle(tr("填写 SST／服务费", "Add SST / service charge", "Isi SST / caj perkhidmatan"), isOn: $enabled)
                .accessibilityIdentifier("transaction.charges.enabled")
            if enabled {
                LabeledContent(tr("税前小计", "Subtotal before charges", "Subtotal sebelum caj")) {
                    TextField("0.00", text: $subtotal).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .focused(focus, equals: .chargeSubtotal)
                        .accessibilityIdentifier("transaction.charges.subtotal")
                }
                percentageRow("SST", value: $sst, field: .sstPercent, identifier: "transaction.charges.sst")
                percentageRow("Service Charge", value: $service, field: .servicePercent, identifier: "transaction.charges.service")
                if let draft, let calculation = try? draft.breakdown() {
                    LabeledContent("SST \(ExpenseCharges.percentText(draft.sstBasisPoints))%", value: Currency.display(calculation.sst, currency))
                    LabeledContent("Service Charge \(ExpenseCharges.percentText(draft.serviceBasisPoints))%", value: Currency.display(calculation.service, currency))
                    LabeledContent(tr("含税费总额", "Total with charges", "Jumlah termasuk caj"), value: Currency.display(calculation.total, currency))
                        .fontWeight(.semibold).monospacedDigit()
                        .accessibilityIdentifier("transaction.charges.total")
                    Button(tr("使用计算出的付款总额", "Use calculated payment total", "Gunakan jumlah bayaran dikira")) {
                        applyTotal(calculation.total)
                    }.disabled(actualMinor == calculation.total)
                        .accessibilityIdentifier("transaction.charges.apply")
                    if let actualMinor, actualMinor != calculation.total {
                        Text(tr("请核对实际付款与含税费总额。", "Check the actual payment against the total with charges.", "Semak bayaran sebenar dengan jumlah termasuk caj."))
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } else if !subtotal.isEmpty || !sst.isEmpty || !service.isEmpty {
                    Text(tr("请填写正数小计及 0–100 的百分比，百分比最多两位小数。", "Enter a positive subtotal and percentages from 0 to 100, with up to two decimal places.", "Isi subtotal positif dan peratus 0 hingga 100, dengan sehingga dua tempat perpuluhan."))
                        .font(.footnote).foregroundStyle(.orange)
                }
            }
        } header: { Text("SST & Service Charge · \(currency)") } footer: {
            if enabled {
                Text(tr("两项都按税前小计计算，各自四舍五入。点“使用计算出的付款总额”可填入含税费金额。物品填写税前单价，税费按比例分摊。", "Both percentages use the subtotal, rounded separately. Use the calculated total to fill the payment amount. Enter items before charges; fees are allocated proportionally.", "Kedua-dua peratus menggunakan subtotal dan dibundarkan berasingan. Gunakan jumlah dikira sebagai bayaran. Isi item sebelum caj; caj diagihkan berkadar."))
            }
        }
    }
    private func percentageRow(_ title: String, value: Binding<String>, field: ExpenseInputField, identifier: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .focused(focus, equals: field).accessibilityIdentifier(identifier)
                    .accessibilityLabel(title + " %")
                Text("%").foregroundStyle(.secondary)
            }
        }
    }
}

struct ExpenseChargeDetails: View {
    @Environment(\.locale) private var locale
    let entry: Expense
    var body: some View {
        let _ = locale.identifier
        if let charges = entry.charges, let calculation = try? charges.breakdown() {
            Section {
                LabeledContent(tr("税前小计", "Subtotal before charges", "Subtotal sebelum caj"), value: Currency.display(charges.subtotal, charges.currency))
                LabeledContent("SST \(ExpenseCharges.percentText(charges.sstBasisPoints))%", value: Currency.display(calculation.sst, charges.currency))
                LabeledContent("Service Charge \(ExpenseCharges.percentText(charges.serviceBasisPoints))%", value: Currency.display(calculation.service, charges.currency))
                LabeledContent(tr("含税费总额", "Total with charges", "Jumlah termasuk caj"), value: Currency.display(calculation.total, charges.currency))
                    .fontWeight(.semibold).monospacedDigit()
            } header: { Text("SST & Service Charge") } footer: {
                Text(tr("两项均按税前小计计算；物品保留税前单价，分类和分账包含按比例分摊的税费。", "Both charges use the subtotal. Items retain base prices; categories and shares include proportionally allocated fees.", "Kedua-dua caj menggunakan subtotal. Item mengekalkan harga asas; kategori dan bahagian termasuk caj diagih berkadar."))
            }
        }
    }
}
