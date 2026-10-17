/// Commands the native menus can ask the web page to run.
/// The raw value is the name `bridge.js` dispatches on.
enum OutlookCommand: String, CaseIterable {
    case newMail
    case search
    case gotoInbox
    case gotoCalendar
    case gotoPeople
    case refresh
}
