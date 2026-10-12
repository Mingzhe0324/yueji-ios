import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Foreground presentation only. The original notification and ledger records remain intact.
struct ForegroundLedgerNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let recordID: String?
    let kind: String?
    init(title: String, message: String, userInfo: [AnyHashable: Any]) {
        self.title = title; self.message = message
        if let record = userInfo["recordID"] as? String, !record.isEmpty,
           let kind = userInfo["recordKind"] as? String, ["expense", "notice"].contains(kind) {
            self.recordID = record; self.kind = kind
        } else { self.recordID = nil; self.kind = nil }
    }
    var destination: [String: String]? {
        guard let recordID, let kind else { return nil }
        return ["recordID": recordID, "kind": kind, "action": "view"]
    }
}

struct BannerExpirationKey: Hashable {
    let id: UUID?
    let paused: Bool
}

@MainActor enum BannerTiming {
    // Give VoiceOver time to read the message and reach its actions.
    static var duration: TimeInterval { UIAccessibility.isVoiceOverRunning ? 12 : 4 }
}

enum BannerSwipePolicy {
    static func accepts(translation: CGPoint, velocity: CGPoint) -> Bool {
        let vector = abs(translation.x) + abs(translation.y) > 2 ? translation : velocity
        return axis(translation: vector) != nil
    }
    enum Axis { case horizontal, upward }
    static func axis(translation: CGPoint) -> Axis? {
        if abs(translation.x) > abs(translation.y) * 1.25 { return .horizontal }
        if translation.y < 0 && abs(translation.y) > abs(translation.x) * 1.25 { return .upward }
        return nil
    }
    /// A reverse flick cancels an otherwise long drag; a short deliberate flick can dismiss.
    static func dismissalDirection(offset: CGFloat, velocity: CGFloat, width: CGFloat, cancelled: Bool = false) -> CGFloat? {
        guard !cancelled else { return nil }
        let threshold = min(140, max(72, width * 0.28))
        let reverses = offset * velocity < 0 && abs(velocity) > 450
        let projected = offset + velocity * 0.16
        if reverses && (projected * offset <= 0 || abs(projected) < threshold) { return nil }
        if abs(offset) >= threshold { return offset < 0 ? -1 : 1 }
        if abs(offset) >= 12 && abs(velocity) >= 650 && offset * velocity > 0 { return offset < 0 ? -1 : 1 }
        return nil
    }
}

/// UIKit owns the translation so finger movement doesn't publish changes into the app's view tree.
@MainActor final class BannerInteraction {
    var dragged = false
    var exiting = false
    var dismiss: (() -> Void)?
    var canActivate: Bool { !dragged && !exiting }
}

/// Observe the entire contact, including a downward drag rejected by the dismissal pan.
/// This recognizer never cancels the hosted button or the simultaneous pan.
@MainActor private final class BannerContact: UIGestureRecognizer {
    var contactBegan: (() -> Void)?
    var contactMoved: ((CGPoint) -> Void)?
    var contactEnded: (() -> Void)?
    private var origin: CGPoint?
    private var contacts = Set<UITouch>()
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        contacts.formUnion(touches)
        if origin == nil { origin = touches.first?.location(in: view); contactBegan?() }
        super.touchesBegan(touches, with: event)
        if state == .possible { state = .began }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let origin, let point = touches.first?.location(in: view) {
            contactMoved?(CGPoint(x: point.x - origin.x, y: point.y - origin.y))
        }
        super.touchesMoved(touches, with: event)
        state = .changed
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        contacts.subtract(touches)
        if contacts.isEmpty { contactEnded?(); state = .ended }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event); contactEnded?(); state = .cancelled
    }
    override func reset() { super.reset(); origin = nil; contacts.removeAll(); contactEnded?() }
}

