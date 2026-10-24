# Installing on an iPhone (Mac + free Apple ID)

Xcode signs and installs the app with a free Apple ID ("Personal Team"). No paid developer account is needed. A free-account build stops opening after 7 days; re-run it from Xcode to renew it. Your data is kept.

Free sideloading tools (AltStore, SideStore, Sideloadly) have failed to sign in to Apple since about 2026-10-21, so this guide uses Xcode only.

Tested 2026-10-24 with Xcode 27.1 and an iPhone on iOS 26.

## One-time setup

### Mac
1. Install **Xcode** from the App Store (macOS 15.6 or newer). Open it once and install the **iOS** platform when asked.
2. Install Homebrew from https://brew.sh, and run the "Next steps" commands it prints.
3. Install the tools and sign in to GitHub (the repo is private):
   ```
   brew install gh xcodegen
   gh auth login
   ```
   Choose GitHub.com, HTTPS, yes to authenticating Git, and log in with a web browser.
4. Get the code and generate the project:
   ```
   cd ~
   gh repo clone W7RP/calai-clone
   cd calai-clone
   xcodegen generate
   open CalorieTracker.xcodeproj
   ```

### Signing
5. **Xcode → Settings → Accounts → + → Apple Account**, and sign in with your Apple ID.
6. Select the **CalorieTracker** project in the sidebar, then the **CalorieTracker** target, then **Signing & Capabilities**. Tick **Automatically manage signing** and set **Team** to your Personal Team.
   Until the phone is connected you'll see "your team has no devices" and "no profiles found". That's expected.

### iPhone
7. Plug the phone in, unlock it, and tap **Trust**. Pick the phone in Xcode's device menu at the top of the window. The first time, Xcode prepares the device, which takes a few minutes.
8. **Settings → Privacy & Security → Developer Mode → On**, then restart and confirm. The option appears once Xcode has seen the phone.
9. Back in **Signing & Capabilities**, the errors clear. Click **Try Again** if they don't.

## Running a build
1. With the phone plugged in and unlocked, press **Cmd+R**.
2. If macOS asks for your login password for `codesign`, enter it and choose **Always Allow**.
3. First install only: if the launch is blocked as an untrusted developer, go to **Settings → General → VPN & Device Management** on the phone, tap your Apple ID, then **Trust**. Press Cmd+R again.

## Updating
```
cd ~/calai-clone
git pull
```
Then press Cmd+R. Run `xcodegen generate` only when files were added or removed. It rewrites the project, so set the Team again afterwards (step 6).

## Troubleshooting
- *Bundle identifier not available*: change `com.w7rp.calorietracker` in Signing & Capabilities to something unique, such as `com.<yourname>.easycal`.
- *App won't open after a week*: the free signature expired. Plug in and press Cmd+R.
- Free accounts allow 3 sideloaded apps per device and 10 app IDs per week.
