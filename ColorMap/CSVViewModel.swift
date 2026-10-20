import Combine
import Foundation

@MainActor
final class CSVViewModel: ObservableObject {
    @Published private(set) var records: [StatusRecord] = []
    @Published private(set) var houses: [HouseSummary] = []
    @Published private(set) var sourceFileName: String?
    @Published private(set) var isLoading = false
    @Published private(set) var fileError: String?
    @Published private(set) var apiWarning: String?

    private let dadataService = DadataService()

    var statusCounts: [StatusCount] {
        Dictionary(grouping: records, by: \.status)
            .map { status, records in
                StatusCount(status: status, count: records.count)
            }
            .sorted {
                if $0.count != $1.count {
                    return $0.count > $1.count
                }

                return $0.status.localizedCaseInsensitiveCompare($1.status)
                    == .orderedAscending
            }
    }

    /// Все дома, которые DaData определила как многоквартирные.
    var apartmentBuildings: [HouseSummary] {
        houses
            .filter(\.isApartmentBuilding)
            .sorted {
                $0.address.localizedCaseInsensitiveCompare($1.address)
                    == .orderedAscending
            }
    }

    /// Остальные дома, включая дома с неопределённым типом.
    var residentialHouseCount: Int {
        houses.filter { !$0.isApartmentBuilding }.count
    }

    /// Число домов, для которых DaData вернула ровно одну квартиру.
    var knownOtherHouseCount: Int {
        houses.filter(\.isKnownNonApartmentBuilding).count
    }

    /// Число домов, для которых DaData не вернула количество квартир.
    var unknownHouseCount: Int {
        houses.filter {
            !$0.isApartmentBuilding && !$0.isKnownNonApartmentBuilding
        }.count
    }

    func loadCSV(from url: URL) async {
        isLoading = true
        fileError = nil
        apiWarning = nil
        houses = []

        defer {
            isLoading = false
        }

        do {
            records = try CSVReader.read(from: url)
            sourceFileName = url.lastPathComponent
        } catch {
            fileError = error.localizedDescription
            return
        }

        // Группируем абонентские записи по адресу дома — без квартиры.
        let groupedRecords = Dictionary(
            grouping: records.filter { !$0.dadataQuery.isEmpty },
            by: { normalize($0.dadataQuery) }
        )

        guard dadataService.isConfigured else {
            houses = groupedRecords.map { key, clients in
                HouseSummary(
                    id: key,
                    address: clients.first?.dadataQuery ?? key,
                    apartmentCount: nil,
                    subscriberCount: ordinarySubscriberCount(in: clients)
                )
            }

            apiWarning = """
            Не заданы ключи DaData. Адреса загружены, но определить тип домов не удалось.
            """
            return
        }

        var summariesByHouseID: [String: HouseSummary] = [:]
        var failedRequests = 0

        for (queryKey, clients) in groupedRecords.sorted(by: { $0.key < $1.key }) {
            guard let query = clients.first?.dadataQuery else {
                continue
            }

            let ordinaryCount = ordinarySubscriberCount(in: clients)

            do {
                let lookup = try await dadataService.lookupHouse(address: query)

                // Если DaData вернула ФИАС-ID, используем его для объединения
                // вариантов записи одного и того же дома.
                let houseID = lookup.houseFiasId?.lowercased() ?? queryKey
                let displayAddress = lookup.address ?? query

                if var existing = summariesByHouseID[houseID] {
                    existing.subscriberCount += ordinaryCount

                    if existing.apartmentCount == nil {
                        existing.apartmentCount = lookup.apartmentCount
                    }

                    summariesByHouseID[houseID] = existing
                } else {
                    summariesByHouseID[houseID] = HouseSummary(
                        id: houseID,
                        address: displayAddress,
                        apartmentCount: lookup.apartmentCount,
                        subscriberCount: ordinaryCount
                    )
                }
            } catch {
                failedRequests += 1

                // Сохраняем адрес и число абонентов даже при ошибке DaData.
                summariesByHouseID[queryKey] = HouseSummary(
                    id: queryKey,
                    address: query,
                    apartmentCount: nil,
                    subscriberCount: ordinaryCount
                )
            }
        }

        houses = summariesByHouseID.values.sorted {
            $0.address.localizedCaseInsensitiveCompare($1.address)
                == .orderedAscending
        }

        if failedRequests > 0 {
            apiWarning = """
            Не удалось получить ответ DaData для \(failedRequests) адресов. \
            Для них тип дома считается неопределённым.
            """
        }
    }

    private func ordinarySubscriberCount(in records: [StatusRecord]) -> Int {
        records.filter {
            $0.status
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare("обычный") == .orderedSame
        }.count
    }

    private func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