@MainActor final class SwipeBannerController: UIViewController, UIGestureRecognizerDelegate {
    private let host: UIHostingController<AnyView>
    let interaction: BannerInteraction
    var reduceMotion: Bool
    var onDismiss: () -> Void
    var onInteraction: (Bool) -> Void
    private var animator: UIViewPropertyAnimator?
    private var initialOffset = CGPoint.zero
    private var axis: BannerSwipePolicy.Axis = .horizontal
    private var touching = false
    private var entered = false
    private var stopped = false
    init(content: AnyView, interaction: BannerInteraction, reduceMotion: Bool,
         onDismiss: @escaping () -> Void, onInteraction: @escaping (Bool) -> Void) {
        host = UIHostingController(rootView: content)
        self.interaction = interaction; self.reduceMotion = reduceMotion
        self.onDismiss = onDismiss; self.onInteraction = onInteraction
        super.init(nibName: nil, bundle: nil)
        interaction.dismiss = { [weak self] in self?.exit(direction: 1) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        addChild(host)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = false
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1; pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false; pan.delaysTouchesEnded = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
        let contact = BannerContact(target: nil, action: nil)
        contact.cancelsTouchesInView = false
        contact.delaysTouchesBegan = false; contact.delaysTouchesEnded = false
        contact.delegate = self
        contact.contactBegan = { [weak self] in self?.beginContact() }
        contact.contactMoved = { [weak self] in self?.movedContact(translation: $0) }
        contact.contactEnded = { [weak self] in self?.endContact() }
        view.addGestureRecognizer(contact)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !entered, !stopped else { return }; entered = true
        host.view.alpha = 0
        if !reduceMotion { host.view.transform = CGAffineTransform(translationX: 0, y: -6) }
        animate(duration: 0.18, spring: false) { [weak self] in
            self?.host.view.alpha = 1; self?.host.view.transform = .identity
        }
    }
    func update(content: AnyView) { host.rootView = content }
    func fittingSize(width: CGFloat) -> CGSize {
        let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(44, size.height))
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is BannerContact { return !interaction.exiting && !stopped }
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, !interaction.exiting, !stopped else { return false }
        return BannerSwipePolicy.accepts(translation: pan.translation(in: view), velocity: pan.velocity(in: view))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer is BannerContact || otherGestureRecognizer is BannerContact
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // The host occupies only the card, never a full-screen gesture shield.
        view.bounds.contains(touch.location(in: view))
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        !(gestureRecognizer is BannerContact) && otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
    }
    private func setTouching(_ value: Bool) {
        guard !stopped else { return }
        guard touching != value else { return }
        touching = value; onInteraction(value)
    }
    func beginContact() {
        guard !interaction.exiting, !stopped else { return }
        interaction.dragged = false
        interruptAnimation()
        initialOffset = CGPoint(x: host.view.transform.tx, y: host.view.transform.ty)
        host.view.alpha = 1
        setTouching(true)
    }
    func movedContact(translation: CGPoint) {
        guard !stopped else { return }
        // Even a rejected vertical pan must not turn into a button tap at touch-up.
        if max(abs(translation.x), abs(translation.y)) > 10 { interaction.dragged = true }
    }
    func endContact() { setTouching(false) }
    private func interruptAnimation() {
        let transform = host.view.layer.presentation()?.affineTransform() ?? host.view.transform
        let alpha = host.view.layer.presentation()?.opacity ?? Float(host.view.alpha)
        stopAnimator()
        host.view.transform = transform; host.view.alpha = CGFloat(alpha)
    }
    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        handlePan(state: pan.state, translation: pan.translation(in: view), velocity: pan.velocity(in: view))
    }
    func handlePan(state: UIGestureRecognizer.State, translation: CGPoint, velocity: CGPoint) {
        guard !interaction.exiting, !stopped else { return }
        switch state {
        case .began:
            interaction.dragged = true
            axis = BannerSwipePolicy.axis(translation: translation) ?? BannerSwipePolicy.axis(translation: velocity) ?? .horizontal
            // Recognition cancels the hosted button; retain this latch through touch-up as well.
            host.view.alpha = 1
            move(translation)
        case .changed:
            move(translation)
        case .ended, .cancelled, .failed:
            let upward = axis == .upward
            let offset = upward ? min(0, initialOffset.y + translation.y) : initialOffset.x + translation.x
            if let direction = BannerSwipePolicy.dismissalDirection(offset: offset, velocity: upward ? velocity.y : velocity.x,
                width: upward ? view.bounds.height : view.bounds.width, cancelled: state != .ended), !upward || direction < 0 {
                exit(direction: direction, upward: upward)
            } else {
                if reduceMotion { host.view.transform = .identity; host.view.alpha = 1 }
                else {
                    animate(duration: 0.24, spring: true) { [weak self] in
                        self?.host.view.transform = .identity; self?.host.view.alpha = 1
                    }
                }
            }
        default: break
        }
    }
    private func move(_ translation: CGPoint) {
        host.view.transform = axis == .upward
            ? CGAffineTransform(translationX: 0, y: min(0, initialOffset.y + translation.y))
            : CGAffineTransform(translationX: initialOffset.x + translation.x, y: 0)
    }
    private func animate(duration: TimeInterval, spring: Bool, changes: @escaping () -> Void, completion: (() -> Void)? = nil) {
        stopAnimator()
        let animation = spring ? UIViewPropertyAnimator(duration: duration, dampingRatio: 0.9, animations: changes)
            : UIViewPropertyAnimator(duration: duration, curve: .easeOut, animations: changes)
        animator = animation
        animation.addCompletion { [weak self, weak animation] position in
            if self?.animator === animation { self?.animator = nil }
            if position == .end { completion?() }
        }
        animation.startAnimation()
    }
    private func stopAnimator() {
        if animator?.state == .active { animator?.stopAnimation(true) }
        animator = nil
    }
    private func exit(direction: CGFloat, upward: Bool = false) {
        guard !interaction.exiting, !stopped else { return }
        interruptAnimation(); interaction.exiting = true
        host.view.isUserInteractionEnabled = false
        let window = view.window
        let frame = view.convert(view.bounds, to: window)
        let target = direction > 0 ? (window?.bounds.width ?? view.bounds.width) - frame.minX + 24 : -frame.maxX - 24
        animate(duration: reduceMotion ? 0.14 : 0.20, spring: false, changes: { [weak self] in
            guard let self else { return }
            if self.reduceMotion { self.host.view.alpha = 0 }
            else { self.host.view.transform = upward
                ? CGAffineTransform(translationX: 0, y: -frame.maxY - 24)
                : CGAffineTransform(translationX: target, y: 0) }
        }, completion: { [weak self] in
            // Consume the dismissing touch through the animation, then release the card's hit area.
            self?.view.isUserInteractionEnabled = false
            self?.onDismiss()
        })
    }
    func stop() {
        guard !stopped else { return }; stopped = true
        stopAnimator()
        interaction.dismiss = nil
        if touching {
            touching = false
            let ended = onInteraction
            // Dismantling may run during a SwiftUI update. Publish after that update, without a timed delay.
            Task { @MainActor in ended(false) }
        }
    }
}

