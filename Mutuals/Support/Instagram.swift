import Foundation

enum Instagram {
    /// Opens the profile in the Instagram app. Usernames are limited to
    /// letters, digits, periods and underscores, so they need no escaping.
    static func profile(_ username: String) -> URL {
        URL(string: "instagram://user?username=\(username)")!
    }

    static func web(_ username: String) -> URL {
        URL(string: "https://www.instagram.com/\(username)/")!
    }

    /// Accounts Center's "Export your information" page.
    static let exportPage = URL(string: "https://accountscenter.instagram.com/info_and_permissions/dyi/")!
}
