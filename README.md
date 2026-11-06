<p align="center">
  <img src="docs/icon.png" width="128" alt="Clipster icon">
</p>

<h1 align="center">Clipster</h1>

<p align="center">
  <b>An encrypted clipboard history for macOS.</b><br>
  Press <kbd>⌘</kbd><kbd>⇧</kbd><kbd>V</kbd> anywhere to search, preview and paste everything you've copied,
  sorted into categories automatically.
</p>

<p align="center">
  <a href="https://github.com/arlintdev/clipster/releases/latest"><img src="https://img.shields.io/github/v/release/arlintdev/clipster?label=download" alt="Latest release"></a>
  <a href="https://github.com/arlintdev/clipster/actions/workflows/ci.yml"><img src="https://github.com/arlintdev/clipster/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
</p>

<p align="center">
  <img src="docs/screenshot.png" alt="Clipster overlay in dark mode">
</p>

## Features

- **Global overlay on ⌘⇧V.** A floating panel opens over whatever you're doing. Type to search, use arrow keys to pick, press Return to paste straight into the app you were in.
- **Automatic categories.** Every clip is labelled by local regex and heuristic rules. There's no network access and no AI.
- **Encrypted at rest.** History and images are sealed with **AES-256-GCM** (CryptoKit). The 256-bit key is generated on your Mac and kept in your login Keychain as this-device-only. Nothing is ever written to disk in plaintext.
- **Careful with secrets.** Passwords, API keys and card numbers are masked in the UI (hold <kbd>⌥</kbd> to reveal) and auto-deleted after an hour by default. Clipster follows the [nspasteboard.org](http://nspasteboard.org) conventions: it skips *transient* items and labels *concealed* items from password managers as passwords (or skips them entirely, if you choose).
- **Native and light.** Swift + AppKit + SwiftUI, one universal binary, runs only in the menu bar, no dependencies.

### Categories

| Category | How it's detected |
|---|---|
| 📸 **Screenshot** | A bare image with no other pasteboard data (what the system screenshot tool produces), an image from a screenshot app, or a copied `Screenshot …png` file |
| 🖼 **Image** / 📄 **File** | Images copied from apps or the web; files copied in Finder |
| 🔑 **Password** | Marked concealed by a password manager, or a single token mixing letters, digits and symbols (or 14+ high-entropy characters) |
| 🛡 **Secret** | AWS / GitHub / GitLab / Slack / Stripe / Google / OpenAI / Anthropic / npm / SendGrid keys, JWTs, `-----BEGIN … PRIVATE KEY-----`, `API_KEY=…` lines, long high-entropy tokens |
| 💳 **Card** | 13–19 digits that pass the Luhn check |
| 🔗 **Link** · ✉️ **Email** · 📞 **Phone** · 🌐 **IP Address** | URLs, email addresses, phone numbers (not dates), IPv4/IPv6 with optional CIDR or port |
| 🎨 **Color** | `#hex`, `rgb()`, `hsl()`, `oklch()` and similar, shown with a live swatch |
| 🔢 **UUID** · **Hash** · **Number** · **JSON** | Exact formats; JSON must actually parse |
| ⌨️ **Command** | Shell commands (`git`, `kubectl`, `brew`, `$ …`, …) |
| 🧩 **Code** | Scored on signals like declarations, braces, semicolons, imports, SQL, HTML and indentation |
| 📁 **Path** | `/…`, `~/…`, `./…`, `C:\…` |
| 📝 **Text** | Everything else |

The rules live in [`Sources/ClipsterCore/Categorizer.swift`](Sources/ClipsterCore/Categorizer.swift) and are unit-tested in [`Tests/ClipsterCoreTests`](Tests/ClipsterCoreTests). PRs for new formats are welcome.

### Keyboard

| Key | Action |
|---|---|
| <kbd>⌘</kbd><kbd>⇧</kbd><kbd>V</kbd> | Open or close Clipster |
| <kbd>↑</kbd> <kbd>↓</kbd> | Move the selection |
| <kbd>↩</kbd> | Paste into the active app |
| <kbd>⌘</kbd><kbd>↩</kbd> | Copy to the clipboard without pasting |
| <kbd>⌘</kbd><kbd>1</kbd>…<kbd>9</kbd> | Paste the Nth item |
| <kbd>⇥</kbd> / <kbd>⇧</kbd><kbd>⇥</kbd> | Next / previous category filter |
| <kbd>⌘</kbd><kbd>P</kbd> | Pin or unpin (pinned items never expire) |
| <kbd>⌘</kbd><kbd>⌫</kbd> | Delete the item |
| hold <kbd>⌥</kbd> | Reveal masked passwords and secrets |
| <kbd>Esc</kbd> | Clear the search, then the filter, then close |
| <kbd>⌘</kbd><kbd>,</kbd> | Settings |

<p align="center">
  <img src="docs/screenshot-light.png" alt="Clipster overlay in light mode with a masked password">
</p>

## Install

1. Download **`Clipster-x.y.z.dmg`** from the [latest release](https://github.com/arlintdev/clipster/releases/latest).
2. Drag **Clipster** into **Applications** and open it. A clipboard icon appears in the menu bar.
3. Press <kbd>⌘</kbd><kbd>⇧</kbd><kbd>V</kbd>.

**"Clipster can't be verified"?** Release builds are ad-hoc signed unless the repository has Developer ID secrets set up (see [Releasing](#releasing)). To allow it, open **System Settings → Privacy & Security** and click **Open Anyway**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Clipster.app
```

**Auto-paste** needs Accessibility permission so Clipster can press <kbd>⌘</kbd><kbd>V</kbd> for you. Clipster asks the first time you paste. Until you grant it, choosing an item copies it and you paste yourself. You can grant it under **System Settings → Privacy & Security → Accessibility**.

> Note: ⌘⇧V is a global shortcut, so it replaces "Paste and Match Style" in apps that use it. Clipster always pastes plain text for text items, so you get the same result.

## Security model

| | |
|---|---|
| **At rest** | `~/Library/Application Support/Clipster/history.vault` (index and text) plus `blobs/*.vault` (images). Each file is `CLIPSTR1` ‖ AES-256-GCM nonce ‖ ciphertext ‖ tag, with the header bound as associated data. The folder is `0700` and the files are `0600`. |
| **Key** | 256 random bits, stored in the login Keychain as a generic password (`dev.arlint.clipster` / `vault-key`), `WhenUnlockedThisDeviceOnly`, never synced. |
| **In memory** | History is decrypted into memory while Clipster runs. |
| **Sensitive items** | Masked in the UI, excluded from content search when concealed, and deleted after 5 min to 1 week (default 1 hour). When Clipster pastes them back, it marks them `ConcealedType` so other clipboard tools don't record them. |
| **Network** | None. Clipster makes no network requests. |
| **Unreadable vault** | If the vault can't be decrypted (for example, the Keychain item was deleted), Clipster moves it aside instead of overwriting it. |

To wipe everything, use **Clear History…** in the menu, or quit Clipster and delete the data folder and the Keychain item:

```bash
rm -rf ~/Library/Application\ Support/Clipster
```

```bash
security delete-generic-password -s dev.arlint.clipster -a vault-key
```

## Build from source

Requires Xcode 16+ (Swift 5.9+) on macOS 14+.

```bash
git clone https://github.com/arlintdev/clipster && cd clipster
```

```bash
swift test
```

```bash
./Scripts/build-app.sh && open build/Clipster.app
```

`build-app.sh` makes a universal, ad-hoc-signed `build/Clipster.app`. Set `SIGN_ID="Developer ID Application: …"` to sign with your own identity, or `ARCHS=arm64` for a faster single-arch build. `Scripts/package.sh <version>` produces the `.dmg`, `.zip` and `SHA256SUMS.txt` in `dist/`.

To preview the UI without installing anything, `Clipster --snapshot out.png [--light] [--select N] [--reveal]` renders the overlay with sample data to a PNG. It runs in memory only and never touches your vault.

### Project layout

```
Sources/ClipsterCore/   categorizer, model, AES-GCM vault, Keychain key: pure and unit-tested
Sources/Clipster/       menu bar app: pasteboard monitor, Carbon hotkey, overlay panel, SwiftUI views
Scripts/                build-app.sh, package.sh, make-icon.swift
.github/workflows/      ci.yml (test + build on every push/PR), release.yml (tag → GitHub Release)
```

## Releasing

Push a version tag:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

[`release.yml`](.github/workflows/release.yml) runs the tests, builds a universal app, packages the `.dmg` and `.zip`, and publishes a GitHub Release. Release notes come from `docs/releases/<tag>.md` if that file exists; otherwise they're generated.

For a **signed and notarized** build, add these repository secrets: `MACOS_CERT_P12` (base64 Developer ID Application .p12), `MACOS_CERT_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD`. Without them the workflow falls back to ad-hoc signing.

## License

[MIT](LICENSE) © 2026 Austin Arlint
