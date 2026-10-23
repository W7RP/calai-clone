# Getting builds onto the iPhone (Windows, no paid Apple account)

GitHub Actions builds an unsigned `.ipa` on a cloud Mac. AltStore signs it with a free Apple ID and installs it. A free-account signature lasts 7 days; AltStore renews it over Wi-Fi when AltServer is running on the PC.

Tool details change; if a step below doesn't match what you see, check https://faq.altstore.io first.

## One-time setup

### On the Windows PC
1. Install **iTunes** and **iCloud** from Apple's website (the direct downloads, not the Microsoft Store versions; AltServer needs the desktop ones).
2. Install **AltServer for Windows** from https://altstore.io and start it. It lives in the system tray.
3. Plug the iPhone in by USB. Open iTunes, select the phone, tick **"Sync with this iPhone over Wi-Fi"**, and click Apply. This is what lets refreshes happen without the cable later.

### On the iPhone
4. Unlock the phone and tap **Trust** when asked about the computer.
5. In the AltServer tray icon: **Install AltStore → (your iPhone)**. Sign in with your Apple ID. (Optional: use a separate Apple ID made just for this.)
6. On the phone: **Settings → General → VPN & Device Management**, tap your Apple ID, then **Trust**.
7. **Settings → Privacy & Security → Developer Mode → On**. The phone restarts; confirm when it asks.
8. Open AltStore once to check it launches.

## Installing a build
1. On GitHub, open the repo's **Actions** tab, pick the latest green **Build** run, and download the `CalorieTracker-N` artifact under *Artifacts*. GitHub wraps it in a `.zip`; extract it to get `CalorieTracker-N.ipa`.
2. Get the `.ipa` onto the phone. Easiest: save it to iCloud Drive on the PC, or AirDrop it from the Mac.
3. On the phone, open **AltStore → My Apps → +**, pick the `.ipa`. AltServer must be running on the PC and the phone on the same Wi-Fi.
4. Open the app. The build number and commit on screen should match the Actions run you downloaded.

Installing a newer build over an existing one keeps the app's data.

## Keeping it alive
- AltStore refreshes apps in the background when the phone and PC are on the same Wi-Fi and AltServer is running. Leave AltServer set to launch at Windows startup.
- **My Apps** shows days left. If one gets close to 0, tap **Refresh All** with the PC on.
- If it does expire, the app just won't open until refreshed. Data isn't lost.
- Free accounts allow 3 sideloaded apps at once, and AltStore itself counts as one.

## Troubleshooting
- *"Could not find AltServer"*: PC and phone on different networks, AltServer not running, or Windows Firewall blocking it. Plugging in by USB always works as a fallback.
- *"Maximum number of apps"*: remove another sideloaded app.
- App crashes straight away after install: tell Claude the build number and what you saw.
