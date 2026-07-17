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
        let document = """
            <html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <style>\(css)</style>
            </head><body>\(html)</body></html>
            """
        // anki-media:/// as the base URL: relative media src="foo.jpg"
        // resolves to anki-media:///foo.jpg, handled by MediaSchemeHandler.
        webView.loadHTMLString(document, baseURL: URL(string: "anki-media:///"))
    }
}
