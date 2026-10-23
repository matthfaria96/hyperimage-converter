import SwiftUI

/// Empty-list landing area. Idles with a gentle float and reacts when files are dragged over it.
struct EmptyDropZone: View {
    let targeted: Bool
    let addFiles: () -> Void
    var browse: (() -> Void)?

    var body: some View {
        VStack(spacing: 22) {
            DropIllustration(targeted: targeted)
            VStack(spacing: 6) {
                Text(targeted ? "Solte para adicionar" : "Arraste suas imagens para cá")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.opacity)
                Text("Imagens ou pastas do Finder — ou use ⌘O.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                Button("Adicionar imagens…", systemImage: "plus", action: addFiles)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                if let browse {
                    Button("Navegar pelas pastas do Mac", systemImage: "sidebar.leading", action: browse)
                        .buttonStyle(.glass)
                }
            }
            .opacity(targeted ? 0 : 1)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if targeted { DropZoneFrame(targeted: true).padding(24).transition(.opacity.combined(with: .scale(scale: 0.98))) }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.7), value: targeted)
    }
}

/// Full overlay shown over a non-empty list while a drag hovers it.
struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 14) {
                DropIllustration(targeted: true)
                Text("Solte para adicionar à lista").font(.title3.weight(.semibold))
            }
        }
        .overlay { DropZoneFrame(targeted: true).padding(10) }
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 1.03)))
    }
}

/// Stack of tilted "photo cards" that fan out and lift when a drop is pending.
private struct DropIllustration: View {
    let targeted: Bool
    @State private var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.accentColor.opacity(targeted ? 0.35 : 0.15), .clear],
                                     center: .center, startRadius: 4, endRadius: 90))
                .frame(width: 180, height: 180)
                .scaleEffect(targeted ? 1.25 : 1)
            card(color: .pink, systemImage: "photo").rotationEffect(.degrees(targeted ? -24 : -10))
                .offset(x: targeted ? -38 : -14, y: targeted ? 6 : 4)
            card(color: .orange, systemImage: "camera.macro").rotationEffect(.degrees(targeted ? 22 : 9))
                .offset(x: targeted ? 38 : 14, y: targeted ? 6 : 4)
            card(color: .accentColor, systemImage: targeted ? "arrow.down" : "photo.on.rectangle.angled")
                .offset(y: targeted ? -14 : 0)
                .symbolEffect(.bounce, value: targeted)
        }
        .offset(y: floating && !targeted ? -5 : 0)
        .scaleEffect(targeted ? 1.08 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { floating = true }
        }
    }

    private func card(color: Color, systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 74, height: 90)
            .overlay {
                Image(systemName: systemImage).font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
            }
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1) }
            .shadow(color: color.opacity(0.35), radius: 10, y: 6)
    }
}

/// Dashed border whose dashes "march" while targeted.
private struct DropZoneFrame: View {
    let targeted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !targeted || reduceMotion)) { context in
            let phase = targeted && !reduceMotion ? context.date.timeIntervalSinceReferenceDate * -28 : 0
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.accentColor.opacity(targeted ? 0.08 : 0))
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: targeted ? 3 : 1.5, lineCap: .round,
                                                 dash: [10, 8], dashPhase: phase))
        }
    }
}

/// Slim glass hint above a non-empty list: a drop target that also opens the file panel when clicked.
struct CompactDropZone: View {
    let targeted: Bool
    let addFiles: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: addFiles) {
            HStack(spacing: 10) {
                Image(systemName: targeted ? "arrow.down.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: targeted)
                Text(targeted ? "Solte para adicionar" : "Arraste imagens ou pastas, ou clique para escolher")
                    .foregroundStyle(targeted || hovering ? .primary : .secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(targeted ? Color.accentColor.opacity(0.25) : nil).interactive(), in: .capsule)
        .overlay {
            if targeted {
                Capsule().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: targeted)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Adicionar imagens (⌘O)")
    }
}
