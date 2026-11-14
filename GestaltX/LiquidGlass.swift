// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import SwiftUI

/// Liquid Glass design system for the Tools home, preset groups and change
/// review pages. Presentation only: no preset, staging, backup or write
/// behavior lives here.
///
/// The system prefers the native iOS 26 glass APIs (`glassEffect`,
/// `GlassEffectContainer`). The deployment target is iOS 26, so the APIs
/// are available, but every glass surface still has an explicit fallback:
/// SwiftUI Material plus a hairline stroke and a soft shadow, used when
/// the SDK check fails or when the user turned on Reduce Transparency
/// (in which case the fallback is an opaque system background instead of
/// any blur). Reduce Motion disables press-scale and transition
/// animations; Dynamic Type is honored by the callers (adaptive grids
/// collapse to one column at accessibility sizes).
enum GlassTokens {
    static let cornerRadius: CGFloat = 20
    static let smallRadius: CGFloat = 14
    static let tileRadius: CGFloat = 18
    static let barRadius: CGFloat = 22
    static let borderOpacity: Double = 0.35
    static let shadowOpacity: Double = 0.12
    /// The corner radius of the main diagnostic cards on the home.
    /// Every full card uses this (not a per-card literal) so the
    /// radius stays uniform when the design is adjusted.
    static let cardRadius: CGFloat = 22
    /// The vertical spacing between sections inside a card.
    static let cardSpacing: CGFloat = 14
    /// The inner padding of a card's content (the inset from the
    /// glass edge to the text). The cards apply this to their outer
    /// stack; the glass itself adds no padding, so the value lives
    /// here as the single source of truth.
    static let cardPadding: CGFloat = 16
    /// The icon pedestal sizes: full cards use `iconSize`, feature
    /// rows and progress cards use `iconSizeSmall`, compact apply
    /// steps use `iconSizeCompact`. One source of truth; callers
    /// read these, not literals.
    static let iconSize: CGFloat = 44
    static let iconSizeSmall: CGFloat = 40
    static let iconSizeCompact: CGFloat = 36
    /// Page and section layout: the outer page margin, the spacing
    /// between home sections, the grid spacing between tiles, and
    /// the minimum height of a destination tile.
    static let pageMargin: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let gridSpacing: CGFloat = 12
    static let tileMinHeight: CGFloat = 106
    /// The inner padding of a category tile's content.
    static let tilePadding: CGFloat = 12
    /// Title / subtitle / detail text styles for card headers, as
    /// one source of truth so card headers do not drift per card.
    static let cardTitleFont: Font = .headline
    static let cardSubtitleFont: Font = .subheadline
    static let cardDetailFont: Font = .caption
    /// Status colors, as one source of truth: success green,
    /// warning orange, danger red. A status text and its fill
    /// always use the same token.
    static let successColor: Color = .green
    static let warningColor: Color = .orange
    static let dangerColor: Color = .red
    /// Minimum tap height for text buttons in the catalog manager
    /// (44pt, the platform minimum). The primary glass button keeps
    /// its own padding-based height and is untouched.
    static let buttonMinHeight: CGFloat = 44
    /// Cards and sections are leading-aligned; the value lives here
    /// so a section that needs centered content says so explicitly.
    static let cardAlignment: HorizontalAlignment = .leading
}

extension Color {
    /// Primary lavender accent (#8652DC in light mode, a lighter
    /// lavender in dark mode so text and icons stay readable). Used for
    /// the tab bar, primary buttons, accent pills and the author badge.
    static let gestaltAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.66, green: 0.55, blue: 0.98, alpha: 1)
            : UIColor(red: 0.53, green: 0.32, blue: 0.86, alpha: 1)
    })

    /// Soft periwinkle for the two blue-ish category/preset tints, so
    /// icons keep a slight colour distinction without system blue.
    static let lavenderBlue = Color(red: 0.45, green: 0.42, blue: 0.88)

    /// Light-purple glass tint (#EAE1FF) for the unlock hero card.
    static let lavenderGlass = Color(red: 0.92, green: 0.88, blue: 1.0)

    /// Deep purple end of the primary-button gradient (#643ACB).
    static let lavenderDeep = Color(red: 0.39, green: 0.23, blue: 0.80)
}

