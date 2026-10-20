import Combine
import Foundation

@MainActor
final class CSVViewModel: ObservableObject {
    @Published private(set) var records: [StatusRecord] = []
    @Published private(set) var houses: [HouseSummary] = []
    @Published private(set) var sourceFileName: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isGeneratingKML = false
    @Published private(set) var fileError: String?
    @Published private(set) var apiWarning: String?
    @Published private(set) var addressErrors: [String] = []
    @Published private(set) var mapErrors: [String] = []

    private var dadataService = DadataService()
    private var yandexGeocodingService = YandexGeocodingService()
    private var houseIDByAddressKey: [String: String] = [:]

    /// All buildings DaData identified as apartment buildings.
    var apartmentBuildings: [HouseSummary] {
        houses
            .filter(\.isApartmentBuilding)
            .sorted {
                $0.address.localizedCaseInsensitiveCompare($1.address)
                    == .orderedAscending
            }
    }

    var apartmentBuildingsCSV: String {
        let header = [
            "Коэффициент проникновения, %",
            "Адрес",
            "Кол-во квартир",
            "Кол-во абонентов"
        ]

        let rows = apartmentBuildings.compactMap { house -> [String]? in
            guard let apartmentCount = house.apartmentCount,
                  apartmentCount > 0
            else {
                return nil
            }

            let penetrationPercent =
                Double(house.subscriberCount) / Double(apartmentCount) * 100
            let formattedPercent = String(
                format: "%.1f",
                locale: Locale(identifier: "ru_RU"),
                penetrationPercent
            )

            return [
                formattedPercent,
                house.address,
                String(apartmentCount),
                String(house.subscriberCount)
            ]
        }

        let csvRows = [header] + rows
        let csvText = csvRows
            .map { $0.map(escapeCSVField).joined(separator: ";") }
            .joined(separator: "\r\n")
        return "\u{FEFF}" + csvText
    }

    func reloadAPISettings() {
        dadataService = DadataService()
        yandexGeocodingService = YandexGeocodingService()
    }

