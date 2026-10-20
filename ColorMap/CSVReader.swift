import Foundation

enum CSVReader {
    private enum CSVReaderError: Error, LocalizedError {
        case emptyFile
        case missingColumns([String])
        case malformedQuotes

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "CSV-файл пустой."

            case .missingColumns(let columns):
                return """
                Не найдены обязательные столбцы: \(columns.joined(separator: ", ")).
                """

            case .malformedQuotes:
                return "В CSV обнаружены незакрытые кавычки."
            }
        }
    }

    static func read(from url: URL) throws -> [StatusRecord] {
        let hasSecurityAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var text = try String(contentsOf: url, encoding: .utf8)

        // Удаляем BOM, если он есть.
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        // Сначала приводим окончания строк CRLF и CR к LF.
        // Это важно для корректного разбиения CSV на строки.
        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // В taiturka.csv столбцы разделены точкой с запятой.
        let rows = try parse(text, delimiter: ";")

        guard let headerIndex = rows.firstIndex(where: { row in
            row.contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }) else {
            throw CSVReaderError.emptyFile
        }

        // Нормализуем заголовки: «нас. пункт», «нас.пункт» и «нас пункт»
        // будут распознаны как один и тот же столбец.
        var columnIndexes: [String: Int] = [:]

        for (index, name) in rows[headerIndex].enumerated() {
            let key = normalizedHeader(name)
            if columnIndexes[key] == nil {
                columnIndexes[key] = index
            }
        }

        let requiredColumns: [(key: String, displayName: String)] = [
            ("статус", "статус"),
            ("наспункт", "нас. пункт"),
            ("улица", "улица"),
            ("дом", "дом"),
            ("квартира", "квартира")
        ]

        let missingColumns = requiredColumns
            .filter { columnIndexes[$0.key] == nil }
            .map(\.displayName)

        guard missingColumns.isEmpty,
              let statusIndex = columnIndexes["статус"],
              let settlementIndex = columnIndexes["наспункт"],
              let streetIndex = columnIndexes["улица"],
              let houseIndex = columnIndexes["дом"],
              let apartmentIndex = columnIndexes["квартира"]
        else {
            throw CSVReaderError.missingColumns(missingColumns)
        }

        let requiredIndexes = [
            statusIndex,
            settlementIndex,
            streetIndex,
            houseIndex,
            apartmentIndex
        ]
        let lastRequiredIndex = requiredIndexes.max() ?? 0

        var records: [StatusRecord] = []

        for row in rows.dropFirst(headerIndex + 1) {
            let isBlank = row.allSatisfy {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            if isBlank {
                continue
            }

            // Пропускаем строки, в которых не хватает нужных столбцов.
            guard row.count > lastRequiredIndex else {
                continue
            }

            let status = cleaned(row[statusIndex])
            let settlement = cleaned(row[settlementIndex])
            let street = normalizeStreet(
                cleaned(row[streetIndex]),
                settlement: settlement
            )
            let house = cleaned(row[houseIndex])

            let rawApartment = cleaned(row[apartmentIndex])
            let apartment = rawApartment.isEmpty ? "0" : rawApartment

            records.append(
                StatusRecord(
                    status: status,
                    settlement: settlement,
                    street: street,
                    house: house,
                    apartment: apartment
                )
            )
        }

        // Диагностика без вывода адресов и персональных данных.
        print("CSV: разобрано записей — \(records.count)")

        return records
    }

    private static func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedHeader(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace && $0 != "." }
    }

    /// Удаляет содержимое круглых скобок вместе со скобками.
    /// Повторение цикла позволяет обработать и вложенные скобки.
    private static func normalizeStreet(
        _ street: String,
        settlement: String
    ) -> String {
        guard settlement.localizedCaseInsensitiveContains("Тайтурка") else {
            return street
        }
        return street
            .replacingOccurrences(
                of: #"\s*\(\s*Тай-ка\s*\)"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parse(
        _ text: String,
        delimiter: Character
    ) throws -> [[String]] {
        let characters = Array(text)

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if inQuotes {
                if character == "\"" {
                    // Две кавычки подряд внутри поля означают одну кавычку.
                    if index + 1 < characters.count,
                       characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }

                    inQuotes = false
                } else {
                    // Перенос строки внутри кавычек остаётся частью поля.
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                inQuotes = true
            } else if character == delimiter {
                row.append(field)
                field = ""
            } else if character == "\n" {
                row.append(field)
                field = ""
                rows.append(row)
                row = []
            } else {
                field.append(character)
            }

            index += 1
        }

        guard !inQuotes else {
            throw CSVReaderError.malformedQuotes
        }

        // Добавляем последнюю строку, если файл не заканчивается переводом строки.
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }
}
