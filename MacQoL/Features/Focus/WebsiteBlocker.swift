import Foundation

/// Blocks websites by adding entries to /etc/hosts via admin AppleScript
final class WebsiteBlocker {
    private let marker = "# MacQoL Focus Mode"
    private var isBlocking = false

    func block(websites: [String]) {
        guard !websites.isEmpty else { return }

        let entries = websites.map { "127.0.0.1 \($0)\n127.0.0.1 www.\($0)" }.joined(separator: "\n")
        let block = "\n\(marker)\n\(entries)\n\(marker) END\n"

        let script = """
        do shell script "echo '\(block.replacingOccurrences(of: "'", with: "'\\''"))' >> /etc/hosts" with administrator privileges
        """

        runAppleScript(script)
        flushDNSCache()
        isBlocking = true
    }

    func unblock() {
        guard isBlocking else { return }

        let script = """
        do shell script "sed -i '' '/\(marker)/,/\(marker) END/d' /etc/hosts" with administrator privileges
        """

        runAppleScript(script)
        flushDNSCache()
        isBlocking = false
    }

    private func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript error: \(error)")
        }
    }

    private func flushDNSCache() {
        let task = Process()
        task.launchPath = "/usr/bin/dscacheutil"
        task.arguments = ["-flushcache"]
        try? task.run()
    }
}
