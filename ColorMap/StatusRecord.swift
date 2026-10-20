import Foundation

struct StatusRecord: Identifiable {
    let id = UUID()

    let status: String
    let settlement: String
    let street: String
    let house: String
    let apartment: String

    /// Адрес дома для DaData — квартира намеренно не включена.
    var dadataQuery: String {
        [settlement, street, house]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

struct StatusCount {
    let status: String
    let count: Int
}

struct HouseSummary: Identifiable {
    let id: String
    let address: String
    var apartmentCount: Int?
    var subscriberCount: Int

    var isApartmentBuilding: Bool {
        (apartmentCount ?? 0) > 1
    }

    /// Наличие одного помещения считаем известным не-МКД.
    /// Ноль или отсутствие данных — неизвестный тип.
    var isKnownNonApartmentBuilding: Bool {
        apartmentCount == 1
    }
}
