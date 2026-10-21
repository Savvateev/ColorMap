import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "map.circle.fill")
                .font(.system(size: 64))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.blue, .green)
                .accessibilityHidden(true)

            Text("ColorMap")
                .font(.largeTitle.bold())

            VStack(spacing: 10) {
                Text("Интернет-провайдер «Большие связи»")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Анализ объектов и подготовка карт")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()
                .frame(maxWidth: 360)

            Text("Автор: Павел Савватеев")
                .font(.body)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("О программе")
    }
}

#Preview {
    AboutView()
}
