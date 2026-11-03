import GameCore

/// One name offered under a new station's name on a real-world map
/// (decision 569): a tap puts it in the name field, where the player can
/// change it.
public struct StationNameChoice: Hashable, Sendable, Identifiable {
    /// Where the name comes from.
    public enum Kind: Hashable, Sendable {
        case realStation
        case place
        case landmark(StationLandmarks.Kind)
        case attraction
        case road
        case crossing
    }

    public let name: String
    public let kind: Kind

    public var id: String { name }

    /// What it is, for VoiceOver after the name: 「臺灣大學，大學」.
    public func kindText(in language: DisplayLanguage) -> String {
        switch kind {
        case .realStation: language.text("Railway station", "火車站")
        case .place: language.text("Place", "地名")
        case .landmark(.university): language.text("University", "大學")
        case .landmark(.school): language.text("High school", "高中")
        case .landmark(.hospital): language.text("Hospital", "醫院")
        case .landmark(.park): language.text("Park", "公園")
        case .landmark(.market): language.text("Market", "商圈")
        case .landmark(.mall): language.text("Shopping", "百貨")
        case .attraction: language.text("Sight", "景點")
        case .road: language.text("Road", "路名")
        case .crossing: language.text("Crossroads", "路口")
        }
    }
}
