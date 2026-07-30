# Appends the two Windows-only pieces inno_bundle cannot express to the
# generated Inno Setup script, after `dart run inno_bundle --no-installer`.
#
# inno_bundle regenerates inno-script.iss from scratch on every build and its
# pubspec config covers only [Setup]/[Files]/[Icons]/[Run] essentials — there is
# no [Registry] option and no way to add a [Run] entry. So both of these have to
# be patched in here rather than configured alongside the rest in pubspec.yaml.
#
#   1. The playtogether:// protocol handler. Google OAuth redirects to
#      playtogether://auth-callback; with nothing registered, Windows drops the
#      callback and sign-in hangs on its spinner forever. macOS/iOS/Android
#      declare this in their Info.plist/manifest, but on Windows it is purely an
#      installer concern.
#
#   2. The Evergreen WebView2 runtime, which flutter_inappwebview needs for the
#      guest captcha dialog. It ships with Windows 11 and most Windows 10, but
#      is absent on LTSC/Server and de-bloated images — where the captcha would
#      silently fail to render and guest sign-in becomes impossible. A [Code]
#      check skips the bootstrapper when a runtime is already registered
#      (Windows 11's inbox one, a previous PlayTogether install, or a manual
#      install all count) — even in that case the bootstrapper costs seconds of
#      EdgeUpdate round-trips, which is pure waste on every upgrade. When it
#      does run, it detects concurrent installs itself, so racing EdgeUpdate is
#      still safe.
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

$exe = 'playtogether.exe'
if ($issContent -notmatch [regex]::Escape('{app}\' + $exe)) {
    throw "$iss does not reference {app}\$exe — the executable may have been renamed."
}

if ($issContent -match '(?m)^\[Code\]') {
    throw "$iss already contains a [Code] section — merge the WebView2 check into it instead of appending a duplicate."
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
    'Root: HKA; Subkey: "Software\Classes\playtogether"; ValueType: string; ValueName: ""; ValueData: "URL:PlayTogether Protocol"; Flags: uninsdeletekey'
    'Root: HKA; Subkey: "Software\Classes\playtogether"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""'
    ('Root: HKA; Subkey: "Software\Classes\playtogether\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\' + $exe + ',0"')
    # The doubled quotes are Inno's escape for a literal quote: the command ends
    # up as `"C:\...\playtogether.exe" "%1"`. Quoting %1 is what keeps a URI
    # containing spaces from arriving split across argv — app_links only reads
    # the link when argc is exactly 2.
    ('Root: HKA; Subkey: "Software\Classes\playtogether\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\' + $exe + '"" ""%1"""')
    ''
    '[Files]'
    ('Source: "' + $bootstrapper + '"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: WebView2Needed')
    ''
    '[Run]'
    # No postinstall flag, so this runs during installation — before the finish
    # page where inno_bundle's own "launch the app" entry waits.
    'Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "Installing the WebView2 runtime..."; Flags: waituntilterminated; Check: WebView2Needed'
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
)

Add-Content -Path $iss -Value $lines
Write-Host "Patched $iss with the playtogether:// handler and the WebView2 runtime."
