import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CSVViewModel()
    @State private var didAttemptLoad = false

    private let csvURL = URL(
        fileURLWithPath: "/Users/pavelsavvateev/Downloads/taiturka.csv"
    )

    var body: some View {
        NavigationStack {
            List {
                Section("Результат") {
                    Text("Файл: \(viewModel.sourceFileName ?? csvURL.lastPathComponent)")
                    Text("Абонентских записей: \(viewModel.records.count)")
                    Text("Многоквартирных домов: \(viewModel.apartmentBuildings.count)")
                    Text("Жилых домов: \(viewModel.residentialHouseCount)")
                    Text(
                        "МКД с низким проникновением (менее 1/3): " +
                        "\(viewModel.apartmentBuildings.count)"
                    )
                }

                if viewModel.isLoading {
                    Section {
                        ProgressView("Запрашиваем DaData…")
                    }
                }

                if let apiWarning = viewModel.apiWarning {
                    Section("Предупреждение") {
                        Text(apiWarning)
                            .foregroundStyle(.orange)
                    }
                }

                if !viewModel.apartmentBuildings.isEmpty {
                    Section("Многоквартирные дома") {
                        ForEach(viewModel.apartmentBuildings) { house in
                            let apartments = house.apartmentCount ?? 0
                            let penetration = apartments > 0
                                ? Double(house.subscriberCount) / Double(apartments)
                                : nil

                            VStack(alignment: .leading, spacing: 5) {
                                Text(house.address)
                                    .font(.headline)

                                Text("Квартир: \(apartments)")
                                Text("Абонентов со статусом «обычный»: \(house.subscriberCount)")

                                if let penetration {
                                    Text(
                                        "Проникновение: " +
                                        penetration.formatted(
                                            .percent.precision(.fractionLength(1))
                                        )
                                    )
                                    .foregroundStyle(.secondary)
                                } else {
                                    Text("Проникновение: нет данных о количестве квартир")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }


                if let fileError = viewModel.fileError {
                    Section("Ошибка") {
                        Text(fileError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Дома и абоненты")
            .task {
                guard !didAttemptLoad else { return }
                didAttemptLoad = true
                await viewModel.loadCSV(from: csvURL)
            }
        }
    }
}

#Preview {
    ContentView()
}
