<p align="center">
  <img width="150" src="assets/image/app_logo.png">
</p>

<h1 align="center">PlayTogether</h1>

<p align="center">
  <img src="https://img.shields.io/github/v/release/shubhamsinghshubham777/playtogether?style=for-the-badge&label=Latest%20Version&labelColor=blue&color=blue&link=https%3A%2F%2Fgithub.com%2Fshubhamsinghshubham777%2Fplaytogether%2Freleases" />
  <img src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Windows%2011-%230079d5.svg?style=for-the-badge&logo=Windows%2011&logoColor=white" />
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" />
</p>

PlayTogether is a WebRTC-based shared media player. Written in Flutter, it allows you to enjoy your local media with your friends in real-time while having a video call with them 📹📷

## Screenshots

|   **Feature**  	| **Screenshot** 	|
|:--------------:	|:--------------:	|
| Authentication 	| ![1](https://github.com/user-attachments/assets/48b0296f-4fba-4cdf-82ab-b099a109afc6)	|
|    Dashboard   	| ![2](https://github.com/user-attachments/assets/c8b67bd2-c74f-43b4-ab39-1e503fb8870d)	|
|     Profile    	| ![3](https://github.com/user-attachments/assets/1d321f34-e65b-4e0f-9307-629b2589e39b)	|
|  Incoming Call 	| ![4](https://github.com/user-attachments/assets/4cbfc57d-4ae8-442e-979c-27f4c048705a)	|
|   Video Call   	| ![5](https://github.com/user-attachments/assets/a9d4923e-189f-40a2-a18b-6fa2bf94f5e0)	|

## Get Started
This project uses [FVM](https://fvm.app/) to lock onto a specific Flutter version. Right now, it uses Flutter `3.22.3`, so please make sure to set up FVM on your system and run `pub use 3.22.3` before starting up the project.

This app uses Firebase, make sure to use [flutterfire](https://firebase.google.com/docs/flutter/setup) to set up your own Firebase project with this app.

This project also uses the following environment variables using [envied](https://pub.dev/packages/envied):
1. `GOOGLE_CLIENT_ID` - You can find this in your Google Cloud Platform console (from the `APIs & Services` > `Credentials` tab)
2. `GOOGLE_CLIENT_SECRET` - You can find this in your Google Cloud Platform console (from the `APIs & Services` > `Credentials` tab)

Therefore please make sure to manually create an `.env` file in the root of the project that has the following content (replace values with your own):
```env
GOOGLE_CLIENT_ID=90xxxx298xxx-xxxxxgv1a9bxxxxxxtb4fthxxxxxxlg6.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=GOCSPX-xxxxxx99KnByxxxxxxxSuLhvpxxx
```

## Generate MSIX (Windows)

### For Viewers / Users

If you are a viewer/user and want to install the provided MSIX file (in [releases](https://github.com/shubhamsinghshubham777/playtogether/releases)) on your Windows system, please follow this guide to install the certificate to be able to do so:

1. Select `Properties` from the right-click menu of the MSIX package.
2. Go to the `Digital Signature` tab.
3. From the `Signature List` choose the certificate.
4. Click on `Details`.
5. Click on `View Certificate`.
6. Click `Install Certificate`.
7. Choose Local Machine from Store Location.
8. Allow the app to install certificates.
9. Choose Place all certificates in the following store.
10. Click Browse and select `Trusted People`.
11. Click `OK` and Click `Next` then Click `Finish`
12. Then you should see a popup window with the message `Import was successful`

### For Developers

All builds are supposed to be `debug` builds because the app does NOT run in `profile` or `release` mode due to the following issue (possibly because of the `media_kit` library):

`fatal error LNK1120: 7 unresolved externals`
**Ref**: https://github.com/flutter/flutter/issues/32746

Therefore, the only way to differentiate between builds is by its `flavor`, i.e. either `development` or `production`. And since there is not way to set `flavor` via the `msix:create` command, we are defaulting to `production` if no flavor values are passed, and to run the `development` flavor, you will have to pass `--dart-define FLAVOR=development` flag to your `flutter run` command (in VSCode, you can do it by writing "args": ["--dart-define", "FLAVOR=development"] inside your configuration(s)).

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