@MainActor private struct SwipeBannerBridge: UIViewControllerRepresentable {
    let content: AnyView
    let interaction: BannerInteraction
    let reduceMotion: Bool
    let onDismiss: () -> Void
    let onInteraction: (Bool) -> Void
    func makeUIViewController(context: Context) -> SwipeBannerController {
        SwipeBannerController(content: content, interaction: interaction, reduceMotion: reduceMotion,
                              onDismiss: onDismiss, onInteraction: onInteraction)
    }
    func updateUIViewController(_ controller: SwipeBannerController, context: Context) {
        controller.reduceMotion = reduceMotion; controller.onDismiss = onDismiss; controller.onInteraction = onInteraction
        controller.update(content: content)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController: SwipeBannerController, context: Context) -> CGSize? {
        let width = proposal.width ?? 340
        return uiViewController.fittingSize(width: width.isFinite ? max(1, min(520, width)) : 520)
    }
    static func dismantleUIViewController(_ controller: SwipeBannerController, coordinator: ()) { controller.stop() }
}

@MainActor struct SwipeDismissBanner<Content: View>: View {
    @EnvironmentObject private var model: LedgerModel
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var interaction = BannerInteraction()
    let onDismiss: () -> Void
    var onInteraction: (Bool) -> Void = { _ in }
    @ViewBuilder let content: (BannerInteraction) -> Content
    var body: some View {
        // Forward app overrides through writable keys. Contrast and accessibility preferences
        // are read-only system values; the child UIHostingController reads them from iOS.
        // Pass Reduce Motion directly to the UIKit animation controller instead of overriding it.
        SwipeBannerBridge(content: AnyView(content(interaction)
            .environmentObject(model).environment(\.locale, locale).environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, typeSize).environment(\.layoutDirection, direction)),
            interaction: interaction, reduceMotion: reduceMotion, onDismiss: onDismiss, onInteraction: onInteraction)
    }
}

struct NotificationBannerSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    @ViewBuilder private var surface: some View {
        if reduceTransparency { shape.fill(Color(uiColor: .secondarySystemGroupedBackground)) }
        else if #available(iOS 26.0, *) { Color.clear.glassEffect(.regular, in: shape) }
        else { shape.fill(.regularMaterial) }
    }
    func body(content: Content) -> some View {
        content.background { surface }
            .overlay { shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.09), lineWidth: 0.5).allowsHitTesting(false) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.08), radius: 8, y: 3)
    }
}
