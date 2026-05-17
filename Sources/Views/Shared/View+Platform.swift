import Foundation
import SwiftUI
import os

final class DebouncedWorkScheduler {
  private let queue: DispatchQueue
  private let delay: TimeInterval
  private var pendingWorkItem: DispatchWorkItem?

  init(label: String, delay: TimeInterval) {
    self.queue = DispatchQueue(label: label, qos: .utility)
    self.delay = delay
  }

  func schedule(_ block: @escaping () -> Void) {
    pendingWorkItem?.cancel()
    let workItem = DispatchWorkItem(block: block)
    pendingWorkItem = workItem
    queue.asyncAfter(deadline: .now() + delay, execute: workItem)
  }
}

enum PerformanceMonitor {
  private static let logger = Logger(subsystem: "com.loldashboard.notiondashboard", category: "performance")
  private static let queue = DispatchQueue(label: "com.loldashboard.notiondashboard.performance", qos: .utility)
  private static var renderHits: [String: Int] = [:]
  private static var widgetReloadCount = 0

  static func recordPersistence(label: String, durationMs: Double) {
#if DEBUG
    logger.debug("persist[\(label, privacy: .public)] \(durationMs, format: .fixed(precision: 2))ms")
#endif
  }

  static func recordRender(label: String, durationMs: Double) {
#if DEBUG
    queue.async {
      renderHits[label, default: 0] += 1
      let hitCount = renderHits[label, default: 0]
      if hitCount == 1 || hitCount.isMultiple(of: 25) {
        logger.debug("render[\(label, privacy: .public)] #\(hitCount) \(durationMs, format: .fixed(precision: 2))ms")
      }
    }
#endif
  }

  static func noteWidgetReloadScheduled() {
#if DEBUG
    queue.async {
      widgetReloadCount += 1
      logger.debug("widget-reload-batch #\(widgetReloadCount)")
    }
#endif
  }
}

enum AppLogger {
  private static let subsystem = "com.loldashboard.notiondashboard"

  static let app = Logger(subsystem: subsystem, category: "app")
  static let database = Logger(subsystem: subsystem, category: "database")
  static let notion = Logger(subsystem: subsystem, category: "notion")
  static let google = Logger(subsystem: subsystem, category: "google")
  static let calendar = Logger(subsystem: subsystem, category: "calendar")
  static let widget = Logger(subsystem: subsystem, category: "widget")
  static let focus = Logger(subsystem: subsystem, category: "focus")
  static let network = Logger(subsystem: subsystem, category: "network")
  static let persistence = Logger(subsystem: subsystem, category: "persistence")
}

extension View {
  @ViewBuilder
  func plainTextInputBehavior() -> some View {
#if os(iOS)
    textInputAutocapitalization(.never)
      .autocorrectionDisabled()
#else
    self
#endif
  }

  func instrumentedScreen(_ label: String) -> some View {
#if DEBUG
    return _buildInstrumentedScreen(label)
#else
    return self
#endif
  }

  private func _buildInstrumentedScreen(_ label: String) -> Self {
    let start = CFAbsoluteTimeGetCurrent()
    let built = self
    let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
    PerformanceMonitor.recordRender(label: label, durationMs: durationMs)
    return built
  }
}
