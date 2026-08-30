---
description: Violet glass design system tokens, PTLoader, LiveKit AV rails, diagnostics vs. analytics doctrines, and generated asset tools.
trigger: model_decision
---


# UI Design System, AV & Telemetry

Guidance for UI components (`lib/ui/`), audio/video facecams (`lib/av/`), diagnostics (`lib/diagnostics.dart`), analytics (`lib/analytics.dart`), and generated assets.

## 1. Design System & UI Components (`lib/ui/`)

- **Dark Mode Only**: Aesthetic is violet glass. All colors and typography must use tokens from `lib/ui/pt_theme.dart` (`PTColors`, `PTText`). **Never hardcode hex color values.**
- **Bundled Fonts**: Space Grotesk, Outfit, and JetBrains Mono (in `assets/fonts/`). Icons from `material_symbols_icons`.
- **Loading Indicators**: Always use **`PTLoader`** (`lib/ui/loader.dart`), which is a tinted `CupertinoActivityIndicator`. Never use `CircularProgressIndicator` (except the determinate countdown ring in `PTBanner`).
- **Glass Rendering Rules**:
  - **Never wrap `GlassPanel` in `Opacity`**: `Opacity` causes `BackdropFilter` to blur an empty intermediate layer. Animate glass surfaces using slide or clip transitions (`Align(heightFactor:)`, slide transforms).
  - **Collapsed Overlays**: In a `Positioned`, zero-height/collapsed states still receive touch events. Always wrap inactive or collapsed overlays in `IgnorePointer`.
- **Keyboard Navigation & Focus**:
  - Shortcuts are ignored while `EditableText` has focus.
  - Esc hierarchy is strictly ordered: Text field unfocus -> Reaction strip close -> Chat panel close -> Fullscreen exit.

---

## 2. Audio / Video Facecams (`lib/av/`)

- **LiveKit Service**: Managed per room via `LiveKitService`.
- **Token Minting**: Fetches credentials from `supabase/functions/livekit-token`.
- **Availability**: Gated strictly on `LiveKitService.isAvailableFor(room.avLevel)` (`none`, `voice`, `video`).
- **Video Publishing Cap**: Video publishes capped at 360p / 24fps to conserve room bandwidth for media playback.

---

## 3. Diagnostics vs. Analytics Doctrines

### Diagnostics (`lib/diagnostics.dart`) — *"Why did this break?"*
- **`reportNonFatal(error, stackTrace)`**: Routes to Sentry for unhandled or unexpected failure branches.
- **`trace(msg, category:, data:)`**: Records breadcrumbs on key state transitions (`sync`, `gate`, `media`, `room`, `av`, `auth`, `turnstile`, `youtube`, `tls`, `webview`).
- **Do NOT log per-frame or per-heartbeat ticks**: Avoid logging on the 10 s position heartbeat, presence updates, or scrub preview dragging to prevent evicting useful breadcrumbs.
- **Privacy**: Never log chat messages or full local file paths.

### Analytics (`lib/analytics.dart`) — *"Is anyone doing this?"*
- **Strictly User-Initiated**: Fire analytics events **only when a human explicitly triggered the action**. Never track inside remote action callbacks, gate pauses, drift corrections, or reconnect handlers.
- **Implementation**: Custom lightweight `dart:io` HTTP client to PostHog Cloud (no third-party Flutter plugin dependencies).
- **Privacy Boundaries**: Never track media file names, file paths, chat text, or YouTube video IDs.
- **Opt-Out**: User consent (`AnalyticsConsent`) is checked before initialization.

---

## 4. Generated Assets & Build Scripts (`tool/`)

The following files are generated build outputs. **Never edit them manually**:

| Asset | Generated Output | Generator Command |
| :--- | :--- | :--- |
| **Splash Sound** | `assets/sfx/splash.wav` | `python3 tool/generate_splash_sound.py` |
| **Reaction Emoji** | `assets/emoji/*.json` | `python3 tool/fetch_reaction_emoji.py` |
| **CA Root Bundle** | `assets/ca/cacert.pem` | `python3 tool/update_ca_bundle.py` |
| **App Icons** | `assets/icon/`, `windows/.../app_icon.ico` | `python3 tool/generate_app_icon.py && fvm dart run flutter_launcher_icons` |
