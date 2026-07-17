// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import WebKit

/// Renders card question/answer HTML. Cards are arbitrary HTML/CSS/JS —
/// never render them natively.
struct CardWebView: UIViewRepresentable {
    let html: String
    let css: String
    let mediaSchemeHandler: MediaSchemeHandler

    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(mediaSchemeHandler, forURLScheme: "anki-media")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // `overrideUserInterfaceStyle` keeps the WebView's own idea of
        // light/dark in sync with SwiftUI's — without this, `color-scheme:
        // light dark` in the document below can resolve independently of
        // the (transparent) native background and produce e.g. white text
        // on a white background.
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let document = """
            <html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <style>
            body { background: Canvas; color: CanvasText; }
            \(css)
            </style>
            </head><body>\(html)</body></html>
            """
        // anki-media:/// as the base URL: relative media src="foo.jpg"
        // resolves to anki-media:///foo.jpg, handled by MediaSchemeHandler.
        webView.loadHTMLString(document, baseURL: URL(string: "anki-media:///"))
    }
}
