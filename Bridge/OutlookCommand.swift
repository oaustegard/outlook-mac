/// Commands the native menus can ask the web page to run.
/// The raw value is the name `bridge.js` and `keymap.json` use.
enum OutlookCommand: String, CaseIterable {
    // Mail
    case newMail
    case reply
    case replyAll
    case forward
    case send
    case delete
    case archive
    case markRead
    case markUnread
    case flag
    case gotoInbox

    // Calendar
    case newEvent
    case calToday
    case calDay
    case calWorkWeek
    case calWeek
    case calMonth
    case gotoCalendar

    // People and Tasks
    case newContact
    case gotoPeople
    case newTask
    case gotoTasks

    // Window and search
    case search
    case refresh
}
