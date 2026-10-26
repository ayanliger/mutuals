# Mutuals

[![Tests](https://github.com/ayanliger/mutuals/actions/workflows/tests.yml/badge.svg)](https://github.com/ayanliger/mutuals/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![iOS 18+](https://img.shields.io/badge/iOS-18%2B-000000?logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-0071E3?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Xcode 26+](https://img.shields.io/badge/Xcode-26%2B-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![Dependencies: none](https://img.shields.io/badge/dependencies-none-brightgreen)](MutualsCore/Package.swift)

An iPhone app that lists the Instagram accounts you follow that don't follow you back, with the people who used to follow you at the top. It works from the data export Instagram gives you, so there is no login, no ads and no network access.

<p>
  <img src="docs/overview.png" width="270" alt="Overview listing the accounts that unfollowed you">
  <img src="docs/personal.png" width="270" alt="Accounts that look like people you know">
</p>

## How it works

Instagram doesn't say who unfollowed you, but its data export contains your followers and following lists with the date each follow started. Mutuals keeps every export you import and compares each one with the ones before it. An account that followed you in an earlier export, doesn't follow you in the latest one, and that you still follow goes under Unfollowed you. Accounts that changed username are matched by account id or follow date.

The first export has no history to compare against, so the app looks for other signs that an account belongs to a person rather than a creator: your close friends list, follow requests, stories you hide from them, and when you followed them. If most of the accounts you followed in the same period follow you back, the ones that don't are likely people you know.

The Quiet list is for cleaning up pages. When the export includes your activity, the app finds the accounts you follow that haven't shown up in it for a period you pick (six months to three years): no likes, comments, story likes or saves, and no posts or videos you viewed. Those are often pages that stopped posting. The export can't tell an account that stopped posting from one you scroll past, and Instagram keeps the viewed-posts log for a limited time, so the list says how far back each log goes. Only one date per account is kept, not the likes and views themselves.

The app never unfollows anyone. Tapping an account opens its profile in Instagram, and when you come back the app asks whether you unfollowed. The next export confirms it.

## Getting the export

1. In Instagram, go to Accounts Center > Your information and permissions > Export your information.
2. Tap Create export, choose your Instagram account, then Export to device.
3. Under Customize information, select Followers and following.
4. For the Quiet list, also select your likes, comments, saved posts, story interactions and ads information. None of them include photos.
5. Set the date range to All time and the format to JSON.
6. When Instagram notifies you, download the zip and import it in Mutuals, or share it to the app from Files.

Importing a new export every week or two builds the history. An export with activity made soon after one without can have identical lists; the app then adds the activity to the export it already has. Older exports can be imported too; the app sorts them by date. HTML exports are read as well, but they have no follow dates, so renames and follow periods can't be detected from them.

## Building

You need Xcode 26 or later. The app runs on iOS 18 and later.

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your team ID and a bundle ID prefix.
2. Open `Mutuals.xcodeproj`, select your iPhone and run.

With a free Apple developer account the installed app expires after 7 days. Running it from Xcode again renews it and keeps your data.

Export parsing and the comparisons live in the `MutualsCore` Swift package, which has its own tests. CI runs them on every push:

```sh
swift test --package-path MutualsCore
```

Debug builds accept launch arguments for working in the simulator: `-sample` loads demo data, `-import <path>` imports a file at launch, and `-route <screen>` opens a screen (`unfollowed`, `personal`, `rest`, `kept`, `requests`, `quiet`, `history`, `snapshot` or `about`).

## Limitations

Instagram changes the export format now and then. The August 2026 change put usernames under labels written in the account's language ("Nome de usuário" in Portuguese), so the parser finds the username field by the shape of its values instead of its label. If an import fails, open an issue describing the file's structure, without your data.

The follow-period signal is a heuristic. Celebrities you followed in the same months as your friends can show up under Likely personal; swipe right on them to keep them out of the lists.

## License

MIT
