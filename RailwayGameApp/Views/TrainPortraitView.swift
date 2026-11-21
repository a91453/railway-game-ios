import Foundation
import GamePresentation
import SwiftUI
import UIKit

/// TRAIN-IDENTITY: a train's picture, the 3D map's own model of it
/// (``TrainPortrait``), painted once off the main thread and kept; while
/// it is being painted, and for a type the map has no model of, the
/// drawn stand-in (``CatalogTrain``).
struct TrainPortraitView: View {
    /// The key the map draws it by (``TrainPortrait/key(type:performance:)``),
    /// `nil` for none.
    let key: String?
    let cars: Int
    /// The stand-in's stripe.
    let stripe: Color
    var dimmed = false
    @State private var image: UIImage?
    @State private var shownKey: String?

    var body: some View {
        let id = "\(key ?? "-")|\(cars)"
        ZStack {
            if let image, shownKey == id {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else {
                CatalogTrain(stripe: stripe, cars: cars)
            }
        }
        .opacity(dimmed ? 0.4 : 1)
        .accessibilityHidden(true)
        .task(id: id) {
            guard let key else {
                image = nil
                return
            }
            let painted = await TrainPortraitImages.image(key: key, cars: cars)
            image = painted
            shownKey = id
        }
    }
}

/// The pictures painted so far, by key and cars: kept on the main actor,
/// the picture itself made off it.
@MainActor
enum TrainPortraitImages {
    private static let cache = NSCache<NSString, UIImage>()

    /// Decision 338: the train pack's sets drawn as the map draws them
    /// while the pack is locked.
    private static var locked: Set<String> {
        let defaults = UserDefaults.standard
        let unlocked = TrainPack.isUnlocked(testBuild: TestBuild.isTest, switchOn: defaults.bool(forKey: TrainPack.testUnlockKey))
        return TrainPack.locked(unlocked: unlocked, pushPullE1000: defaults.bool(forKey: TrainPack.pushPullE1000Key))
    }

    static func image(key: String, cars: Int) async -> UIImage? {
        let locked = locked
        let name = "\(key)|\(cars)|\(locked.sorted().joined(separator: ","))" as NSString
        if let made = cache.object(forKey: name) { return made }
        let portrait = await Task.detached(priority: .userInitiated) {
            TrainPortrait.make(key: key, cars: cars, locked: locked)
        }.value
        let made = paint(portrait)
        if let made { cache.setObject(made, forKey: name) }
        return made
    }

    /// The picture's pixels as an image, two pixels to a point.
    private static func paint(_ portrait: TrainPortrait?) -> UIImage? {
        guard let portrait, portrait.width > 0, portrait.height > 0,
              let provider = CGDataProvider(data: Data(portrait.rgba) as CFData),
              let image = CGImage(width: portrait.width, height: portrait.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: portrait.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }
}
