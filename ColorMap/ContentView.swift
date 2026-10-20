import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = CSVViewModel()
    @State private var didAttemptLoad = false
    @State private var isExportingKML = false
    @State private var kmlDocument = KMLExportDocument()
    @State private var exportError: String?

    private let csvURL = URL(
        fileURLWithPath: "/Users/pavelsavvateev/Downloads/taiturka.csv"
    )

    var body: some View {
        NavigationStack {
            List {
                Section("Карта") {
                    Button {
                        Task {
                            guard let kml = await viewModel.generateKML() else {
                                exportError = viewModel.mapErrors.joined(separator: "\n\n")
                                return
                            }
                            kmlDocument = KMLExportDocument(text: kml)
                            isExportingKML = true
                        }
                    } label: {
                        Label("Создать и экспортировать KML", systemImage: "map")
                    }
                    .disabled(viewModel.isLoading || viewModel.isGeneratingKML || viewModel.records.isEmpty)

                    if viewModel.isGeneratingKML {
                        ProgressView("Получаем координаты Яндекс Геокодером…")
                    }

                    if !viewModel.mapErrors.isEmpty {
                        Text("Ошибки формирования карты: \(viewModel.mapErrors.count)")
                            .foregroundStyle(.red)
                        ForEach(viewModel.mapErrors.indices, id: \.self) { index in
                            Text(viewModel.mapErrors[index])
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Источник") {
                    Text("Файл: \(viewModel.sourceFileName ?? csvURL.lastPathComponent)")
                    Text("Прочитано записей: \(viewModel.records.count)")
                }

                if viewModel.isLoading {
                    Section {
                        ProgressView("Обрабатываем адреса DaData…")
                    }
                }

                if let apiWarning = viewModel.apiWarning {
                    Section("Предупреждение DaData") {
                        Text(apiWarning)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                }

                Section("Проверка адресов DaData") {
                    Text("Ошибок нормализации: \(viewModel.addressErrors.count)")
                    ForEach(viewModel.addressErrors.indices, id: \.self) { index in
                        Text(viewModel.addressErrors[index])
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }

                if let fileError = viewModel.fileError {
                    Section("Ошибка чтения файла") {
                        Text(fileError)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
            .fileExporter(
                isPresented: $isExportingKML,
                document: kmlDocument,
                contentType: KMLExportDocument.kmlContentType,
                defaultFilename: "colormap_houses"
            ) { result in
                if case .failure(let error) = result {
                    exportError = error.localizedDescription
                }
            }
            .alert(
                "Ошибка экспорта",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "Неизвестная ошибка.")
            }
            .navigationTitle("ColorMap")
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
