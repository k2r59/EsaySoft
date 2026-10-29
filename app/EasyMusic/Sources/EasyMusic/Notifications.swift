import SwiftUI

struct MusicNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let warning: Bool
}

/// Errors survive navigation and concurrent successes. Routine confirmations coalesce.
@MainActor final class MusicNotifications: ObservableObject {
    @Published private(set) var messages: [MusicNotice] = []
    var current: MusicNotice? { messages.first }

    func post(_ message: String, warning: Bool = false) {
        guard !message.isEmpty else { return }
        if warning {
            guard !messages.contains(where: { $0.warning && $0.message == message }) else { return }
            let index = messages.firstIndex { !$0.warning } ?? messages.endIndex
            messages.insert(MusicNotice(message: message, warning: true), at: index)
        } else {
            messages.removeAll { !$0.warning }
            messages.append(MusicNotice(message: message, warning: false))
        }
    }

    func dismiss(_ id: UUID) { messages.removeAll { $0.id == id } }

    func expire(_ id: UUID) {
        guard let current, current.id == id, !current.warning else { return }
        dismiss(id)
    }
}

struct NoticeToast: View {
    @ObservedObject var notifications: MusicNotifications
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var closeFocused: Bool

    var body: some View {
        Group {
            if let notice = notifications.current {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: notice.warning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 19)).foregroundStyle(notice.warning ? .orange : Theme.green)
                        .padding(.top, 3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(notice.message).font(.system(size: 13, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        if notifications.messages.count > 1 {
                            Text(notifications.messages.count == 2 ? "1 autre notification" : "\(notifications.messages.count - 1) autres notifications")
                                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { notifications.dismiss(notice.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondary).frame(width: 28, height: 28)
                    }.buttonStyle(.plain).focused($closeFocused)
                        .accessibilityLabel("Fermer la notification")
                }
                .padding(16).frame(maxWidth: 460).foregroundStyle(.white)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
                .onHover { hovering = $0 }
                .task(id: "\(notice.id)-\(hovering)-\(closeFocused)") {
                    guard !notice.warning, !hovering, !closeFocused else { return }
                    do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                    guard !Task.isCancelled else { return }
                    notifications.expire(notice.id)
                }
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: notifications.current?.id)
    }
}

struct PlaylistWarningButton: View {
    let message: String
    @State private var presented = false
    @State private var pinned = false
    @State private var hovering = false
    @State private var bubbleHovered = false

    var body: some View {
        Button { pinned.toggle(); presented = pinned || hovering } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20)).foregroundStyle(.orange).frame(width: 44, height: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel("Avertissement sur l’import")
            .accessibilityValue(message)
            .onHover { hovering = $0; if $0 { presented = true } }
            .popover(isPresented: $presented, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Import potentiellement incomplet").font(.system(size: 13, weight: .bold))
                        Spacer(minLength: 8)
                        Button { pinned = false; presented = false } label: {
                            Image(systemName: "xmark").frame(width: 24, height: 24)
                        }.buttonStyle(.plain).accessibilityLabel("Fermer l’avertissement")
                    }
                    Text(message).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }.padding(16).frame(width: 320).background(Theme.card)
                    .onHover { bubbleHovered = $0 }
            }
            .task(id: "\(hovering)-\(bubbleHovered)-\(pinned)") {
                guard !hovering, !bubbleHovered, !pinned else { return }
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                presented = false
            }
            .onChange(of: presented) { if !$0 { pinned = false; bubbleHovered = false } }
    }
}
