import Foundation
import UserNotifications

enum UpdateNotificationService {
    static let appointmentPrefix = "redfruit-appointment-"

    static func scheduleAppointment(seriesID: String, title: String, date: Date, isDateUnknown: Bool = false) async {
        if isDateUnknown { return }
        let center = UNUserNotificationCenter.current()
        let identifier = appointmentIdentifier(seriesID: seriesID)
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var triggerDate = components
        triggerDate.hour = 9
        triggerDate.minute = 0
        triggerDate.second = 0
        let fireDate = calendar.date(from: triggerDate)
        let trigger: UNNotificationTrigger
        if let fireDate, fireDate > .now {
            trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        } else if calendar.isDateInToday(date) {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "漫剧记录提醒"
        content.body = "《\(title)》预约日期到了，可以回来查看更新。"
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func cancelAppointment(seriesID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [appointmentIdentifier(seriesID: seriesID)]
        )
    }

    static func appointmentIdentifier(seriesID: String) -> String {
        appointmentPrefix + seriesID
    }
}
