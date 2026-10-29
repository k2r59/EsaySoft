import SwiftUI

struct NoticeBanner: View {
    let title: String
    let message: String
    var warning = false
    var dismiss: (() -> Void)? = nil
    private var color: Color { warning ? .orange : Theme.green }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 21)).foregroundStyle(color).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(message).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).accessibilityLabel("Fermer le message")
            }
        }.padding(16).foregroundStyle(.white)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.65), lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}
