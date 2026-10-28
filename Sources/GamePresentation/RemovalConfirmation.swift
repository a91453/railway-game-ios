// What the panels ask before a removal that one tap would otherwise make
// (UI review 2026-10-28, A): clearing a timetable, taking up a platform or
// a freight yard, removing a station's ridership, leaving a transfer group,
// removing a line's pattern or stop, going back to the standard service
// day. Undo takes each back only until game time moves on, and these are
// made from panels while the game runs, so a stray tap could not be
// undone; the building tool pauses the game (decision 99) and keeps its
// one-tap demolish.

/// A removal a panel confirms first, and the words of its confirmation.
public enum RemovalConfirmation: Hashable, Sendable {
    /// Clearing the timetable of the train named.
    case clearTimetable(train: String)
    /// Taking up the station's platform `number`, counted from 1.
    case removePlatform(number: Int)
    case removeFreightYard
    case removeRidership
    case leaveTransferGroup
    /// Removing the line's pattern titled so.
    case removePattern(title: String)
    /// Removing the line's stop at the station named.
    case removeStop(station: String)
    case standardDay

    /// The question the confirmation asks.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .clearTimetable(let train): language.text("Clear \(train)'s timetable?", "清空 \(train) 的時刻表？")
        case .removePlatform(let number): language.text("Remove platform \(number)?", "拆除第 \(number) 月台？")
        case .removeFreightYard: language.text("Remove the freight yard?", "拆除貨運場？")
        case .removeRidership: language.text("Remove this station's ridership?", "移除這個車站的運量？")
        case .leaveTransferGroup: language.text("Leave the transfer group?", "離開轉乘群組？")
        case .removePattern(let title): language.text("Remove \(title)?", "刪除「\(title)」？")
        case .removeStop(let station): language.text("Remove \(station) from the line?", "把 \(station) 從路線刪除？")
        case .standardDay: language.text("Go back to the standard day?", "回到標準營運日？")
        }
    }

    /// The button that removes it, naming what it does.
    public func button(in language: DisplayLanguage) -> String {
        switch self {
        case .clearTimetable: language.text("Clear Timetable", "清空時刻表")
        case .removePlatform(let number): language.text("Remove Platform \(number)", "拆除第 \(number) 月台")
        case .removeFreightYard: language.text("Remove Freight Yard", "拆除貨運場")
        case .removeRidership: language.text("Remove Ridership", "移除運量")
        case .leaveTransferGroup: language.text("Leave Transfer Group", "離開轉乘群組")
        case .removePattern: language.text("Remove Pattern", "刪除停站模式")
        case .removeStop: language.text("Remove Stop", "刪除停靠站")
        case .standardDay: language.text("Standard Day", "標準營運日")
        }
    }

    /// What else goes with it, under the question; `nil` when nothing does.
    public func message(in language: DisplayLanguage) -> String? {
        switch self {
        case .clearTimetable: language.text("Every stop and time on it goes.", "表上所有停靠站與時刻都會刪除。")
        case .removePlatform: nil
        case .removeFreightYard: language.text("The goods waiting there go with it.", "場內等著運送的貨物也會一起消失。")
        case .removeRidership: language.text("Passengers already waiting there stay.", "已經在等車的旅客會留下。")
        case .leaveTransferGroup: nil
        case .removePattern: language.text("Its trains finish the trip they are on.", "這個模式的列車會跑完目前這一趟。")
        case .removeStop: language.text("Passengers waiting for a train there leave.", "等著搭車去這一站的旅客會離開。")
        case .standardDay: language.text("The bands you split or changed go.", "你切分或調整過的時段都會刪除。")
        }
    }
}
