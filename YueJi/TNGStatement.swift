import Foundation
import PDFKit
import UIKit
import Vision

/// The sampled TNG transaction-history export has outlined/raster text, including
/// sideways pages. OCR stays on device. Columns, row counts and the continuous
/// wallet balance are checked before anything can reach the ledger.
enum TNGStatementReader {
    struct Line: Sendable {
        let text: String
        let top: Double
        var confidence: Float = 1
    }
    struct Header: Sendable {
        let wallet: String
        let start: Date
        let end: Date
    }
    // Normalized upright coordinates for the sampled eight-column TNG export.
    // Reference/details are deliberately not OCR'd or persisted as identifiers.
    static let columns: [(Double, Double)] = [
        (0.020, 0.092), (0.093, 0.163), (0.165, 0.273),
        (0.349, 0.544), (0.775, 0.860), (0.884, 0.980)
    ]
    static func failure(_ page: Int? = nil) -> Error {
        let message = tr("TNG 交易表识别或逐笔余额校验未通过，请使用完整导出文件；本次未写入账目。", "TNG table recognition or running-balance checks failed. Use the complete export. No entries were written.", "Pengecaman jadual TNG atau semakan baki gagal. Gunakan eksport lengkap. Tiada rekod ditulis.")
        return LedgerError.invalid(page.map { message + " (PDF \($0))" } ?? message)
    }
    static func compact(_ text: String) -> String {
        text.uppercased().filter { !$0.isWhitespace && $0 != "_" }
    }
    /// Restricted OCR glyph normalization in numeric cells only. Never infer a
    /// missing decimal, sign or digit from the expected balance.
    static func numeric(_ text: String) -> String {
        text.filter { !$0.isWhitespace }.replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "|", with: "1")
    }
    static func amount(_ text: String) throws -> Int {
        guard text.uppercased().hasPrefix("RM") else { throw failure() }
        let value = numeric(String(text.dropFirst(2)))
        guard value.range(of: #"^(?:\d+|\d{1,3}(?:,\d{3})+)\.\d{2}$"#, options: .regularExpression) != nil,
              let cents = Int(value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")),
              (0...10_000_000_000).contains(cents) else { throw failure() }
        return cents
    }
    static func date(_ text: String, format: String) throws -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = RHBStatement.calendar; f.timeZone = RHBStatement.calendar.timeZone
        f.dateFormat = format; f.isLenient = false
        guard let result = f.date(from: text) else { throw failure() }
        return result
    }
    static func incoming(_ text: String) throws -> Bool {
        let type = compact(text)
        // The final letter of Wallet touches the adjacent reference column in
        // this export. Accept only that clipped word, never arbitrary substrings.
        if ["RECEIVEFROMWALLET", "RECEIVEFROMWALLE", "RECEIVEFROMWALLEI", "RECEIVEFROMWALLEL", "RECEIVEFROMWALLED", "DUITNOWRECEIVEFROM"].contains(type) { return true }
        if ["TRANSFERTOWALLET", "DUITNOWTRANSFERTO", "PAYMENT", "RFIDPAYMENT", "PAYDIRECTPAYMENT", "DUITNOWQR", "DUITNOWQRTNGD"].contains(type) { return false }
        throw failure()
    }
    static func parse(header: Header, pages: [[[Line]]]) throws -> RHBStatement {
        guard (1...20).contains(pages.count), header.wallet.range(of: #"^\d{10,20}$"#, options: .regularExpression) != nil,
              header.start <= header.end, header.end <= Date(),
              (RHBStatement.calendar.dateComponents([.day], from: header.start, to: header.end).day ?? 999) <= 366 else { throw failure() }
        let accountHash = RHBStatement.hash("TNG:" + header.wallet)
        var rows: [StatementRow] = [], opening: Int?, running: Int?, previousDate = header.start
        var zeroCount = 0
        for (pageIndex, page) in pages.enumerated() {
            try Task.checkCancellation()
            guard page.count == columns.count else { throw failure(pageIndex + 1) }
            let minimum = pageIndex == 0 ? 0.410 : 0.055
            // The fixed footer starts below 0.88; it is never a transaction.
            let table = page.map { lines in lines.filter { $0.top >= minimum && $0.top < 0.88 }.sorted { $0.top < $1.top } }
            let dates = table[0]
            guard !dates.isEmpty, dates.count <= 20,
                  table[1].count == dates.count, table[4].count == dates.count, table[5].count == dates.count else { throw failure(pageIndex + 1) }
            for (index, line) in dates.enumerated() {
                let dateText = numeric(line.text)
                guard line.confidence >= 0.3, dateText.range(of: #"^\d{1,2}/\d{1,2}/\d{4}$"#, options: .regularExpression) != nil else { throw failure(pageIndex + 1) }
                let posted = try date(dateText, format: "d/M/yyyy")
                let bottom = index + 1 < dates.count ? dates[index + 1].top - 0.008 : 0.88
                func cell(_ column: Int) throws -> String {
                    let parts = table[column].filter { $0.top >= line.top - 0.008 && $0.top < bottom }
                    guard !parts.isEmpty, parts.allSatisfy({ $0.confidence >= 0.3 }) else { throw failure(pageIndex + 1) }
                    if [1, 4, 5].contains(column) {
                        guard parts.count == 1, abs(parts[0].top - line.top) < 0.012 else { throw failure(pageIndex + 1) }
                    }
                    return parts.map(\.text).joined(separator: " ")
                }
                guard compact(try cell(1)) == "SUCCESS", posted >= previousDate, posted >= header.start, posted <= header.end else { throw failure(pageIndex + 1) }
                let type = try cell(2), isIncoming = try incoming(type)
                let cents = try amount(cell(4)), balance = try amount(cell(5))
                let before = running ?? (isIncoming ? balance - cents : balance + cents)
                guard before >= 0, before <= 10_000_000_000,
                      before + (isIncoming ? cents : -cents) == balance else { throw failure(pageIndex + 1) }
                if opening == nil { opening = before }
                running = balance; previousDate = posted
                // Successful zero-fee rows still participate in continuity checks,
                // but never create a zero-valued financial posting.
                if cents == 0 { zeroCount += 1; continue }
                let description = try cell(3)
                guard description.count <= 200 else { throw failure(pageIndex + 1) }
                // IDs are independent of OCR merchant spelling and page breaks.
                // Identical monetary/date tuples fail validation rather than collide.
                let identity = [accountHash, String(posted.timeIntervalSince1970), isIncoming ? "in" : "out", String(cents), String(balance)].joined(separator: "|")
                rows.append(StatementRow(id: "statement:" + RHBStatement.hash(identity), date: posted,
                    description: description, serial: "", debit: isIncoming ? 0 : cents, credit: isIncoming ? cents : 0,
                    balance: balance, detail: "TNG · " + type))
            }
        }
        guard let opening, let closing = running else { throw failure() }
        let note = tr("已在本机识别并校验逐笔余额。此交易历史未印期初及总计，期初为推算值；保存后交易待确认，不代表整月核对完成。", "Recognized on device and running balances checked. This history has no printed opening or totals; opening is derived. Saved entries await review, not full-month reconciliation.", "Dikenal pasti setempat dan baki setiap transaksi disemak. Sejarah ini tiada baki awal atau jumlah bercetak; baki awal dikira. Rekod disimpan menunggu semakan, bukan penyelarasan seluruh bulan.")
        let result = RHBStatement(provider: "TNG", verificationNote: note + (zeroCount > 0 ? " (RM0: \(zeroCount))" : ""), reviewOnly: true,
            accountHash: accountHash, suffix: String(header.wallet.suffix(4)), start: header.start, end: header.end, opening: opening, closing: closing,
            debitCount: rows.filter { $0.debit > 0 }.count, creditCount: rows.filter { $0.credit > 0 }.count,
            debitTotal: rows.reduce(0) { $0 + $1.debit }, creditTotal: rows.reduce(0) { $0 + $1.credit }, rows: rows)
        try result.validate()
        return result
    }

    static func recognize(_ image: CGImage, rect: CGRect) throws -> [Line] {
        try Task.checkCancellation()
        let pixels = CGRect(x: rect.minX * CGFloat(image.width), y: rect.minY * CGFloat(image.height),
                            width: rect.width * CGFloat(image.width), height: rect.height * CGFloat(image.height)).integral
        guard let crop = image.cropping(to: pixels) else { throw failure() }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
        try VNImageRequestHandler(cgImage: crop, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Line(text: candidate.string, top: Double(rect.minY + (1 - observation.boundingBox.maxY) * rect.height), confidence: candidate.confidence)
        }.sorted { $0.top < $1.top }
    }
    static func render(_ page: PDFPage, orientation: UIImage.Orientation) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw failure() }
        let scale = 2400 / max(bounds.width, bounds.height)
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        guard let raw = image.cgImage else { throw failure() }
        let rotated = UIImage(cgImage: raw, scale: 1, orientation: orientation)
        let swap = orientation == .right || orientation == .left
        let size = CGSize(width: CGFloat(swap ? raw.height : raw.width), height: CGFloat(swap ? raw.width : raw.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            rotated.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let result = rendered.cgImage else { throw failure() }
        return result
    }
    static func header(_ image: CGImage) throws -> Header {
        guard image.width > image.height,
              abs(Double(image.width) / Double(image.height) - 792.0 / 612.0) < 0.03 else { throw failure() }
        let title = try recognize(image, rect: CGRect(x: 0.30, y: 0.18, width: 0.43, height: 0.055)).map(\.text).joined(separator: " ")
        guard compact(title) == "TNGWALLETTRANSACTIONHISTORY" else { throw failure() }
        let wallet = try recognize(image, rect: CGRect(x: 0.222, y: 0.272, width: 0.32, height: 0.022)).map(\.text).joined()
        let period = try recognize(image, rect: CGRect(x: 0.222, y: 0.356, width: 0.40, height: 0.025)).map(\.text).joined(separator: " ")
        let pattern = #"^(\d{1,2} [A-Za-z]+ \d{4})\s*[-–]\s*(\d{1,2} [A-Za-z]+ \d{4})$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = period as NSString
        guard let match = regex.firstMatch(in: period, range: NSRange(location: 0, length: ns.length)) else { throw failure() }
        // Check the money-column headings before relying on the sampled geometry.
        let amountHeader = try recognize(image, rect: CGRect(x: 0.775, y: 0.394, width: 0.09, height: 0.022)).map(\.text).joined()
        let balanceHeader = try recognize(image, rect: CGRect(x: 0.884, y: 0.394, width: 0.096, height: 0.022)).map(\.text).joined()
        guard compact(amountHeader) == "AMOUNT(RM)", compact(balanceHeader) == "WALLETBALANCE" else { throw failure() }
        return Header(wallet: numeric(wallet), start: try date(ns.substring(with: match.range(at: 1)), format: "d MMMM yyyy"),
                      end: try date(ns.substring(with: match.range(at: 2)), format: "d MMMM yyyy"))
    }
    static func read(_ pages: [PDFPage]) throws -> RHBStatement {
        guard let first = pages.first, (1...20).contains(pages.count) else { throw failure() }
        var selected: UIImage.Orientation?, metadata: Header?
        for orientation: UIImage.Orientation in [.up, .right, .down, .left] {
            try Task.checkCancellation()
            if let found = try? autoreleasepool(invoking: { try header(render(first, orientation: orientation)) }) {
                selected = orientation; metadata = found; break
            }
        }
        guard let selected, let metadata else { throw failure() }
        var recognized: [[[Line]]] = []
        for page in pages {
            try Task.checkCancellation()
            let lines: [[Line]] = try autoreleasepool {
                let image = try render(page, orientation: selected)
                guard image.width > image.height, abs(Double(image.width) / Double(image.height) - 792.0 / 612.0) < 0.03 else { throw failure() }
                return try columns.map { left, right in
                    try recognize(image, rect: CGRect(x: left, y: 0, width: right - left, height: 1))
                }
            }
            recognized.append(lines)
        }
        return try parse(header: metadata, pages: recognized)
    }
}
