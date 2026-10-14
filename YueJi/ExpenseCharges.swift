import Foundation

struct ExpenseCharges: Codable, Equatable {
    var currency: String = "MYR"
    var subtotal: Int
    var sstBasisPoints: Int
    var serviceBasisPoints: Int

    static func draft(currency: String, subtotal: String, sst: String, service: String) throws -> ExpenseCharges {
        let result = ExpenseCharges(currency: currency, subtotal: try Currency.parse(subtotal, code: currency),
                                    sstBasisPoints: try percent(sst), serviceBasisPoints: try percent(service))
        _ = try result.breakdown()
        return result
    }

    static func percent(_ input: String) throws -> Int {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return 0 }
        if text.hasSuffix("%") { text.removeLast(); text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard text.range(of: #"^[0-9]{1,3}(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value <= 100 else {
            throw reviewError("百分比须为 0–100，最多两位小数。", "Enter a percentage from 0 to 100 with up to two decimal places.", "Isi peratus antara 0 hingga 100 dengan sehingga dua tempat perpuluhan.")
        }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
    static func percentText(_ points: Int) -> String {
        NSDecimalNumber(decimal: Decimal(points) / 100).stringValue
    }
    func breakdown() throws -> (sst: Int, service: Int, total: Int) {
        guard Currency.codes.contains(currency), (0...10_000).contains(sstBasisPoints), (0...10_000).contains(serviceBasisPoints) else {
            throw reviewError("请检查 SST 和服务费百分比。", "Check the SST and service percentages.", "Semak peratus SST dan perkhidmatan.")
        }
        let sst = try ReceiptCalculation.percentCharge(base: subtotal, percent: Decimal(sstBasisPoints) / 100)
        let service = try ReceiptCalculation.percentCharge(base: subtotal, percent: Decimal(serviceBasisPoints) / 100)
        return (sst, service, try ReceiptCalculation.total(subtotal: subtotal, tax: sst, service: service, discount: 0))
    }
    func myrSubtotal(foreign: ForeignAmount?) throws -> Int {
        _ = try breakdown()
        if currency == "MYR" { return subtotal }
        guard let foreign, foreign.currency == currency else { throw LedgerError.invalid("币种无效。") }
        return try ForeignAmount(currency: currency, minor: subtotal, quote: foreign.quote).myrCents()
    }
}

/// Distribute whole sen without overflowing integer products or changing item prices.
func allocateChargeTotal(_ total: Int, weights: [Int]) throws -> [Int] {
    guard total > 0, total <= 10_000_000_000, !weights.isEmpty, weights.count <= 100,
          weights.allSatisfy({ $0 > 0 && $0 <= 10_000_000_000 }) else { throw LedgerError.invalid("交易金额或日期无效。") }
    let sum = weights.reduce(0, +)
    var amounts = weights.map { weight -> Int in
        var raw = Decimal(total) * Decimal(weight) / Decimal(sum)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .down)
        return NSDecimalNumber(decimal: rounded).intValue
    }
    var remaining = total - amounts.reduce(0, +)
    for index in amounts.indices where remaining > 0 { amounts[index] += 1; remaining -= 1 }
    guard remaining == 0, amounts.reduce(0, +) == total else { throw LedgerError.invalid("付款或分账数据无效。") }
    return amounts
}

extension Expense {
    var chargeEditsLocked: Bool {
        refunded > 0 || shares.contains { !$0.repayments.isEmpty || !($0.returns ?? []).isEmpty }
    }
    func validateChargeEdit(replacing original: Expense) throws {
        guard charges == original.charges || !original.chargeEditsLocked else {
            throw reviewError("请先撤销退款或还款，再修改 SST 和服务费。", "Undo refunds or repayments before changing SST and service charges.", "Batalkan pulangan atau bayaran balik sebelum menukar SST dan caj perkhidmatan.")
        }
    }
    var itemSubtotalCents: Int { charges.flatMap { try? $0.myrSubtotal(foreign: foreign) } ?? cents }
    /// Financial capacities include charges; the saved items retain their base unit prices.
    var chargedItems: [ExpenseItem] {
        let original = items ?? []
        guard charges != nil, let amounts = try? allocateChargeTotal(cents, weights: original.map(\.cents)) else { return original }
        return zip(original, amounts).map { item, amount in
            var copy = item
            copy.cents = amount
            return copy
        }
    }
    func validateCharges() throws {
        guard let charges else { return }
        let calculation = try charges.breakdown()
        if let foreign {
            guard charges.currency == foreign.currency, calculation.total == foreign.minor,
                  try foreign.myrCents() == cents else { throw chargeTotalMismatch() }
        } else {
            guard charges.currency == "MYR", calculation.total == cents else { throw chargeTotalMismatch() }
        }
    }
}

func chargeTotalMismatch() -> LedgerError {
    reviewError("税前小计加 SST 和服务费必须等于实际付款。请核对金额，或使用计算出的含税总额。", "Subtotal plus SST and service must equal the actual payment. Check the amounts or use the calculated total.", "Subtotal bersama SST dan perkhidmatan mesti sama dengan bayaran sebenar. Semak amaun atau gunakan jumlah dikira.")
}