/// Light-lavender page background (#F6F3FF family) with a few soft,
/// static lavender light spots. Dark mode uses a deep-plum glass theme
/// in the same lavender family (no midnight blue). No animation, no
/// strong glow. When Reduce Transparency is on, the spots disappear
/// and the background is solid.
struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            [Color(red: 0.09, green: 0.07, blue: 0.16),
             Color(red: 0.12, green: 0.09, blue: 0.20),
             Color(red: 0.16, green: 0.12, blue: 0.27)]
        } else {
            [Color(red: 0.96, green: 0.95, blue: 1.0),
             Color(red: 0.94, green: 0.91, blue: 1.0),
             Color(red: 0.92, green: 0.88, blue: 1.0)]
        }
    }

    var body: some View {
        if reduceTransparency {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        } else {
            ZStack {
                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(Color.purple.opacity(colorScheme == .dark ? 0.20 : 0.10))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(x: -140, y: -260)
                Circle()
                    .fill(Color.gestaltAccent.opacity(colorScheme == .dark ? 0.16 : 0.08))
                    .frame(width: 280, height: 280)
                    .blur(radius: 90)
                    .offset(x: 150, y: 180)
                Circle()
                    .fill(Color.purple.opacity(colorScheme == .dark ? 0.12 : 0.05))
                    .frame(width: 220, height: 220)
                    .blur(radius: 80)
                    .offset(x: 120, y: -80)
            }
            .ignoresSafeArea()
        }
    }
}

/// A translucent frosted-glass card. On iOS 26+ this is a real glass
/// surface (regular glass with an optional tint); otherwise it falls back
/// to ultra-thin material with a hairline highlight border and a soft
/// shadow. Reduce Transparency forces an opaque system background.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color?
    let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(cornerRadius: CGFloat = GlassTokens.cornerRadius, tint: Color? = nil,
         @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint,
                                        reduceTransparency: reduceTransparency))
    }
}

private struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: cornerRadius))
        } else if #available(iOS 26.0, *) {
            // No .shadow() here on purpose: on iOS 26+ the glass effect
            // already gives the card its depth, and a radius-14 shadow on
            // every card forced an extra offscreen blur per card while
            // scrolling, which made the Tools tab lag. The pre-iOS 26
            // fallback below keeps its shadow (no glass there to carry
            // the depth).
            content
                .glassEffect(glassEffect(), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(GlassTokens.borderOpacity), lineWidth: 0.5))
                .shadow(color: .black.opacity(GlassTokens.shadowOpacity), radius: 14, y: 5)
        }
    }

    @available(iOS 26.0, *)
    private func glassEffect() -> Glass {
        if let tint {
            return .regular.tint(tint).interactive()
        }
        return .regular.interactive()
    }
}

/// Primary button in a purple glass gradient (#8652DC → #643ACB).
/// Used for the one-tap unlock / apply actions. Press feedback scales
/// slightly and dims; Reduce Motion turns the scale off.
struct GlassPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background { glassBackground }
            .clipShape(RoundedRectangle(cornerRadius: GlassTokens.smallRadius))
            .overlay(RoundedRectangle(cornerRadius: GlassTokens.smallRadius)
                .stroke(.white.opacity(0.4), lineWidth: 0.5))
            .shadow(color: Color.gestaltAccent.opacity(0.35), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var glassBackground: some View {
        Group {
            if reduceTransparency {
                Color.lavenderDeep
            } else {
                LinearGradient(colors: [Color.gestaltAccent, Color.lavenderDeep],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
    }
}

/// A feature icon on a translucent glass pedestal, tinted per category.
/// Used for preset rows and category tiles so every icon shares one look.
struct GlassIconPedestal: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = GlassTokens.iconSize

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.35), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// Small status pill: Configured (green), Not Configured (gray),
/// Pending (orange), Unsupported (red), Enabled (blue). The text and the
/// translucent fill always come from the same tint so contrast is kept.
struct GlassStatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 0.5))
    }
}

