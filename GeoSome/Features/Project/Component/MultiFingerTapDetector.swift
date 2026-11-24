import SwiftUI
#if canImport(UIKit)
import UIKit

/// An invisible passthrough view that attaches multi-finger tap gesture recognizers
/// (e.g., 3-finger or 4-finger tap) to detect secret demo gestures.
struct MultiFingerTapDetector: UIViewRepresentable {
  var numberOfTouches: [Int] = [3, 4]
  var action: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeUIView(context: Context) -> PassthroughView {
    let view = PassthroughView()
    view.coordinator = context.coordinator
    view.numberOfTouches = numberOfTouches
    view.backgroundColor = .clear
    return view
  }

  func updateUIView(_ uiView: PassthroughView, context: Context) {
    context.coordinator.action = action
  }

  @MainActor
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var action: () -> Void
    var recognizers: [UITapGestureRecognizer] = []
    private var lastTriggerTime: TimeInterval = 0

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
      guard recognizer.state == .recognized else { return }
      let now = ProcessInfo.processInfo.systemUptime
      guard now - lastTriggerTime > 1.2 else { return }
      lastTriggerTime = now
      action()
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }
  }

  final class PassthroughView: UIView {
    weak var coordinator: Coordinator?
    var numberOfTouches: [Int] = [3, 4]

    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard let coordinator else { return }

      cleanUpRecognizers(coordinator: coordinator)

      guard let targetView = window ?? self.superview else { return }

      for count in numberOfTouches {
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTouchesRequired = count
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.delegate = coordinator
        targetView.addGestureRecognizer(tap)
        coordinator.recognizers.append(tap)
      }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
      super.willMove(toWindow: newWindow)
      if newWindow == nil, let coordinator {
        cleanUpRecognizers(coordinator: coordinator)
      }
    }

    private func cleanUpRecognizers(coordinator: Coordinator) {
      for r in coordinator.recognizers {
        r.view?.removeGestureRecognizer(r)
      }
      coordinator.recognizers.removeAll()
    }
  }
}
#else
struct MultiFingerTapDetector: View {
  var numberOfTouches: [Int] = [3, 4]
  var action: () -> Void

  var body: some View {
    Color.clear
  }
}
#endif
