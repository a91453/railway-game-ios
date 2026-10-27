import Foundation
import GamePresentation
import SwiftUI
import UIKit

/// Decision 434: the demo mode's train showcase, full screen: the trains
/// picked laid side by side on open ground (``Map3DShowcase``), to turn
/// round, come close to and photograph. One finger turns the camera round
/// them, a pinch comes closer, two fingers move it; the camera's ready
/// views, the time of day, near or far models and a turntable are under
/// the picture, and "Hide Buttons" leaves only the trains until the
/// picture is tapped. Its photos are the 3D map's (decision 403, 續二).
struct TrainShowcaseScreen: View {
    let close: () -> Void
    @State private var selection = Map3DShowcase.Selection()
    @State private var far = false
    @State private var light = Map3DShowcase.Light.day
    /// The ready view asked for last, and how many times one was asked
    /// for, so the same one asked again moves the camera back to it.
    @State private var cameraView = Map3DShowcase.View.closeUp
    @State private var viewRequests = 0
    /// Off when opened: with Reduce Motion it never starts by itself.
    @State private var turntable = false
    @State private var controlsHidden = false
    @State private var picking = false
    /// The models, made once off the main thread before the stage shows.
    @State private var ready = false
    @State private var photo = Map3DPhotoState()
    @State private var cameraLink = Map3DCameraLink()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Map3DQuality.key) private var quality: Map3DQuality = .forThisDevice

    var body: some View {
        let language = DisplayLanguage.app
        ZStack {
            if ready {
                TrainShowcaseStage(rows: Map3DShowcase.layout(keys: selection.keys, cars: selection.cars, far: far),
                                   cameraView: cameraView, viewRequests: viewRequests, light: light, turntable: turntable,
                                   quality: quality.drawn, cameraLink: cameraLink)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("trainShowcase.view")
            } else {
                Theme.background.ignoresSafeArea()
                ProgressView()
                    .controlSize(.large)
            }
            if controlsHidden {
                // As the idle mode's curtain (decision 414): a tap anywhere
                // brings the buttons back, and VoiceOver can press it. A
                // tap recognizer on the Metal view never heard the full
                // lane's tap (run 40502803331).
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { controlsHidden = false }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(verbatim: language.text("Show Buttons", "顯示按鈕")))
                    .accessibilityAction { controlsHidden = false }
                    .accessibilityIdentifier("trainShowcase.reveal")
            } else {
                VStack(spacing: 8) {
                    topBar(language)
                        .transition(.card(from: .top, reduceMotion: reduceMotion))
                    Spacer()
                    controls(language)
                        .transition(.card(from: .bottom, reduceMotion: reduceMotion))
                }
                .padding(CGFloat(HUDMargins.edge))
            }
        }
        // As the reference's garage: Reduce Motion turned on stops it.
        .onChange(of: reduceMotion) { _, reduce in
            if reduce { turntable = false }
        }
        .task {
            // Every train's models, made once (as the 3D map's are).
            _ = await Task.detached(priority: .userInitiated) { Map3DModelPack.standard.models.count }.value
            ready = true
        }
        .sheet(isPresented: $picking) {
            TrainShowcasePicker(selection: $selection, language: language)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $photo.snapshot) { snapshot in
            Map3DSnapshotSheet(snapshot: snapshot, language: language)
        }
    }

    private func topBar(_ language: DisplayLanguage) -> some View {
        HStack(alignment: .top) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(Text(verbatim: language.text("Close", "關閉")))
            .accessibilityIdentifier("trainShowcase.close")
            Spacer(minLength: 8)
            Button(action: takePhoto) {
                Image(systemName: "camera.fill")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(Text(verbatim: language.text("Take Photo", "拍照")))
            .accessibilityHint(Text(verbatim: language.text("Takes a photo of the trains to save or share.", "拍下列車的照片，可以存起來或分享。")))
            .accessibilityIdentifier("trainShowcase.photo")
            Button {
                controlsHidden = true
            } label: {
                Image(systemName: "eye.slash")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(Text(verbatim: language.text("Hide Buttons", "隱藏按鈕")))
            .accessibilityHint(Text(verbatim: language.text("Leaves only the trains on screen. Tap the picture to bring the buttons back.",
                                                            "畫面只留下列車。點一下畫面，按鈕就回來。")))
            .accessibilityIdentifier("trainShowcase.hide")
        }
    }

    private func controls(_ language: DisplayLanguage) -> some View {
        VStack(spacing: 10) {
            Picker(selection: $light) {
                ForEach(Map3DShowcase.Light.allCases, id: \.self) { light in
                    Text(verbatim: light.name(in: language)).tag(light)
                }
            } label: {
                Text(verbatim: language.text("Time of Day", "時段"))
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("trainShowcase.light")
            HStack(spacing: 8) {
                Picker(selection: $far) {
                    Text(verbatim: language.text("Near", "近景")).tag(false)
                    Text(verbatim: language.text("Far", "遠景")).tag(true)
                } label: {
                    Text(verbatim: language.text("Detail", "細節"))
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("trainShowcase.far")
                Toggle(isOn: $turntable) {
                    Label {
                        Text(verbatim: language.text("Turntable", "轉台"))
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .toggleStyle(.button)
                .accessibilityHint(Text(verbatim: language.text("Turns the camera slowly round the trains.", "鏡頭慢慢繞著列車轉。")))
                .accessibilityIdentifier("trainShowcase.turntable")
            }
            HStack(spacing: 8) {
                ForEach(Map3DShowcase.View.allCases, id: \.self) { view in
                    Button {
                        cameraView = view
                        viewRequests &+= 1
                    } label: {
                        Text(verbatim: view.name(in: language))
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("trainShowcase.camera.\(view.rawValue)")
                }
                Button {
                    picking = true
                } label: {
                    Label {
                        Text(verbatim: language.text("Trains", "選車"))
                    } icon: {
                        Image(systemName: "tram")
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(Text(verbatim: language.text("Chooses the trains shown and their cars.", "選要展示的列車與節數。")))
                .accessibilityIdentifier("trainShowcase.pick")
            }
        }
        .padding(12)
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trainShowcase.controls")
    }

    /// The picture as drawn next, with the game's name in its corner
    /// (``Map3DShowcase/photoCredit(in:)``), shared as the 3D map's photo.
    private func takePhoto() {
        guard let view = cameraLink.view else { return }
        let language = DisplayLanguage.app
        let title = language.text("Train Showcase", "列車展示")
        let credit = Map3DShowcase.photoCredit(in: language)
        let photo = photo
        view.capture { image in
            guard let image else { return }
            photo.snapshot = Map3DSnapshot(image: Map3DPreviewScreen.credited(image, credit), title: title)
        }
    }
}

/// Decision 434: the showcase's Metal view. It takes only what to show
/// (the rows, the light) and how to look at it, so the train pack's 3D
/// preview can use it as it is. The ground and the cars are made again
/// only when the rows change; turning the camera makes nothing again.
struct TrainShowcaseStage: UIViewRepresentable {
    let rows: [Map3DShowcase.Row]
    let cameraView: Map3DShowcase.View
    let viewRequests: Int
    let light: Map3DShowcase.Light
    let turntable: Bool
    let quality: Map3DQuality
    let cameraLink: Map3DCameraLink

    /// Where the ground goes among the Metal view's chunks.
    private static let groundKey = Map3DStreaming.Key(column: 0, row: 0)

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        guard let view = Map3DMetalView.make(samples: quality.samplesPerPixel) else {
            let label = UILabel()
            label.text = DisplayLanguage.app.text("3D isn't available on this device.", "這台裝置無法顯示 3D。")
            label.textAlignment = .center
            label.numberOfLines = 0
            return label
        }
        context.coordinator.view = view
        cameraLink.view = view
        view.useModels(Map3DModelPack.standard)
        let orbit = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.orbit(_:)))
        orbit.maximumNumberOfTouches = 1
        let move = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.move(_:)))
        move.minimumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        for recognizer in [orbit, move, pinch] as [UIGestureRecognizer] {
            recognizer.delegate = context.coordinator
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? Map3DMetalView else { return }
        let coordinator = context.coordinator
        view.lighting = light.lighting
        view.quality = quality
        view.reduceMotion = context.environment.accessibilityReduceMotion
        if coordinator.shownRows != rows {
            let first = coordinator.shownRows == nil
            coordinator.shownRows = rows
            view.place([Map3DShowcase.ground(rows)], at: [Self.groundKey])
            let frame = Map3DShowcase.frame(rows)
            view.trains = { _, _ in frame }
            if first { show(cameraView, in: view) }
        }
        if coordinator.shownRequests != viewRequests {
            coordinator.shownRequests = viewRequests
            show(cameraView, in: view)
        }
        coordinator.turn(turntable)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.turn(false)
    }

    /// The camera of `cameraView` at once, worked out at the next frame
    /// from the view as laid out.
    private func show(_ cameraView: Map3DShowcase.View, in view: Map3DMetalView) {
        let rows = rows
        view.fly(reduceMotion: true) { camera in
            Map3DShowcase.camera(cameraView, rows: rows, viewport: camera.viewport)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: Map3DMetalView?
        var shownRows: [Map3DShowcase.Row]?
        var shownRequests = 0
        /// The turntable, a frame at a time.
        private var turning: CADisplayLink?
        private var lastTurn: CFTimeInterval?

        func turn(_ on: Bool) {
            guard on != (turning != nil) else { return }
            if on {
                let link = CADisplayLink(target: self, selector: #selector(turnStep(_:)))
                link.add(to: .main, forMode: .common)
                turning = link
            } else {
                turning?.invalidate()
                turning = nil
                lastTurn = nil
            }
        }

        @objc private func turnStep(_ link: CADisplayLink) {
            guard let view else { return }
            let elapsed = lastTurn.map { link.timestamp - $0 } ?? 0
            lastTurn = link.timestamp
            view.camera = Map3DShowcase.turning(view.camera, seconds: min(elapsed, 0.1))
        }

        @objc func orbit(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            let moved = recognizer.translation(in: view)
            view.camera = Map3DShowcase.orbited(view.camera, dx: Float(moved.x), dy: Float(moved.y))
            recognizer.setTranslation(.zero, in: view)
        }

        @objc func move(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            let moved = recognizer.translation(in: view)
            view.camera = view.camera.panned(dx: Float(moved.x), dy: Float(moved.y))
            recognizer.setTranslation(.zero, in: view)
        }

        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view else { return }
            view.camera = Map3DShowcase.zoomed(view.camera, by: Float(recognizer.scale))
            recognizer.scale = 1
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// Decision 434: the trains to show, by kind, and the cars of those shown;
/// at most ``Map3DShowcase/mostRows`` at once.
private struct TrainShowcasePicker: View {
    @Binding var selection: Map3DShowcase.Selection
    let language: DisplayLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(selection.keys, id: \.self) { key in
                        if let entry = Map3DShowcase.entry(key) {
                            carsRow(entry)
                        }
                    }
                } header: {
                    Text(verbatim: language.text("Shown", "展示中"))
                } footer: {
                    Text(verbatim: language.text("Shows up to \(Map3DShowcase.mostRows) trains at once. To add another, take one off first.",
                                                 "一次最多展示 \(Map3DShowcase.mostRows) 列。要加別的車，先取消一列。"))
                }
                ForEach(Map3DShowcase.Category.allCases, id: \.self) { category in
                    Section {
                        ForEach(Map3DShowcase.catalog.filter { $0.category == category }) { entry in
                            pickRow(entry)
                        }
                    } header: {
                        Text(verbatim: category.name(in: language))
                    }
                }
            }
            .navigationTitle(language.text("Trains", "選車"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Done", "完成")) { dismiss() }
                        .accessibilityIdentifier("trainShowcase.pick.done")
                }
            }
        }
    }

    private func carsRow(_ entry: Map3DShowcase.Entry) -> some View {
        let cars = selection.cars(of: entry.key)
        let label = Text(verbatim: entry.name(in: language) + language.text(" · \(cars) cars", "・\(cars) 節"))
        return Group {
            if entry.fewestCars == entry.mostCars {
                label
            } else {
                Stepper(value: Binding(get: { selection.cars(of: entry.key) }, set: { selection.setCars($0, of: entry.key) }),
                        in: entry.fewestCars...entry.mostCars) {
                    label
                }
            }
        }
        .accessibilityIdentifier("trainShowcase.cars.\(entry.key)")
    }

    private func pickRow(_ entry: Map3DShowcase.Entry) -> some View {
        let picked = selection.keys.contains(entry.key)
        return Button {
            selection.toggle(entry.key)
        } label: {
            HStack {
                Text(verbatim: entry.name(in: language))
                    .foregroundStyle(.primary)
                Spacer()
                if picked {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .disabled(!picked && selection.isFull)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("trainShowcase.pick.\(entry.key)")
    }
}
