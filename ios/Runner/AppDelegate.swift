import UIKit
import Flutter
import EventKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "com.example.english/calendar", binaryMessenger: controller.binaryMessenger)

    let store = EKEventStore()

    channel.setMethodCallHandler { (call, result) in
      if call.method == "addEvent" {
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let timeStr = args["time"] as? String else {
          result(FlutterError(code: "BAD_ARGS", message: "Missing arguments", details: nil))
          return
        }
        let description = args["description"] as? String ?? ""

        let parts = timeStr.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
          result(FlutterError(code: "BAD_TIME", message: "Invalid time format", details: nil))
          return
        }

        store.requestAccess(to: .event) { granted, error in
          if granted {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.notes = description
            event.calendar = store.defaultCalendarForNewEvents

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute
            let calendar = Calendar.current
            let eventDate = calendar.nextDate(after: Date(), matching: dateComponents, matchingPolicy: .nextTime) ?? Date()

            event.startDate = eventDate
            event.endDate = eventDate.addingTimeInterval(30 * 60)

            let rule = EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
            event.addRecurrenceRule(rule)

            do {
              try store.save(event, span: .futureEvents)
              DispatchQueue.main.async { result(true) }
            } catch {
              DispatchQueue.main.async {
                result(FlutterError(code: "SAVE_ERROR", message: error.localizedDescription, details: nil))
              }
            }
          } else {
            DispatchQueue.main.async {
              result(FlutterError(code: "NO_PERMISSION", message: "Calendar access denied", details: nil))
            }
          }
        }
      } else if call.method == "removeEvent" {
        store.requestAccess(to: .event) { granted, error in
          if granted {
            let predicate = store.predicateForEvents(
              withStart: Date.distantPast,
              end: Date.distantFuture,
              calendars: nil
            )
            let events = store.events(matching: predicate).filter { $0.title == "Wordie 学习提醒" }
            for event in events {
              do {
                try store.remove(event, span: .futureEvents)
              } catch {}
            }
          }
          DispatchQueue.main.async { result(true) }
        }
      } else {
        result(FlutterError.notImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
