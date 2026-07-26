# Known issues

Accepted-for-now bugs (with everything already learned so a future fix doesn't
start from zero) and deferred cleanups.

## Deferred cleanup: `file_info` is nearly redundant on the wire

Since the readiness gate shipped, presence carries each member's
`loaded_file_name` (replays to joiners, dies with the connection) and canonical
media identity lives on the room row. The only thing `file_info` still carries
that presence does not is each member's **duration**, feeding the soft "same
name, different length" warning. Settled recommendation (2026-07-26): fold a
`loaded_duration_ms` into presence and delete `file_info` entirely — including
the synthesized `FileInfoEvent` in `_handleStateResponse`
(`lib/sync/sync_service.dart`) — in one move, not a half-migration. Nothing is
blocked meanwhile.

## Cursor flicker over the room screen in YouTube mode (macOS)

**Symptom:** whenever the pointer moves over the video area or the media
controls while a YouTube video is embedded, the cursor flickers between the
default arrow and the pointing hand. Local-file mode is unaffected. Reported
2026-07-27; user has chosen to live with it for now.

**Why only YouTube mode:** local video renders as a Flutter texture
(media_kit), so Flutter owns the whole surface. The YouTube embed
(`youtube_player_flutter` → `flutter_inappwebview`) is a **macOS platform
view** — a real `WKWebView` `NSView` inside the window. AppKit delivers mouse
tracking to that view directly, *below Flutter's event layer*: WKWebView
re-asserts the arrow cursor on mouse moves while FlutterView sets the pointing
hand for hovered buttons, and the two alternate → flicker.

**Ruled out (don't retry these):**

- **Dart-side `IgnorePointer` / `MouseRegion` around the embed** — cannot
  work; the fight happens in AppKit, beneath Flutter's event pipeline.
  `RawYoutubePlayer` inside the package *already* wraps its `InAppWebView` in
  `IgnorePointer(ignoring: true)`, and its player HTML sets
  `pointer-events: none` on the whole page, so DOM hover inside the webview
  was never the source either.
- **`flutter_inappwebview` settings** — no interaction/cursor-related setting
  exists in the macOS implementation (checked 1.1.2 sources).
- **`pointer_interceptor`** — has no macOS support
  ([flutter/flutter#162662](https://github.com/flutter/flutter/issues/162662)).
- **Runner-level WKWebView swizzle** — tried and **reverted** (it did not stop
  the flicker). `MainFlutterWindow.swift` swizzled `hitTest` / `mouseMoved` /
  `mouseEntered` / `mouseExited` / `cursorUpdate` to no-ops for webviews whose
  `url.host` was `youtube-nocookie.com` (the embed's baseUrl; the Turnstile
  captcha webview uses `localhost` and must stay interactive). The full
  implementation is preserved at the bottom of this file (it was never
  committed). Its failure suggests the cursor set isn't reaching WKWebView
  through those NSResponder entry points on the WKWebView instance itself —
  candidates: WebKit setting the cursor from an internal/child object or via
  its own `NSTrackingArea` owner that isn't the `WKWebView`, or the Flutter
  engine's platform-view container views participating in tracking.

**Leads for a real fix:**

- Instrument first: swizzle/observe `NSCursor.set` globally in a debug build
  and log the call stack to find *who* re-asserts the arrow. Fix follows from
  the answer; everything above was aimed at an assumed source.
- Upstream: [flutter/flutter#164841](https://github.com/flutter/flutter/issues/164841)
  (webview keeps controlling mouse events on macOS) and
  [flutter/flutter#145892](https://github.com/flutter/flutter/issues/145892)
  (wrong cursor on macOS) are adjacent; check whether a newer Flutter /
  flutter_inappwebview release fixes platform-view cursor arbitration before
  writing native code again.
- Nuclear option: while in YouTube mode, force a single cursor for the whole
  window (e.g. default arrow everywhere over the video region) so there is
  nothing to fight about — degrades hover affordances but kills the flicker.

### Appendix: the reverted swizzle (for reference)

Lived in `macos/Runner/MainFlutterWindow.swift`; installed from
`awakeFromNib` via `WKWebView.ptInstallDisplayOnlyPatch()` after
`RegisterGeneratedPlugins`. Did NOT fix the flicker, but did compile and run;
a variant with different interception points could start from here.

```swift
import WebKit

private let youTubeEmbedHost = "youtube-nocookie.com"

extension WKWebView {
  fileprivate var ptIsDisplayOnly: Bool {
    guard let host = url?.host else { return false }
    return host == youTubeEmbedHost || host.hasSuffix("." + youTubeEmbedHost)
  }

  @objc fileprivate func pt_hitTest(_ point: NSPoint) -> NSView? {
    ptIsDisplayOnly ? nil : pt_hitTest(point)
  }

  @objc fileprivate func pt_mouseMoved(with event: NSEvent) {
    if !ptIsDisplayOnly { pt_mouseMoved(with: event) }
  }

  @objc fileprivate func pt_mouseEntered(with event: NSEvent) {
    if !ptIsDisplayOnly { pt_mouseEntered(with: event) }
  }

  @objc fileprivate func pt_mouseExited(with event: NSEvent) {
    if !ptIsDisplayOnly { pt_mouseExited(with: event) }
  }

  @objc fileprivate func pt_cursorUpdate(with event: NSEvent) {
    if !ptIsDisplayOnly { pt_cursorUpdate(with: event) }
  }

  static func ptInstallDisplayOnlyPatch() {
    let pairs: [(Selector, Selector)] = [
      (#selector(NSView.hitTest(_:)), #selector(pt_hitTest(_:))),
      (#selector(NSResponder.mouseMoved(with:)), #selector(pt_mouseMoved(with:))),
      (#selector(NSResponder.mouseEntered(with:)), #selector(pt_mouseEntered(with:))),
      (#selector(NSResponder.mouseExited(with:)), #selector(pt_mouseExited(with:))),
      (#selector(NSResponder.cursorUpdate(with:)), #selector(pt_cursorUpdate(with:))),
    ]
    for (original, replacement) in pairs {
      ptSwizzle(original, replacement)
    }
  }

  // class_addMethod first: if WKWebView only inherits the selector, a direct
  // exchange would patch NSView/NSResponder for the entire app.
  private static func ptSwizzle(_ original: Selector, _ replacement: Selector) {
    guard let replacementMethod = class_getInstanceMethod(self, replacement),
      let originalMethod = class_getInstanceMethod(self, original)
    else { return }
    if class_addMethod(
      self, original,
      method_getImplementation(replacementMethod),
      method_getTypeEncoding(replacementMethod))
    {
      class_replaceMethod(
        self, replacement,
        method_getImplementation(originalMethod),
        method_getTypeEncoding(originalMethod))
    } else {
      method_exchangeImplementations(originalMethod, replacementMethod)
    }
  }
}
```

