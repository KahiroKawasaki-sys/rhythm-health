import SwiftUI

enum Palette {
    static let green = Color(red: 17/255, green: 90/255, blue: 54/255)
    static let ink = Color(red: 26/255, green: 41/255, blue: 35/255)
    static let secondary = Color(red: 89/255, green: 102/255, blue: 94/255)
    static let background = Color(red: 245/255, green: 246/255, blue: 242/255)
    /// SNSと合計が平均より多いときだけに使う。
    static let vermilion = Color(red: 207/255, green: 79/255, blue: 37/255)
}

struct Surface<Content: View>: View {
    var background: Color = .white
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20).background(background, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct SectionLabel: View {
    var title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(Palette.secondary) }
        }
    }
}

struct Notice: View {
    var text: String
    var body: some View {
        Label(text, systemImage: "info.circle").font(.footnote)
            .foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(.white).background(Palette.green.opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: 16))
    }
}
