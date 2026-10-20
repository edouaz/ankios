// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

import UniformTypeIdentifiers
import WebKit

/// Serves files from `collection.media/` under the `anki-media:///` scheme,
/// so card HTML can reference media with plain relative `src="foo.jpg"`
/// (resolved against that base URL by WKWebView itself).
final class MediaSchemeHandler: NSObject, WKURLSchemeHandler {
    private let mediaFolderPath: String

    init(mediaFolderPath: String) {
        self.mediaFolderPath = mediaFolderPath
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, !url.path.isEmpty else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let filename = String(url.path.dropFirst())  // drop the leading "/"
        let fileURL = URL(fileURLWithPath: mediaFolderPath).appendingPathComponent(filename)
        // Card scripts must not use either scheme to read outside its resource directory.
        let root = URL(fileURLWithPath: mediaFolderPath).resolvingSymlinksInPath().path + "/"
        guard fileURL.resolvingSymlinksInPath().path.hasPrefix(root) else {
            task.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mimeType =
            UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let response = URLResponse(
            url: url, mimeType: mimeType, expectedContentLength: data.count,
            textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
