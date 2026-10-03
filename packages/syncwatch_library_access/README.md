# macOS library access

The native folder picker grants sandbox access for the running process; saving
its path alone does not restore access on the next launch. This plugin creates
a read-only app-scoped bookmark after either existing library folder picker.
AppController resolves it before the first scan and renews stale bookmark data.
Manual path edits remain unchanged and cannot restore a different saved folder.
An older installation without a bookmark needs one normal folder selection.

The restored URL holds one security scope until plugin teardown, balanced with
stopAccessingSecurityScopedResource. Keeping it for the session preserves the
currently playing file when another library is chosen in player settings.
Creating bookmarks for picker results does not start additional scopes. Failed
or revoked bookmarks retain the path and existing folder-selection workflow;
resolution opens no new dialog. Bookmark data stays in local preferences.

Desktop hosts are generated. After generating/configuring the macOS host, run
`python3 scripts/enable_library_bookmarks_macos.py` before building. It enables
app-scoped bookmarks in both entitlements files while requiring sandbox and
existing user-selected file access. Do not disable sandbox or add broad path
exceptions. Both Swift Package Manager and CocoaPods integration are provided.

Validate the ordinary signed release app: select a folder outside its container,
quit/relaunch, confirm the same files, play/seek/preview, and repeat after changing
folders through Settings. Verify picker cancellation and manual path editing.
Run `flutter test test/library_access_test.dart` for persistence/error handling.
Keep runtime evidence outside the checkout.

Apple references: [bookmark creation](https://developer.apple.com/documentation/foundation/nsurl/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:))
and [sandbox bookmark entitlements](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access).
