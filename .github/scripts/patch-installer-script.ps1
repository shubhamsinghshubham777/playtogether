# Appends the three Windows-only pieces inno_bundle cannot express to the
# generated Inno Setup script, after `dart run inno_bundle --no-installer`.
#
# inno_bundle regenerates inno-script.iss from scratch on every build and its
# pubspec config covers only [Setup]/[Files]/[Icons]/[Run] essentials — there is
# no [Registry] option and no way to add a [Run] entry. So all of these have to
# be patched in here rather than configured alongside the rest in pubspec.yaml.
#
#   1. The synctogether:// protocol handler. Google OAuth redirects to
#      synctogether://auth-callback; with nothing registered, Windows drops the
#      callback and sign-in hangs on its spinner forever. macOS/iOS/Android
#      declare this in their Info.plist/manifest, but on Windows it is purely an
#      installer concern.
#
#   2. The Evergreen WebView2 runtime, which flutter_inappwebview needs for the
#      guest captcha dialog. It ships with Windows 11 and most Windows 10, but
#      is absent on LTSC/Server and de-bloated images — where the captcha would
#      silently fail to render and guest sign-in becomes impossible. A [Code]
#      check skips the bootstrapper when a runtime is already registered
#      (Windows 11's inbox one, a previous SyncTogether install, or a manual
#      install all count) — even in that case the bootstrapper costs seconds of
#      EdgeUpdate round-trips, which is pure waste on every upgrade. When it
#      does run, it detects concurrent installs itself, so racing EdgeUpdate is
#      still safe.
#
#   3. A second launch entry, for the self-update path only. WinSparkle installs
#      updates by running this installer with /SILENT, and inno_bundle's own
#      launch entry carries `skipifsilent` — so a silent install would leave the
#      app updated but never restarted. Rather than rewrite that entry (whether
#      a `postinstall` checkbox entry runs at all under /SILENT is not something
#      the Inno docs promise), this adds a `Check: WizardSilent` twin. Exactly
#      one of the pair ever fires, which is what the `skipifsilent` assertion
#      below keeps true. `runasoriginaluser` is the load-bearing flag on it:
#      Setup is elevated for the Program Files install, and an app relaunched
#      with that token would put WebView2's userDataFolder somewhere a normal
#      run cannot read.
#
# Inno Setup allows a section header to appear more than once and concatenates
# the entries, so appending whole sections here is equivalent to having them
# inline. Section order within the file does not matter.

$ErrorActionPreference = 'Stop'

$iss = './build/windows/x64/installer/Release/inno-script.iss'
if (-not (Test-Path $iss)) {
    throw "$iss not found — run 'dart run inno_bundle --no-app --release --no-installer' first."
}

# The exe name is the pubspec `name`, which is also windows/CMakeLists.txt's
# BINARY_NAME. Assert it landed in the script rather than hardcoding blind: a
# rename would otherwise register a protocol handler pointing at nothing.
$issContent = Get-Content $iss -Raw

$exe = 'synctogether.exe'
if ($issContent -notmatch [regex]::Escape('{app}\' + $exe)) {
    throw "$iss does not reference {app}\$exe — the executable may have been renamed."
}

if ($issContent -match '(?m)^\[Code\]') {
    throw "$iss already contains a [Code] section — merge the WebView2 check into it instead of appending a duplicate."
}

$launchEntry = [regex]::new(
    '(?m)^(Filename: "\{app\}\\' + [regex]::Escape($exe) + '";[^\r\n]*?Flags:)([^\r\n]*)'
)
$launchMatch = $launchEntry.Match($issContent)
if (-not $launchMatch.Success) {
    throw "$iss has no [Run] launch entry for {app}\$exe — inno_bundle changed its output, so the silent-install relaunch below can no longer be reasoned about."
}
if ($launchMatch.Groups[2].Value -notmatch 'skipifsilent') {
    throw "$iss's launch entry no longer carries skipifsilent — it would fire alongside the silent-install relaunch entry appended below and start the app twice."
}

# Permanent Microsoft fwlink for the Evergreen bootstrapper (~2 MB). It is
# redistributable and always fetches the current runtime at install time.
$bootstrapper = Join-Path $PWD 'MicrosoftEdgeWebview2Setup.exe'
Write-Host 'Downloading the WebView2 Evergreen bootstrapper'
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/p/?LinkId=2124703' -OutFile $bootstrapper

# HKA resolves to HKLM for the admin install inno_bundle configures by default,
# and to HKCU if the user downgrades it via PrivilegesRequiredOverridesAllowed.
# uninsdeletekey on the root entry removes the whole tree on uninstall, so a
# removed app never leaves a protocol pointing at a missing exe.
$lines = @(
    ''
    '[Registry]'
    'Root: HKA; Subkey: "Software\Classes\synctogether"; ValueType: string; ValueName: ""; ValueData: "URL:SyncTogether Protocol"; Flags: uninsdeletekey'
    'Root: HKA; Subkey: "Software\Classes\synctogether"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""'
    ('Root: HKA; Subkey: "Software\Classes\synctogether\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\' + $exe + ',0"')
    # The doubled quotes are Inno's escape for a literal quote: the command ends
    # up as `"C:\...\synctogether.exe" "%1"`. Quoting %1 is what keeps a URI
    # containing spaces from arriving split across argv — app_links only reads
    # the link when argc is exactly 2.
    ('Root: HKA; Subkey: "Software\Classes\synctogether\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\' + $exe + '"" ""%1"""')
    ''
    '[Files]'
    ('Source: "' + $bootstrapper + '"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: WebView2Needed')
    ''
    '[Run]'
    # No postinstall flag, so this runs during installation — before the finish
    # page where inno_bundle's own "launch the app" entry waits.
    'Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "Installing the WebView2 runtime..."; Flags: waituntilterminated; Check: WebView2Needed'
    ('Filename: "{app}\' + $exe + '"; Flags: nowait runasoriginaluser; Check: RelaunchAfterSilentInstall')
    ''
    '[Code]'
    'function RuntimeRegistered(const RootKey: Integer; const SubKey: String): Boolean;'
    'var'
    '  pv: String;'
    'begin'
    '  Result := RegQueryStringValue(RootKey, SubKey, ''pv'', pv)'
    '    and (pv <> '''') and (pv <> ''0.0.0.0'');'
    'end;'
    ''
    'function WebView2Needed(): Boolean;'
    'begin'
    '  Result := not ('
    '    RuntimeRegistered(HKLM32, ''SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'')'
    '    or RuntimeRegistered(HKCU, ''Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'')'
    '  );'
    '  if Result and IsWin64 then'
    '    Result := not RuntimeRegistered(HKLM64, ''SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'');'
    'end;'
    ''
    'function RelaunchAfterSilentInstall(): Boolean;'
    'begin'
    '  Result := WizardSilent();'
    'end;'
)

Add-Content -Path $iss -Value $lines
Write-Host "Patched $iss with the synctogether:// handler, the WebView2 runtime and the silent-install relaunch."
