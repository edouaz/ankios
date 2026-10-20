import AppKit
import WebKit

// Use the production resource handler and document, with all HTTP(S) blocked.
let app = NSApplication.shared
let assets = CommandLine.arguments[1]
let fixtures = CommandLine.arguments[2]
let configuration = WKWebViewConfiguration()
configuration.setURLSchemeHandler(MediaSchemeHandler(mediaFolderPath: assets), forURLScheme: "anki-assets")
configuration.setURLSchemeHandler(MediaSchemeHandler(mediaFolderPath: fixtures), forURLScheme: "anki-media")
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 390, height: 700), configuration: configuration)
let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = webView
let cases = ["False-False", "False-True", "True-False", "True-True"]
var index = 0
var attempts = 0
func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}
func loadNext() {
    attempts = 0
    let html = try! String(contentsOfFile: "\(fixtures)/\(cases[index]).html", encoding: .utf8)
    // Start a stale navigation immediately before the real card to test replacement.
    webView.loadHTMLString("<p>stale</p>", baseURL: URL(string: "anki-media:///"))
    webView.loadHTMLString(html, baseURL: URL(string: "anki-media:///"))
}
let check = #"""
(() => {
    const containers = document.querySelectorAll('mjx-container');
    if (containers.length !== 9 || document.fonts.status !== 'loaded') return false;
    const check = (condition, message) => { if (!condition) throw Error(message); };
    check(!document.querySelector('mjx-merror, [data-mjx-error]'), 'TeX error');
    check(document.querySelectorAll('mjx-container[display="true"]').length === 4, 'display math');
    check(document.querySelector('mjx-mfrac') && document.querySelector('mjx-msqrt') && document.querySelector('mjx-mtable'), 'structures');
    check(document.querySelector('.cloze') && window.templateRan === 1, 'cloze/template scripts');
    check([...MathJax.startup.document.math].some(m => m.math === (window.expectedAnswer ? 'x=2' : 'x=[...]')), 'cloze face');
    check(document.querySelector('#media').naturalWidth === 12, 'relative media');
    check(document.querySelector('#latex').naturalWidth === 12, 'desktop LaTeX image');
    check(document.body.classList.contains('card') && getComputedStyle(document.body).textAlign === 'center', 'Anki CSS');
    check(document.body.classList.contains('nightMode') === window.expectedDark && document.documentElement.classList.contains('nightMode') === window.expectedDark, 'night mode classes');
    check(!window.expectedDark || getComputedStyle(document.body).color === 'rgb(240, 240, 240)', 'night mode CSS');
    check(document.fonts.size > 0 && [...document.fonts].some(f => f.status === 'loaded'), 'local fonts');
    check(MathJax.config.loader.paths.mathjax === 'anki-assets:///mathjax', 'local loader');
    return true;
})()
"""#
WKContentRuleListStore.default().compileContentRuleList(
    forIdentifier: "MathJaxOfflineTest",
    encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
) { rules, error in
    guard let rules, error == nil else { fail("HTTP blocking: \(String(describing: error))") }
    configuration.userContentController.add(rules)
    loadNext()
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { timer in
        attempts += 1
        if attempts > 150 { fail("Timeout: \(cases[index])") }
        webView.evaluateJavaScript(check) { value, error in
            if let error { fail("\(cases[index]): \(error)") }
            guard value as? Bool == true else { return }
            print("PASS: \(cases[index]) (HTTP blocked)")
            index += 1
            if index == cases.count {
                timer.invalidate()
                exit(0)
            }
            loadNext()
        }
    }
}
app.run()
