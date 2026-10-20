import Foundation

struct DadataHouseLookup: Codable {
    let address: String?
    let houseFiasId: String?
    let apartmentCount: Int?
}

@MainActor
final class DadataService {
    private struct APIResponse: Decodable {
        let result: String?
        let houseFiasId: String?
        let houseFlatCount: Int?

        private enum CodingKeys: String, CodingKey {
            case result
            case houseFiasId = "house_fias_id"
            case houseFlatCount = "house_flat_count"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            result = try? container.decode(String.self, forKey: .result)
            houseFiasId = try? container.decode(
                String.self,
                forKey: .houseFiasId
            )

            if let stringValue = try? container.decode(
                String.self,
                forKey: .houseFlatCount
            ) {
                houseFlatCount = Int(stringValue)
            } else {
                houseFlatCount = try? container.decode(
                    Int.self,
                    forKey: .houseFlatCount
                )
            }
        }
    }

    private let endpoint = URL(
        string: "https://cleaner.dadata.ru/api/v1/clean/address"
    )!

    private let token: String
    private let secret: String
    private var cache: [String: DadataHouseLookup] = [:]

    private static let cacheKey = "DadataHouseLookupCache.v1"

    var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {
        // Configure credentials in Xcode Scheme > Run > Environment Variables.
        token = ProcessInfo.processInfo.environment["DADATA_API_KEY"] ?? ""
        secret = ProcessInfo.processInfo.environment["DADATA_SECRET_KEY"] ?? ""

        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let savedCache = try? JSONDecoder().decode(
               [String: DadataHouseLookup].self,
               from: data
           ) {
            cache = savedCache
        }
    }

    func lookupHouse(address: String) async throws -> DadataHouseLookup {
        guard isConfigured else {
            throw DadataError.missingCredentials
        }

        let cacheID = normalize(address)

        if let cachedResult = cache[cacheID] {
            #if DEBUG
            print("DaData CACHE HIT: \(address)")
            #endif
            return cachedResult
        }

        // Ограничиваем частоту запросов примерно до 15 запросов в секунду.
        try await Task.sleep(nanoseconds: 65_000_000)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(secret, forHTTPHeaderField: "X-Secret")

        let requestBody = try JSONEncoder().encode([address])
        request.httpBody = requestBody

        #if DEBUG
        print("----- DaData REQUEST -----")
        print("URL: \(endpoint.absoluteString)")
        print("Method: POST")
        print("Address: \(address)")
        print(
            "Body: \(String(data: requestBody, encoding: .utf8) ?? "<не UTF-8>")"
        )
        #endif

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            #if DEBUG
            print("DaData NETWORK ERROR: \(error.localizedDescription)")
            #endif
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DadataError.invalidResponse
        }

        #if DEBUG
        print("----- DaData RESPONSE -----")
        print("HTTP status: \(httpResponse.statusCode)")
        print(
            "Body:\n"
                + (String(data: data, encoding: .utf8) ?? "<ответ не UTF-8>")
        )
        print("---------------------------")
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DadataError.httpError(httpResponse.statusCode)
        }

        let apiResults = try JSONDecoder().decode(
            [APIResponse].self,
            from: data
        )
        let apiResult = apiResults.first

        let lookup = DadataHouseLookup(
            address: apiResult?.result,
            houseFiasId: apiResult?.houseFiasId,
            apartmentCount: apiResult?.houseFlatCount
        )

        cache[cacheID] = lookup
        saveCache()

        return lookup
    }

    private func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}

private enum DadataError: LocalizedError {
    case missingCredentials
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Укажите API-ключ и секретный ключ DaData в DadataHouseLookup.swift."

        case .invalidResponse:
            return "DaData вернула некорректный ответ."

        case .httpError(let statusCode):
            return """
            Ошибка DaData: HTTP \(statusCode). Проверьте ключи, тариф и лимиты API.
            """
        }
    }
}
