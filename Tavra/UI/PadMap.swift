import SwiftUI

/// The trackpad, to scale: every zone where it really is, your fingers on it as they land.
struct PadMap: View {
    var model: AppModel
    /// What's drawn: the defaults, or an app's own version of them.
    var bindings: Bindings
    /// Set when zones can be picked.
    var selected: Zone?
    var onSelect: ((Zone) -> Void)?
    var showsCaption = true

    private var feel: FeelSettings { model.config.feel }
    private var surface: Surface { model.devices.first?.surface ?? .builtIn }

    var body: some View {
        GeometryReader { geometry in
            let size = fitted(in: geometry.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card.opacity(0.55))
                ForEach(Zone.edges) { zone in strip(zone, in: size) }
                ForEach(Zone.corners) { zone in strip(zone, in: size) }
                if showsCaption {
                    Text("The center stays yours.")
                        .font(.system(size: 12.5, weight: .light)).foregroundStyle(Theme.tertiary)
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                }
                if let selected { SelectionFrame(rect: frame(of: selected, in: size)) }
                TouchField(router: model.router, size: size, zones: litZones(in: size))
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line).allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(surface.widthMM / surface.heightMM, contentMode: .fit)
    }

    private func fitted(in available: CGSize) -> CGSize {
        let ratio = surface.widthMM / surface.heightMM
        let width = min(available.width, available.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    private func frame(of zone: Zone, in size: CGSize) -> CGRect {
        let r = Geometry.rect(zone, surface: surface, feel: feel)
        return CGRect(x: r.minX * size.width, y: (1 - r.maxY) * size.height, width: (r.maxX - r.minX) * size.width, height: (r.maxY - r.minY) * size.height)
    }

    /// Light pools only in zones that do something.
    private func litZones(in size: CGSize) -> [CGRect] {
        Zone.allCases.filter { bindings.has($0) }.map { frame(of: $0, in: size) }
    }

    @ViewBuilder private func strip(_ zone: Zone, in size: CGSize) -> some View {
        let rect = frame(of: zone, in: size)
        let isOn = selected == zone
        let hasJob = bindings.has(zone)
        // A corner with no job is only worth drawing when it's being looked at or picked from.
        if onSelect != nil || hasJob {
            ZoneCell(zone: zone, title: title(of: zone), icon: icon(of: zone), hasJob: hasJob, isOn: isOn, isVertical: zone == .left || zone == .right)
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .onTapGesture { onSelect?(zone) }
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private func title(of zone: Zone) -> String {
        if zone.isCorner {
            let counts = bindings.clickCounts(zone)
            guard let first = counts.first else { return "" }
            return counts.count > 1 ? "\(counts.count) actions" : bindings.tap(zone, clicks: first).title
        }
        return bindings.has(zone) ? bindings.slide(zone).title : ""
    }

    private func icon(of zone: Zone) -> String? {
        if zone.isCorner {
            guard let first = bindings.clickCounts(zone).first else { return nil }
            return bindings.tap(zone, clicks: first).icon
        }
        return bindings.has(zone) ? bindings.slide(zone).icon : nil
    }
}

private struct ZoneCell: View {
    var zone: Zone
    var title: String
    var icon: String?
    var hasJob: Bool
    var isOn: Bool
    var isVertical: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            // A corner with a job sits on top of the edges, so their lines don't run through it.
            if zone.isCorner, hasJob { Rectangle().fill(Theme.card) }
            Rectangle().fill(Theme.accent.opacity(hasJob ? (hovering ? 0.17 : 0.09) : (hovering ? 0.07 : 0)))
                .animation(.easeOut(duration: 0.16), value: hovering)
            if zone.isCorner, !hasJob {
                Rectangle().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            } else {
                Rectangle().strokeBorder(Theme.line, lineWidth: 1)
            }
            if let icon {
                if zone.isCorner || isVertical {
                    Image(systemName: icon).font(.system(size: 14, weight: .light)).foregroundStyle(isOn ? Theme.ink : Theme.secondary)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: icon).font(.system(size: 13, weight: .light))
                        Text(title).font(.system(size: 12))
                    }
                    .foregroundStyle(isOn ? Theme.ink : Theme.secondary)
                }
            }
        }
        .help(hasJob ? "\(zone.title): \(title)" : "\(zone.title): free")
        .onHover { hovering = $0 }
    }
}