/// A two-column category tile for the Tools home: glass pedestal icon,
/// title, one-line example, and a chevron. The whole tile is the link.
struct GlassCategoryTile: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            GlassIconPedestal(systemImage: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // No line limit: at large Dynamic Type sizes the
                    // description wraps instead of truncating (P1.8).
                    // The tile grows taller; the title stays short.
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(GlassTokens.tilePadding)
    }
}

/// A floating glass bar pinned above the bottom safe area, used for the
/// pending-changes button on preset pages and the apply bar on the change
/// review page. Apply it with `.safeAreaInset(edge: .bottom)`.
struct GlassBottomBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.barRadius) {
            content
                .padding(.horizontal, GlassTokens.pageMargin)
                .padding(.vertical, 12)
        }
        .padding(.horizontal, GlassTokens.pageMargin)
        .padding(.bottom, 8)
    }
}

/// One preset row on a group page: glass icon pedestal, name, one-line
/// purpose, current-status badge, an Enable/Pending action, and the "⋯"
/// menu with conditions, compatibility notes and restore. The row itself
/// only presents state; all staging logic stays in the caller.
struct GlassFeatureRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let caution: Bool
    let effectHint: String?
    let statusText: String
    let statusTint: Color
    let actionTitle: String?
    let actionEnabled: Bool
    let onAction: () -> Void
    let menu: AnyView

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            GlassIconPedestal(systemImage: symbol, tint: tint, size: GlassTokens.iconSizeSmall)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if caution {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(L("Experimental"))
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // No line limit: at large Dynamic Type sizes the
                    // purpose wraps instead of truncating (P1.8).
                    // The status badge below is a separate view.
                if let effectHint {
                    Text(effectHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GlassStatusBadge(text: statusText, tint: statusTint)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 8) {
                if let actionTitle {
                    Button(actionTitle, action: onAction)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(actionEnabled ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(actionEnabled ? Color.gestaltAccent : Color.secondary.opacity(0.18),
                                    in: Capsule())
                        .disabled(!actionEnabled)
                        .opacity(actionEnabled ? 1 : 0.7)
                }
                menu
            }
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: statusText)
    }
}

/// Progress card shown while the device is being read. The bar is
/// indeterminate on purpose: the upstream read path reports no numeric
/// progress, so no percentage is shown or invented. The card is only
/// visible while a read is actually in progress (driven by
/// `GestaltManager.isReading`).
struct GlassReadProgressCard: View {
    let title: String

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.smallRadius) {
            HStack(spacing: 12) {
                GlassIconPedestal(systemImage: "clock.arrow.circlepath", tint: .gestaltAccent, size: GlassTokens.iconSizeSmall)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    ProgressView()
                        .tint(.gestaltAccent)
                }
                Spacer(minLength: 4)
            }
            .padding(GlassTokens.tilePadding)
        }
    }
}

/// One step of the apply-progress card.
enum ApplyStepState { case done, current, pending, failed }

struct GlassApplyStep {
    let title: String
    let state: ApplyStepState
}

/// Apply-progress card for the change review page. `progress` is the
/// fraction of steps actually observed as complete (0…1) and `title`
/// names the step currently in progress. Steps are driven by the real
/// write flow (backup → write → verify → done) as observed through the
/// session log; no step is shown as done before its event appears, and
/// a failed step is shown as failed instead of claiming success.
struct GlassApplyProgressCard: View {
    let title: String
    let progress: Double
    let steps: [GlassApplyStep]

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.smallRadius) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    GlassIconPedestal(systemImage: "checkmark.circle", tint: .gestaltAccent, size: GlassTokens.iconSizeCompact)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                ProgressView(value: progress)
                    .tint(.gestaltAccent)
                HStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        VStack(spacing: 4) {
                            stepIcon(step.state)
                            Text(step.title)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(step.state == .pending ? .tertiary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private func stepIcon(_ state: ApplyStepState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        case .current:
            Image(systemName: "arrow.right.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.gestaltAccent)
        case .pending:
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.tertiary)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
        }
    }
}
