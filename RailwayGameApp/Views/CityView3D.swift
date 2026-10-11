import GamePresentation
import Observation
import SwiftUI
import UIKit
import WebKit

/// The 3D city view (ARCHITECTURE decision 152): jeantimex/tokyo's web
/// renderer, built from `Web/CityView`, showing the area round Kaohsiung or
/// Taichung Station (decision 161) from Overture's buildings and
/// OpenStreetMap. Since decision 163 the game's website serves the page
/// (``CityViewPage``) and the app opens it there, so it needs the internet.
/// A preview from the settings: it reads nothing of the game, and its
/// traffic and trains are the page's own.
struct CityView3D: View {
    let area: CityViewArea
    @Environment(\.dismiss) private var dismiss
    @State private var host = CityViewHost()

    var body: some View {
        let language = DisplayLanguage.app
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url = URL(string: area.pageAddress) {
                CityWebView(url: url, onLoaded: { host.pageLoaded() }, onFailure: { error in host.loadFailed(error) })
                    .id(host.attempt)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("cityView.web")
            }
            if let message = host.failureText(in: language) {
                // (what went wrong, for a tester to read out, and a way to try again)
                VStack(spacing: 12) {
                    Text(verbatim: message)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("cityView.error")
                    Button {
                        host.retry()
                    } label: {
                        Text(verbatim: language.text("Try Again", "再試一次"))
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("cityView.retry")
                }
                .padding(16)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !host.loaded {
                // until the web view has the page from the website
                ProgressView {
                    Text(verbatim: language.text("Loading the 3D city…", "正在載入 3D 城市…"))
                        .foregroundStyle(.white)
                }
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("cityView.loading")
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
    }
}

/// Whether the web view has the page, and why not when it could not load
/// it.
@MainActor
@Observable
final class CityViewHost {
    /// Whether the web view has loaded the page.
    private(set) var loaded = false
    /// Why the web view could not load the page, when it could not.
    private(set) var loadError: NSError?
    /// Counts the tries: a new one makes a new web view.
    private(set) var attempt = 0

    func pageLoaded() {
        loaded = true
    }

    func loadFailed(_ error: any Error) {
        loadError = error as NSError
    }

    func retry() {
        loadError = nil
        loaded = false
        attempt += 1
    }

    /// What to tell the player when the page did not load; `nil` while all
    /// is well. Without the internet (or the website out of reach), says
    /// so; otherwise WebKit's own error, for a tester to read out.
    func failureText(in language: DisplayLanguage) -> String? {
        guard let error = loadError else { return nil }
        if error.domain == NSURLErrorDomain, Self.offlineCodes.contains(error.code) {
            return language.text(
                "The 3D city loads from the game's website: connect to the internet and try again.",
                "3D 城市要從遊戲官網載入：請連上網路再試一次。"
            )
        }
        return language.text("The 3D page did not load: ", "3D 網頁沒有載入：")
            + "\(error.localizedDescription) (\(error.domain) \(error.code))"
    }

    /// The errors of no network, or of a website out of reach.
    private static let offlineCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
        NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed,
        NSURLErrorDataNotAllowed, NSURLErrorInternationalRoamingOff,
    ]
}

/// The web view of the page. It stays on the city view's own pages
/// (``CityViewPage/opensInView(_:)``): any other link (the website's home
/// page) opens in the browser instead, and a page whose process the
/// system ended (memory) is loaded again.
struct CityWebView: UIViewRepresentable {
    let url: URL
    /// Told when the page has loaded.
    let onLoaded: @MainActor () -> Void
    /// Told why, when the page cannot be loaded.
    let onFailure: @MainActor (any Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded, onFailure: onFailure)
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
        let onLoaded: @MainActor () -> Void
        let onFailure: @MainActor (any Error) -> Void

        init(onLoaded: @escaping @MainActor () -> Void, onFailure: @escaping @MainActor (any Error) -> Void) {
            self.onLoaded = onLoaded
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoaded()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            report(error)
        }

        /// A failure, but not a link this delegate turned away (cancelled).
        private func report(_ error: any Error) {
            let error = error as NSError
            if error.code == NSURLErrorCancelled || (error.domain == "WebKitErrorDomain" && error.code == 102) {
                return
            }
            onFailure(error)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, !CityViewPage.opensInView(url) else {
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
