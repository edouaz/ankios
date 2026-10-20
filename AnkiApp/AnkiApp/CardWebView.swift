// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import SwiftUI
import WebKit

/// Renders card question/answer HTML. Cards are arbitrary HTML/CSS/JS —
/// never render them natively.
struct CardWebView: UIViewRepresentable {
    let html: String
    let css: String
    let templateIndex: UInt32
    let mediaSchemeHandler: MediaSchemeHandler

    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(mediaSchemeHandler, forURLScheme: "anki-media")
        config.setURLSchemeHandler(
            MediaSchemeHandler(mediaFolderPath: Bundle.main.bundleURL
                .appendingPathComponent("CardAssets").path),
            forURLScheme: "anki-assets")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Keep WebKit's native appearance and document colors in sync with SwiftUI.
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let document = """
            <!doctype html>
            <html class="mobile \(colorScheme == .dark ? "nightMode" : "")"><head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="\(colorScheme == .dark ? "dark" : "light")">
            <style>
            body { background: Canvas; color: CanvasText; }
            /* Match Anki: override the standard white .card in night mode. */
            body.nightMode { background-color: Canvas; color: CanvasText; }
            \(css)
            </style>
            <script src="anki-assets:///mathjax-config.js"></script>
            <script defer src="anki-assets:///mathjax/tex-chtml.js"></script>
            </head><body class="card card\(Int(templateIndex) + 1) \(colorScheme == .dark ? "nightMode" : "")">
            <div id="qa">\(html)</div>
            <script>
            document.addEventListener("DOMContentLoaded", function () {
                MathJax.startup.promise.then(function () {
                    return MathJax.typesetPromise([document.getElementById("qa")]);
                }).catch(function (error) { console.error("MathJax:", error); });
            });
            </script>
            </body></html>
            """
        // anki-media:/// as the base URL: relative media src="foo.jpg"
        // resolves to anki-media:///foo.jpg, handled by MediaSchemeHandler.
        webView.loadHTMLString(document, baseURL: URL(string: "anki-media:///"))
    }
}
