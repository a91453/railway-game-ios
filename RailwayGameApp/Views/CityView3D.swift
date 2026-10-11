import GamePresentation
import Network
import Observation
import SwiftUI
import UIKit
import WebKit

/// The 3D city view (ARCHITECTURE decision 152): jeantimex/tokyo's web
/// renderer, built from `Web/CityView` into the bundled folder
/// `Resources/CityView`, showing the area round Kaohsiung or Taichung
/// Station (decision 161) from Overture's buildings and OpenStreetMap. A
/// preview from the settings: it reads nothing of the game, and its traffic
/// and trains are the page's own.
struct CityView3D: View {
    let area: CityViewArea
    @Environment(\.dismiss) private var dismiss
    @State private var host = CityViewHost()

    var body: some View {
        let language = DisplayLanguage.app
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url = host.url {
                CityWebView(url: url)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("cityView.web")
            } else if host.failed {
                Text(verbatim: language.text("The 3D view could not start.", "3D 畫面無法啟動。"))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .padding(12)
            .accessibilityLabel(Text(verbatim: language.text("Close", "關閉")))
            .accessibilityIdentifier("cityView.close")
        }
        .statusBarHidden()
        .task { host.start(area: area) }
        .onDisappear { host.stop() }
    }
}

/// Starts the loopback server for the bundled page and gives the web view
/// its address.
@MainActor
@Observable
final class CityViewHost {
    private(set) var url: URL?
    private(set) var failed = false
    @ObservationIgnored private var server: CityViewServer?

    func start(area: CityViewArea) {
        guard server == nil else { return }
        guard let root = Bundle.main.url(forResource: "CityView", withExtension: nil),
              let server = try? CityViewServer(root: root)
        else {
            failed = true
            return
        }
        self.server = server
        server.start { [weak self] port in
            guard let self else { return }
            if let port {
                url = URL(string: "http://localhost:\(port)\(area.startPath)")
            } else {
                failed = true
            }
        }
    }

    func stop() {
        server?.stop()
        server = nil
    }
}

/// A small HTTP server for one folder, listening on the loopback address
/// only (nothing on the network can reach it), on a port the system picks.
/// It answers each request with the file and closes the connection
/// (``CityViewServing`` decides which file and writes the head). Its
/// listener and connections all run on `queue`.
final class CityViewServer: @unchecked Sendable {
    private let listener: NWListener
    private let root: URL
    private let queue = DispatchQueue(label: "io.github.a91453.RailwayGame.CityViewServer")

    init(root: URL) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.acceptLocalOnly = true
        listener = try NWListener(using: parameters)
        self.root = root.standardizedFileURL
    }

    /// Starts listening; `ready` gets the port, or `nil` when the listener
    /// failed, on the main actor.
    func start(ready: @escaping @MainActor @Sendable (UInt16?) -> Void) {
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let port = self?.listener.port?.rawValue
                Task { @MainActor in ready(port) }
            case .failed:
                Task { @MainActor in ready(nil) }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, head: Data())
    }

    /// Reads until the end of the request's head.
    private func receive(on connection: NWConnection, head: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var head = head
            if let data {
                head.append(data)
            }
            if head.range(of: Data("\r\n\r\n".utf8)) != nil {
                answer(on: connection, head: String(decoding: head, as: UTF8.self))
            } else if isComplete || error != nil || head.count > 65_536 {
                connection.cancel()
            } else {
                receive(on: connection, head: head)
            }
        }
    }

    private func answer(on connection: NWConnection, head: String) {
        var body = Data()
        var type: String?
        if let file = CityViewServing.file(requestHead: head) {
            let url = root.appendingPathComponent(file).standardizedFileURL
            if url.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                body = data
                type = CityViewServing.contentType(of: file)
            }
        }
        var reply = CityViewServing.responseHead(contentType: type, length: body.count)
        if !CityViewServing.isHead(head) {
            reply.append(body)
        }
        connection.send(content: reply, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// The web view of the page. It stays on the loopback page: a link out of
/// it (the source's GitHub link) opens in the browser instead, and a page
/// whose process the system ended (memory) is loaded again.
struct CityWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.allowsBackForwardNavigationGestures = false
        view.isInspectable = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, let host = url.host, host != "localhost" else {
                return .allow
            }
            if url.scheme == "https" {
                _ = await UIApplication.shared.open(url)
            }
            return .cancel
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}