    func loadCSV(from url: URL) async {
        isLoading = true
        fileError = nil
        apiWarning = nil
        addressErrors = []
        mapErrors = []
        houses = []
        houseIDByAddressKey = [:]

        defer { isLoading = false }

        do {
            records = try CSVReader.read(from: url)
            sourceFileName = url.lastPathComponent
        } catch {
            records = []
            fileError = error.localizedDescription
            return
        }

        let groupedRecords = Dictionary(
            grouping: records.filter { !$0.dadataQuery.isEmpty },
            by: { normalize($0.dadataQuery) }
        )

        guard dadataService.isConfigured else {
            var summaries: [HouseSummary] = []
            for (key, clients) in groupedRecords {
                summaries.append(
                    HouseSummary(
                        id: key,
                        address: clients.first?.dadataQuery ?? key,
                        apartmentCount: nil,
                        subscriberCount: ordinarySubscriberCount(in: clients)
                    )
                )
                houseIDByAddressKey[key] = key
                addressErrors.append(
                    "\(clients.first?.dadataQuery ?? key) — ключи DaData не настроены; тип дома не определён."
                )
            }
            houses = sortedHouses(summaries)
            apiWarning = "Ключи DaData не настроены. Типы домов не определены."
            return
        }

        var summariesByHouseID: [String: HouseSummary] = [:]

        for (queryKey, clients) in groupedRecords.sorted(by: { $0.key < $1.key }) {
            guard let query = clients.first?.dadataQuery else { continue }
            let ordinaryCount = ordinarySubscriberCount(in: clients)

            do {
                let lookup = try await dadataService.lookupHouse(address: query)
                guard let normalizedAddress = lookup.address?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !normalizedAddress.isEmpty
                else {
                    addressErrors.append(
                        "\(query) — DaData не вернула нормализованный адрес."
                    )
                    houseIDByAddressKey[queryKey] = queryKey
                    summariesByHouseID[queryKey] = HouseSummary(
                        id: queryKey,
                        address: query,
                        apartmentCount: nil,
                        subscriberCount: ordinaryCount
                    )
                    continue
                }

                let houseID = lookup.houseFiasId?.lowercased() ?? queryKey
                houseIDByAddressKey[queryKey] = houseID

                if var existing = summariesByHouseID[houseID] {
                    existing.subscriberCount += ordinaryCount
                    if existing.apartmentCount == nil {
                        existing.apartmentCount = lookup.apartmentCount
                    }
                    summariesByHouseID[houseID] = existing
                } else {
                    summariesByHouseID[houseID] = HouseSummary(
                        id: houseID,
                        address: normalizedAddress,
                        apartmentCount: lookup.apartmentCount,
                        subscriberCount: ordinaryCount
                    )
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                addressErrors.append("\(query) — \(message)")
                houseIDByAddressKey[queryKey] = queryKey
                summariesByHouseID[queryKey] = HouseSummary(
                    id: queryKey,
                    address: query,
                    apartmentCount: nil,
                    subscriberCount: ordinaryCount
                )
            }
        }

        houses = sortedHouses(Array(summariesByHouseID.values))
        if !addressErrors.isEmpty {
            apiWarning = "DaData не смогла определить тип дома для некоторых адресов; ошибки перечислены ниже."
        }
    }

    /// Geocodes each unique house address and returns a KML document.
    /// Geocoding failures are retained in `mapErrors`; successful placemarks
    /// are still included in a partial export.
    func generateKML() async -> String? {
        mapErrors = []
        guard dadataService.isConfigured else {
            mapErrors = ["Не заданы ключи DaData. Без определения типа домов и числа квартир KML не сформирован."]
            return nil
        }
        guard yandexGeocodingService.isConfigured else {
            mapErrors = ["Не задан ключ YANDEX_GEOCODER_API_KEY. Добавьте его во вкладке «Настройки»."]
            return nil
        }

        isGeneratingKML = true
        defer { isGeneratingKML = false }

        let groupedRecords = Dictionary(
            grouping: records.filter { !$0.dadataQuery.isEmpty },
            by: { normalize($0.dadataQuery) }
        )
        let summariesByID = Dictionary(uniqueKeysWithValues: houses.map { ($0.id, $0) })
        var placemarks: [KMLPlacemark] = []

        // Residential houses get a status-colored mark for each status present.
        // Merge source-address variants that DaData resolved to the same FIAS ID.
        var residentialRecordsByHouseID: [String: [StatusRecord]] = [:]
        for (addressKey, addressRecords) in groupedRecords {
            let houseID = houseIDByAddressKey[addressKey] ?? addressKey
            guard let house = summariesByID[houseID], !house.isApartmentBuilding else {
                continue
            }
            residentialRecordsByHouseID[houseID, default: []].append(contentsOf: addressRecords)
        }

        for (houseID, addressRecords) in residentialRecordsByHouseID.sorted(by: { $0.key < $1.key }) {
            guard let house = summariesByID[houseID] else { continue }
            let address = house.address
            do {
                let coordinate = try await yandexGeocodingService.coordinate(for: address)
                let statusGroups = Dictionary(
                    grouping: addressRecords,
                    by: { normalizedStatus($0.status) }
                )

                for (status, matchingRecords) in statusGroups.sorted(by: { $0.key < $1.key }) {
                    let displayStatus = matchingRecords.first?.status ?? status
                    placemarks.append(
                        KMLPlacemark(
                            name: address,
                            address: address,
                            details: "Жилой дом\nСтатус: \(displayStatus)\nЗаписей со статусом: \(matchingRecords.count)",
                            styleID: KMLGenerator.styleID(forResidentialStatus: displayStatus),
                            coordinate: coordinate
                        )
                    )
                }
            } catch {
                mapErrors.append("\(address) — \(error.localizedDescription)")
            }
        }

        // An apartment building is represented by one larger marker.
        for house in apartmentBuildings {
            guard let apartmentCount = house.apartmentCount, apartmentCount > 0 else {
                mapErrors.append("\(house.address) — DaData не указала количество квартир; МКД пропущен.")
                continue
            }

            do {
                let coordinate = try await yandexGeocodingService.coordinate(for: house.address)
                let penetration = Double(house.subscriberCount) / Double(apartmentCount) * 100
                let styleID = KMLGenerator.styleID(forPenetration: penetration)
                let details = "МКД\nКвартир: \(apartmentCount)\nАбонентов со статусом «обычный»: \(house.subscriberCount)\nПроникновение: \(String(format: "%.1f", penetration))%"

                placemarks.append(
                    KMLPlacemark(
                        name: house.address,
                        address: house.address,
                        details: details,
                        styleID: styleID,
                        coordinate: coordinate
                    )
                )
            } catch {
                mapErrors.append("\(house.address) — \(error.localizedDescription)")
            }
        }

        guard !placemarks.isEmpty else {
            if mapErrors.isEmpty {
                mapErrors.append("Нет объектов для создания KML: адреса не распознаны или отсутствуют.")
            }
            return nil
        }

        return KMLGenerator.generate(placemarks: placemarks)
    }

    private func ordinarySubscriberCount(in records: [StatusRecord]) -> Int {
        records.filter { normalizedStatus($0.status) == "обычный" }.count
    }

    private func normalizedStatus(_ status: String) -> String {
        status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
    }

    private func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private func sortedHouses(_ values: [HouseSummary]) -> [HouseSummary] {
        values.sorted {
            $0.address.localizedCaseInsensitiveCompare($1.address)
                == .orderedAscending
        }
    }

    private func escapeCSVField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
