# PlayTogether

## Get Started
This project uses [FVM](https://fvm.app/) to lock onto a specific Flutter version. Right now, it uses Flutter `3.22.3`, so please make sure to set up FVM on your system and run `pub use 3.22.3` before starting up the project.

## Generate MSIX (Windows)

1. Generate your own MSIX signing certificate using [MSIX Hero](https://www.microsoft.com/store/productId/9N3LL1W6QCNT?ocid=pdpshare) app on Microsoft Store. Open the app, tap on  `Tools`, and under `CERTIFICATES AND SIGNING` category, select `Create self-signed certificate`. Enter your details and it should generate a `.cer` and a `.pfx` files in your user's `Documents\Certificates` folder.

2. Once the certificate is generated, set up the [MSIX](https://pub.dev/packages/msix) pub package and after setting it up, execute the following commands in PowerShell:
```sh
fvm dart run msix:create --certificate-path {YOUR_FILE_PATH} --certificate-password {YOUR_PASSWORD}
```
Here, {YOUR_FILE_PATH} refers to the complete path of your `.pfx` certificate file. For example: `C:\Users\shubh\Documents\Certificates\PlayTogether.pfx` and {YOUR_PASSWORD} refers to the password you used with MSIX Hero to generate this certificate file.

## Quick Commands

1. fvm dart run build_runner watch --delete-conflicting-outputs
2. firebase emulators:start
3. fvm flutter pub upgrade --major-versions
4. fvm flutter pub upgrade --tighten
