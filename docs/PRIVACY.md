# Hushclip Privacy Policy

_Last updated: November 6, 2026_

Hushclip is a clipboard history app for macOS. This policy covers both the Mac App Store version and the builds published on GitHub.

## The short version

Hushclip does not collect, transmit or share any data. Everything it records stays on your Mac, encrypted.

## What Hushclip stores

To show your clipboard history, Hushclip saves the text, images and file references you copy, together with the time each item was copied and the name of the app it came from. This history is stored only on your Mac:

- It is encrypted with AES-256-GCM before it is written to disk.
- The encryption key is generated on your Mac and kept in your login Keychain. It is marked this-device-only and is never synced to iCloud.
- Items that look like passwords, API keys or card numbers are masked on screen and deleted automatically after a time you choose (one hour by default).
- Items that password managers mark as concealed are labelled as passwords, or skipped entirely if you turn that off in Settings. Items marked as transient are never recorded.

You can delete individual items at any time, or all of them with **Clear History…** in the menu bar.

## What Hushclip does not do

- It makes no network connections.
- It contains no analytics, crash reporting, advertising or tracking code.
- It has no accounts.
- It does not share data with Apple, the developer or any third party.

## Permissions

- **Accessibility** (optional): lets Hushclip press ⌘V for you when you choose an item, so it is pasted into the app you were using. Hushclip uses it only to send that one keystroke. Without it, Hushclip copies the item and you paste it yourself.
- **Launch at login** (optional, off by default): starts Hushclip when you log in.

## Children

Hushclip does not knowingly collect information from anyone, including children.

## Changes

If this policy changes, the new version will be published at this address with a new date above.

## Contact

Questions? Open an issue at <https://github.com/arlintdev/hushclip/issues>.
