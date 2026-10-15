import Foundation

/// The embedded noVNC (see Resources/noVNC/VERSION.txt), served to the web
/// view by a local scheme handler: nothing is loaded from the network.
public enum NoVNCResources {
    public static var directory: URL? {
        Bundle.module.url(forResource: "noVNC", withExtension: nil)
    }

    /// The file for a path of the local scheme (`/core/rfb.js`), only inside
    /// the noVNC folder: `..` or an absolute path outside is refused.
    public static func file(forPath path: String, in directory: URL) -> URL? {
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !relative.isEmpty, !relative.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        let candidate = directory.appending(path: relative).standardizedFileURL
        let root = directory.standardizedFileURL.path(percentEncoded: false)
        guard candidate.path(percentEncoded: false).hasPrefix(root.hasSuffix("/") ? root : root + "/") else { return nil }
        return candidate
    }

    public static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": "text/html"
        case "js", "mjs": "text/javascript"
        case "css": "text/css"
        case "png": "image/png"
        case "svg": "image/svg+xml"
        default: "application/octet-stream"
        }
    }
}
