import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = CSVViewModel()
    @State private var selectedCSVURL: URL?
    @State private var isImportingCSV = false
    @State private var isExportingKML = false
    @State private var isExportingApartmentBuildingsCSV = false
    @State private var kmlDocument = KMLExportDocument()
    @State private var csvDocument = CSVExportDocument()
    @State private var exportError: String?
    @State private var importError: String?

    var body: some View {
        TabView {
            mapTab
                .tabItem {
                    Label("Карта", systemImage: "map")
                }

            NavigationStack {
                SettingsView {
                    viewModel.reloadAPISettings()
                    guard let selectedCSVURL else { return }
                    Task {
                        await viewModel.loadCSV(from: selectedCSVURL)
                    }
                }
            }
            .tabItem {
                Label("Настройки", systemImage: "gearshape")
            }

            NavigationStack {
                AboutView()
            }
            .tabItem {
                Label("О программе", systemImage: "info.circle")
            }
        }
    }

    private var mapTab: some View {
        NavigationStack {
            List {
                Section("Анализ CSV") {
                    Button {
                        isImportingCSV = true
                    } label: {
                        Label("Выбрать CSV-файл", systemImage: "doc.badge.plus")
                    }
                    .disabled(viewModel.isLoading || viewModel.isGeneratingKML)

                    if let selectedCSVURL {
                        Label(selectedCSVURL.lastPathComponent, systemImage: "doc.text")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Файл не выбран")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        guard let selectedCSVURL else { return }
                        Task {
                            await viewModel.loadCSV(from: selectedCSVURL)
                        }
                    } label: {
                        Label("Начать анализ", systemImage: "play.fill")
                    }
                    .disabled(
                        selectedCSVURL == nil ||
                        viewModel.isLoading ||
                        viewModel.isGeneratingKML
                    )

                    if viewModel.isLoading {
                        ProgressView("Анализируем адреса и данные DaData…")
                    }
                }

                Section("Экспорт") {
                    Button {
                        csvDocument = CSVExportDocument(
                            text: viewModel.apartmentBuildingsCSV
                        )
                        isExportingApartmentBuildingsCSV = true
                    } label: {
                        Label("Выгрузить МКД в CSV", systemImage: "tablecells")
                    }
                    .disabled(
                        viewModel.isLoading ||
                        viewModel.apartmentBuildings.isEmpty
                    )

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
                    .disabled(
                        viewModel.isLoading ||
                        viewModel.isGeneratingKML ||
                        viewModel.records.isEmpty
                    )

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

                if let sourceFileName = viewModel.sourceFileName {
                    Section("Результат анализа") {
                        Text("Файл: \(sourceFileName)")
                        Text("Прочитано записей: \(viewModel.records.count)")
                        Text("Уникальных домов: \(viewModel.houses.count)")
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
            .fileImporter(
                isPresented: $isImportingCSV,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    selectedCSVURL = url
                    importError = nil
                    viewModel.clearLoadedData()
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: $isExportingApartmentBuildingsCSV,
                document: csvDocument,
                contentType: CSVExportDocument.csvContentType,
                defaultFilename: "multifamily_houses"
            ) { result in
                if case .failure(let error) = result {
                    exportError = error.localizedDescription
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
                importError == nil ? "Ошибка экспорта" : "Не удалось выбрать CSV-файл",
                isPresented: Binding(
                    get: { importError != nil || exportError != nil },
                    set: {
                        if !$0 {
                            importError = nil
                            exportError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    importError = nil
                    exportError = nil
                }
            } message: {
                Text(importError ?? exportError ?? "Неизвестная ошибка.")
            }
            .navigationTitle("ColorMap")
        }
    }
}

#Preview {
    ContentView()
}
