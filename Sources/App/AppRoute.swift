import SwiftUI

enum RootDestination: String, CaseIterable, Identifiable {
  case home
  case stages
  case calendar
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home:
      return "Home"
    case .stages:
      return "Stages"
    case .calendar:
      return "Calendar"
    case .settings:
      return "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .home:
      return "rectangle.grid.2x2.fill"
    case .stages:
      return "square.grid.2x2.fill"
    case .calendar:
      return "calendar"
    case .settings:
      return "gearshape.fill"
    }
  }
}

struct AppRouteFocus: Equatable {
  var destination: RootDestination
  var todoID: String?
  var stageID: String?
  var eventID: String?
  var nonce: UUID = UUID()

  static let home = AppRouteFocus(destination: .home, todoID: nil, stageID: nil, eventID: nil)
}

@MainActor
final class AppRouter: ObservableObject {
  @Published private(set) var route: AppRouteFocus = .home

  var destination: RootDestination {
    route.destination
  }

  func select(_ destination: RootDestination) {
    route = AppRouteFocus(destination: destination, todoID: nil, stageID: nil, eventID: nil)
  }

  func handle(url: URL) {
    guard url.scheme?.lowercased() == WidgetDeepLink.scheme else { return }

    let host = url.host?.lowercased() ?? ""
    let components = url.pathComponents.filter { $0 != "/" }

    switch host {
    case RootDestination.home.rawValue:
      if components.count >= 2, components[0].lowercased() == "todo" {
        route = AppRouteFocus(destination: .home, todoID: components[1], stageID: nil, eventID: nil)
      } else {
        select(.home)
      }
    case RootDestination.stages.rawValue:
      route = AppRouteFocus(
        destination: .stages,
        todoID: nil,
        stageID: components.first,
        eventID: nil
      )
    case RootDestination.calendar.rawValue:
      route = AppRouteFocus(
        destination: .calendar,
        todoID: nil,
        stageID: nil,
        eventID: components.first
      )
    case RootDestination.settings.rawValue:
      select(.settings)
    default:
      select(.home)
    }
  }
}
