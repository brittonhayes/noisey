import SwiftUI

struct BalanceSlider: View {
    let label: String
    let icon: String
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(width: 56, alignment: .leading)

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange(Float($0)) }
                ),
                in: 0...1
            )
            .tint(.white.opacity(0.5))

            Text("\(Int(value * 100))%")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular)
    }
}
