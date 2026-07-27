# Pre-extracts flutter_webrtc's libwebrtc.zip into the package's real pub-cache
# directory, before `flutter build windows` runs CMake.
#
# flutter_webrtc/third_party/CMakeLists.txt does:
#   file(ARCHIVE_EXTRACT INPUT .../downloads/libwebrtc.zip DESTINATION <third_party>)
# and the Windows build reaches <third_party> through the Flutter plugin symlink
# windows/flutter/ephemeral/.plugin_symlinks/flutter_webrtc. Recent CMake refuses
# to extract when any path component is a symlink ("Cannot extract through
# symlink"), which fails the build. That CMake ships with Visual Studio and is
# the one Flutter picks (visualStudio.cmakePath), so it cannot be pinned in CI.
#
# The plugin only downloads+extracts when third_party/libwebrtc is missing, so
# doing the extraction here — against the real path, no symlink involved — makes
# CMake skip it entirely.

$ErrorActionPreference = 'Stop'

$configPath = '.dart_tool/package_config.json'
if (-not (Test-Path $configPath)) {
    throw "$configPath not found — run 'flutter pub get' before this script."
}

$pkg = (Get-Content $configPath -Raw | ConvertFrom-Json).packages |
    Where-Object { $_.name -eq 'flutter_webrtc' }
if (-not $pkg) {
    Write-Host 'flutter_webrtc is not a dependency; nothing to do.'
    exit 0
}

# rootUri is normally absolute for hosted packages, but resolve it against
# .dart_tool/ anyway so a path dependency would also work.
$base = [uri]((Resolve-Path '.dart_tool').Path.TrimEnd('\') + '\')
$root = [uri]::new($base, $pkg.rootUri).LocalPath
$thirdParty = Join-Path $root 'third_party'
$dest = Join-Path $thirdParty 'libwebrtc'
$zip = Join-Path $thirdParty 'downloads\libwebrtc.zip'

# Mirror the plugin's own guard exactly: it downloads when the zip is missing
# (and then extracts unconditionally), and extracts when libwebrtc/ is missing.
# Leaving either one absent would hand the extraction back to CMake.
$needZip = -not (Test-Path $zip)
$needExtract = -not (Test-Path $dest)
if (-not $needZip -and -not $needExtract) {
    Write-Host "libwebrtc already present at $dest — nothing to do."
    exit 0
}

if ($needZip) {
    $cmakeLists = Join-Path $thirdParty 'CMakeLists.txt'
    $url = [regex]::Match((Get-Content $cmakeLists -Raw), 'set\(DOWNLOAD_URL\s+"([^"]+)"').Groups[1].Value
    if (-not $url) {
        throw "Could not parse DOWNLOAD_URL from $cmakeLists — flutter_webrtc may have changed its download logic."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $zip) | Out-Null
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $zip
}

if (-not $needExtract) {
    Write-Host "libwebrtc already extracted at $dest — zip restored, skipping extraction."
    exit 0
}

Write-Host "Extracting to $thirdParty"
Add-Type -AssemblyName System.IO.Compression.FileSystem
# Extract entry by entry rather than via ExtractToDirectory: the archive holds a
# couple of Linux-only symlink entries (lib/elinux-*/libwebrtc.so), and .NET 7+
# tries to materialise those as real symlinks. ExtractToFile just writes bytes,
# which is all the Windows build needs — it only reads include/ and lib/win64/.
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    foreach ($entry in $archive.Entries) {
        $target = Join-Path $thirdParty $entry.FullName
        if ($entry.FullName.EndsWith('/')) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            continue
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
    }
} finally {
    $archive.Dispose()
}

if (-not (Test-Path $dest)) {
    throw "Extraction finished but $dest is missing — the archive layout may have changed."
}
Write-Host "libwebrtc ready at $dest"
