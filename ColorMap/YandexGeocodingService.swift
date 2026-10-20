import Foundation

struct GeocodedCoordinate: Codable, Equatable {
    let longitude: Double
    let latitude: Double
}

@MainActor
final class YandexGeocodingService {
    private struct GeocoderResponse: Decodable {
        struct ResponseBody: Decodable {
            struct GeoObjectCollection: Decodable {
                struct FeatureMember: Decodable {
                    struct GeoObject: Decodable {
                        struct Point: Decodable {
                            let position: String

                            enum CodingKeys: String, CodingKey {
                                case position = "pos"
                            }
                        }

                        let point: Point

                        enum CodingKeys: String, CodingKey {
                            case point = "Point"
                        }
                    }

                    let geoObject: GeoObject

                    enum CodingKeys: String, CodingKey {
                        case geoObject = "GeoObject"
                    }
                }

                let featureMembers: [FeatureMember]?

                enum CodingKeys: String, CodingKey {
                    case featureMembers = "featureMember"
                }
            }

            let geoObjectCollection: GeoObjectCollection

            enum CodingKeys: String, CodingKey {
                case geoObjectCollection = "GeoObjectCollection"
            }
        }

        let response: ResponseBody
    }

    private let endpoint = URL(string: "https://geocode-maps.yandex.ru/1.x/")!
    private let apiKey: String
    // In-memory cache avoids duplicate geocoding during this app session.
    private var cache: [String: GeocodedCoordinate] = [:]

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(apiKey: String = ProcessInfo.processInfo.environment["YANDEX_GEOCODER_API_KEY"] ?? "") {
        self.apiKey = apiKey
    }

    func coordinate(for address: String) async throws -> GeocodedCoordinate {
        guard isConfigured else {
            throw YandexGeocodingError.missingAPIKey
        }

        let cacheID = normalize(address)
        if let cachedCoordinate = cache[cacheID] {
            return cachedCoordinate
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw YandexGeocodingError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "geocode", value: address),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "results", value: "1"),
            URLQueryItem(name: "lang", value: "ru_RU")
        ]

        guard let url = components.url else {
            throw YandexGeocodingError.invalidURL
        }

        // Keep a modest request rate. Coordinates are kept only in memory for this run.
        try await Task.sleep(nanoseconds: 250_000_000)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YandexGeocodingError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw YandexGeocodingError.httpError(httpResponse.statusCode)
        }

        let payload = try JSONDecoder().decode(GeocoderResponse.self, from: data)
        guard let position = payload.response.geoObjectCollection.featureMembers?.first?
            .geoObject.point.position
        else {
            throw YandexGeocodingError.addressNotFound
        }

        let values = position.split(whereSeparator: \.isWhitespace)
        guard values.count == 2,
              let longitude = Double(values[0]),
              let latitude = Double(values[1]),
              longitude.isFinite,
              latitude.isFinite,
              (-180...180).contains(longitude),
              (-90...90).contains(latitude)
        else {
            throw YandexGeocodingError.invalidCoordinates
        }

        let coordinate = GeocodedCoordinate(
            longitude: longitude,
            latitude: latitude
        )
        cache[cacheID] = coordinate
        return coordinate
    }

    private func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

}

private enum YandexGeocodingError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case addressNotFound
    case invalidCoordinates
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Не задан ключ YANDEX_GEOCODER_API_KEY. Добавьте его в переменные среды схемы запуска Xcode."
        case .invalidURL:
            return "Не удалось сформировать запрос к Яндекс Геокодеру."
        case .invalidResponse:
            return "Яндекс Геокодер вернул некорректный ответ."
        case .addressNotFound:
            return "Адрес не найден Яндекс Геокодером."
        case .invalidCoordinates:
            return "Яндекс Геокодер вернул некорректные координаты."
        case .httpError(let statusCode):
            return "Ошибка Яндекс Геокодера: HTTP \(statusCode). Проверьте API-ключ и лимиты."
        }
    }
}
