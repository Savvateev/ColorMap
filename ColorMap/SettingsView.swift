import Combine
import SwiftUI

@MainActor
final class APISettingsViewModel: ObservableObject {
    @Published var yandexKey: String
    @Published var dadataKey: String
    @Published var dadataSecret: String
    @Published private(set) var savedMessage: String?
    @Published private(set) var errorMessage: String?

    init() {
        yandexKey = APIKeyStore.load(.yandexGeocoder)
        dadataKey = APIKeyStore.load(.dadata)
        dadataSecret = APIKeyStore.load(.dadataSecret)
    }

    @discardableResult
    func save() -> Bool {
        do {
            try APIKeyStore.save(yandexKey, for: .yandexGeocoder)
            try APIKeyStore.save(dadataKey, for: .dadata)
            try APIKeyStore.save(dadataSecret, for: .dadataSecret)
            savedMessage = "Ключи сохранены в Keychain."
            errorMessage = nil
            return true
        } catch {
            savedMessage = nil
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct SettingsView: View {
    @StateObject private var viewModel = APISettingsViewModel()
    let onSaved: () -> Void
    @State private var showYandexKey = false
    @State private var showDadataKey = false
    @State private var showDadataSecret = false

    var body: some View {
        Form {
            Section {
                keyField(
                    title: APIKeyName.yandexGeocoder.rawValue,
                    help: APIKeyName.yandexGeocoder.helpText,
                    value: $viewModel.yandexKey,
                    isVisible: $showYandexKey
                )

                keyField(
                    title: APIKeyName.dadata.rawValue,
                    help: APIKeyName.dadata.helpText,
                    value: $viewModel.dadataKey,
                    isVisible: $showDadataKey
                )

                keyField(
                    title: APIKeyName.dadataSecret.rawValue,
                    help: APIKeyName.dadataSecret.helpText,
                    value: $viewModel.dadataSecret,
                    isVisible: $showDadataSecret
                )
            } header: {
                Text("Ключи API")
            } footer: {
                Text("Ключи хранятся локально в системном Keychain и не записываются в исходный код или обычные настройки приложения.")
            }

            Section {
                Button("Сохранить ключи", systemImage: "key") {
                    if viewModel.save() {
                        onSaved()
                    }
                }
                .keyboardShortcut(.defaultAction)

                if let savedMessage = viewModel.savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки API")
        .frame(minWidth: 520, minHeight: 360)
    }

    @ViewBuilder
    private func keyField(
        title: String,
        help: String,
        value: Binding<String>,
        isVisible: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Group {
                    if isVisible.wrappedValue {
                        TextField(title, text: value)
                    } else {
                        SecureField(title, text: value)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isVisible.wrappedValue ? "Скрыть ключ" : "Показать ключ")
            }

            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
