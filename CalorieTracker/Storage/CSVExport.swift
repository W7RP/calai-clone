import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum CSVExport {
    struct Row: Sendable {
        let date: Date
        let meal: String
        let food: String
        let grams: Double
        let macros: Macros
        let source: String
    }

    static let header = "date,time,meal,food,grams,kcal,protein_g,carbs_g,fat_g,source"

    /// ISO dates and dot decimals regardless of the phone's locale, so spreadsheets parse it the same everywhere.
    static func csv(_ rows: [Row], timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let lines = rows.sorted { $0.date < $1.date }.map { row in
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: row.date)
            let date = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            return [date, time, row.meal, escape(row.food), number(row.grams), number(row.macros.kcal),
                    number(row.macros.protein), number(row.macros.carbs), number(row.macros.fat), row.source]
                .joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}

/// A CSV file for ShareLink.
struct CSVFile: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appending(path: file.filename)
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
