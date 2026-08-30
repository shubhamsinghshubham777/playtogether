---
description: Google OAuth PKCE deep linking, Cloudflare Turnstile loopback bridge, Windows WebView2 runtime, TLS root cert overrides, and Sparkle/WinSparkle self-updates.
trigger: model_decision
---


# Authentication, Security & Platform Specifics

Guidance for authentication (`lib/auth/`), TLS overrides, platform runtimes, and desktop self-updates (`lib/updates/`).

## 1. Authentication & Deep Linking

`AuthService` supports Google OAuth (`signInWithOAuth`), anonymous guest logins (`signInAnonymously`), and guest-to-Google upgrades (`linkIdentity`).

### Google OAuth Flow
- Browser opens OAuth -> redirects to web bridge (`synctogether.app/auth/desktop-callback` or `localhost:3000`) -> web bridge relays PKCE params to `synctogether://auth-callback`.
- **Windows Single-Instance**: `windows/runner/main.cpp` calls `app_links`' `SendAppLinkToInstance()` first in `wWinMain` to forward deep link parameters via `WM_COPYDATA` rather than spawning orphaned processes.
- **Config & Manual Linking**: `enable_manual_linking = true` must be enabled in `config.toml` for `linkIdentity` to work (ships via `supabase config push`).
- **Deep Link Stream**: `AuthService.start()` must remain subscribed; its `onError` handler catches unhandled deep-link authentication exceptions.

### Cloudflare Turnstile Captcha (`lib/auth/turnstile_dialog.dart`)
- Anonymous logins require a Turnstile captcha token.
- **Loopback Origin**: Served from a throwaway `HttpServer` on the loopback (`127.0.0.1`), because Windows WebView2 drops `InAppWebViewInitialData.baseUrl` and yields an opaque origin. Keep `localhost` in the Turnstile hostname allow-list.

---

## 2. Platform Runtimes & TLS Overrides

### Windows WebView2 Runtime (`lib/auth/webview_runtime.dart`)
- **Explicit `userDataFolder`**: Initialized under `LOCALAPPDATA`. (If null, WebView2 attempts to write to Program Files, failing with unhandled platform exceptions).
- `PTWebView.init()` probes `WebViewEnvironment.getAvailableVersion()` and configures `--autoplay-policy=no-user-gesture-required`.

### TLS Overrides (`lib/tls.dart`)
- Windows Dart snapshots the Windows ROOT store and fails to build dynamic CryptoAPI chains on demand.
- `installTlsOverrides()` injects Mozilla's root CA bundle (`assets/ca/cacert.pem`) **additively** (`withTrustedRoots: true`).
- `badCertificateCallback` logs diagnostics and returns `false` (never blindly trusts bad certs).

---

## 3. Desktop Self-Updates (`lib/updates/`)

Self-update uses Sparkle (macOS) and WinSparkle (Windows), driven by `releases/latest/download/appcast.xml`.

- **Platform Scope**: `supportsSelfUpdate` (`lib/platform.dart`) gates update logic (desktop only, excluding Linux).
- **Dual-Key Signing**:
  - macOS: Sparkle Ed25519 (`SUPublicEDKey` in Info.plist).
  - Windows: WinSparkle DSA-SHA1 (`dsa_pub.pem` in `Runner.rc`).
  - **Public keys are committed; private keys exist ONLY in GitHub secrets (`SPARKLE_ED_PRIVATE_KEY`, `WINSPARKLE_DSA_PRIVATE_KEY`). Losing private keys strands all installed clients.**
- **Verification**: `.github/scripts/generate-appcast.sh` validates signatures against committed public keys before publishing releases.
- **Startup Check**: Pure Dart HTTP request (`UpdateService.checkForUpdate`), unawaited in `_bootstrap`. Does not touch native updater until the user clicks the banner.
- **WinSparkle First-Launch Silence**: `_silenceWinSparkleOwnChecks` writes `CheckForUpdates=0` to the registry to suppress native prompts.
- **Windows Self-Quit**: `onUpdaterBeforeQuitForUpdate` calls `exit(0)` to prevent the installer from colliding with a live executable.
