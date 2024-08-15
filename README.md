# PlayTogether

## Get Started
This project uses [FVM](https://fvm.app/) to lock onto a specific Flutter version. Right now, it uses Flutter `3.22.3`, so please make sure to set up FVM on your system and run `pub use 3.22.3` before starting up the project.

## Generate MSIX (Windows)

All builds are supposed to be `debug` builds because the app does NOT run in `profile` or `release` mode due to the following issue:

`fatal error LNK1120: 7 unresolved externals`
**Ref**: https://github.com/flutter/flutter/issues/32746

Therefore, the only way to differentiate between builds is by its `flavor`, i.e. either `development` or `production`. And since there is not way to set `flavor` via the `msix:create` command, we are defaulting to `production` if no flavor values are passed, and to run the `development` flavor, you will have to pass `--dart-define FLAVOR=development` flag to your `flutter run` command (in VSCode, you can do it by passing "args": ["--dart-define", "FLAVOR=development"] inside your configurations).

1. Generate your own MSIX signing certificate using [MSIX Hero](https://www.microsoft.com/store/productId/9N3LL1W6QCNT?ocid=pdpshare) app on Microsoft Store. Open the app, tap on  `Tools`, and under `CERTIFICATES AND SIGNING` category, select `Create self-signed certificate`. Enter your details and it should generate a `.cer` and a `.pfx` files in your user's `Documents\Certificates` folder.

2. Once the certificate is generated, set up the [MSIX](https://pub.dev/packages/msix) pub package and after setting it up, execute the following commands in PowerShell:
```sh
fvm dart run msix:create --debug --certificate-path {YOUR_FILE_PATH} --certificate-password {YOUR_PASSWORD}
```
Here, `{YOUR_FILE_PATH}` refers to the complete path of your `.pfx` certificate file. For example: `C:\Users\shubh\Documents\Certificates\PlayTogether.pfx` and `{YOUR_PASSWORD}` refers to the password you used with `MSIX Hero` to generate this certificate file.

## Quick Commands

1. fvm dart run build_runner watch --delete-conflicting-outputs
2. firebase emulators:start
3. fvm flutter pub upgrade --major-versions; fvm flutter pub upgrade --tighten
