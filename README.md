<p align="center">
  <img src="Resources/AppIcon-1024.png" alt="ClaudeStats icon" width="180" />
</p>

# ClaudeStats

A native macOS menu bar app that shows your Claude Code usage at a glance — with a **pace-aware** indicator that tells you whether you're burning through your 5-hour and weekly limits faster or slower than a steady budget.

Built in pure SwiftUI. No Dock icon, no telemetry, no background services.

---

## What you see

**Menu bar item**
- A tortoise / balance / hare glyph indicating whether you're under, on, or over pace
- The percentage of your 5-hour window used

**Popover** (click the menu bar item)
- **5-hour window** section with a pace bar: a colored fill shows how much of your window budget you've consumed, and a vertical marker shows where you should be based on elapsed time. If the fill is left of the marker you're ahead of budget; right of it, you're burning fast.
- **Weekly** section with the same pace visualization for your 7-day cap
- Per-model breakdown (opus / sonnet / haiku) as share of the window's total
- Projected end-of-window utilization
- Countdown to next reset

**Settings** (Settings button in the popover)
- Sign in to Claude.ai (WKWebView-based) or paste your `sessionKey` manually
- Toggle Launch at Login

---

## How it works

When you sign in to Claude.ai through the app, it calls Anthropic's own undocumented but browser-accessible endpoint:

```
GET https://claude.ai/api/organizations/{orgId}/usage
```

This is the exact endpoint used by Claude's in-page `/usage` view. It returns your real 5-hour and 7-day utilization percentages plus actual reset timestamps, straight from Anthropic. No guessing, no local approximation.

Your `sessionKey` cookie is stored in your app preferences plist. Cleared when you sign out.

**Per-model breakdown** comes from parsing your local Claude Code session logs at `~/.claude/projects/*/*.jsonl` — the `/usage` endpoint returns aggregate percentages only, not a per-model split.

**Refresh cadence:** every 30 seconds. Manual refresh via the Refresh button.

---

## System requirements

- **macOS 14 Sonoma** or later (uses `MenuBarExtra`, `@Observable`, `openSettings` environment action)
- Apple Silicon or Intel (universal binary)
- A paid Claude subscription (Pro, Max 5×, or Max 20×) — the app doesn't support Free or API-key-only accounts
- Claude Code installed locally — used for the per-model breakdown via `~/.claude/projects/`

---

## Installation

**Grab the built app:**
```sh
cp -R build/ClaudeStats.app /Applications/
open /Applications/ClaudeStats.app
```

First launch may prompt Gatekeeper because the app is ad-hoc signed. Right-click the app in Finder → **Open** → **Open** in the dialog. You only have to do this once.

**Launch at login** only works reliably when the app lives in `/Applications/` — `SMAppService` registers against the app bundle path.

---

## Building from source

Requirements:
- Xcode 15+ (for the Swift 5.9 toolchain)
- Python 3 with Pillow (only if regenerating the icon: `pip install Pillow`)

```sh
# Build a release binary and assemble the .app bundle
./scripts/build-app.sh

# Regenerate the app icon (optional)
python3 scripts/make-icon.py
```

The build script:
1. Runs `swift build -c release` (arm64 + x86_64 when possible, falls back to host arch)
2. Assembles `build/ClaudeStats.app` with `Info.plist`, binary, and icon
3. Ad-hoc codesigns the bundle (required for `SMAppService` to work)

---

## Signing in

Inside the app, click **Settings** → **Sign in to Claude.ai**. A login window opens at `claude.ai/login`.

**Supported login methods:**
- Email (magic link won't work inside the embedded window, but if your browser session is already authenticated via the same cookie, you may not need to log in again)
- Manual cookie paste — expand "Paste sessionKey manually" in Settings

**Not supported:** "Continue with Google". Google refuses OAuth inside embedded `WKWebView` sessions as an anti-phishing measure. Use email or the manual paste option.

**Manual paste flow:**
1. Open claude.ai in Safari or Chrome while logged in
2. DevTools (⌥⌘I) → Application → Cookies → `https://claude.ai`
3. Copy the value of the `sessionKey` cookie
4. Paste into the app's Settings

The app then fetches your organization ID automatically and starts polling `/usage`.

---

## Privacy

- All data stays on your Mac. No external services apart from claude.ai itself.
- Your session cookie is stored locally in the app's UserDefaults plist (`~/Library/Preferences/name.horta.albert.ClaudeStats.plist`).
- No analytics, no telemetry, no crash reporting.
- Source is all in this repo — audit it.

---

## Known limitations

- **Claude.ai session endpoint is undocumented.** It could change shape or disappear at any time; if that happens the pace sections will simply go blank until the app is updated.
- **Weekly Opus cap is not separately shown.** Anthropic tracks it internally but the `/usage` endpoint doesn't return it, so the weekly bar represents the combined 7-day limit.
- **Sign-in is required.** Without a claude.ai session the pace sections have no data to show.

---

## Project layout

```
ClaudeStats/
├── Package.swift                       swift-tools-version 5.9, macOS 14
├── Resources/
│   ├── Info.plist                      LSUIElement=true, bundle metadata
│   └── AppIcon.icns                    generated by scripts/make-icon.py
├── Sources/ClaudeStats/
│   ├── App.swift                       @main entry, MenuBarExtra, AppDelegate
│   ├── Core/
│   │   ├── JsonlUsageReader.swift      Streams ~/.claude/projects/*/*.jsonl for per-model split
│   │   ├── StatsStore.swift            Observable store, pace math, remote refresh
│   │   ├── Scope.swift                 UsageScope enum (5h, Week)
│   │   ├── Keychain.swift              Thin UserDefaults shim (misnomer kept)
│   │   ├── ClaudeAIClient.swift        GET /api/organizations/{id}/usage
│   │   └── LaunchAtLogin.swift         SMAppService wrapper
│   └── UI/
│       ├── PopoverView.swift           Main popover layout + PaceView
│       ├── SettingsView.swift          Sign-in + launch at login
│       └── SignInWindow.swift          WKWebView-based cookie capture
└── scripts/
    ├── build-app.sh                    swift build → .app bundle → codesign
    └── make-icon.py                    Pillow-generated AppIcon.icns
```

---

## Credits

- The `/api/organizations/{orgId}/usage` endpoint and its response shape were identified by studying [she-llac/claude-counter](https://github.com/she-llac/claude-counter), a MIT-licensed browser extension that does the same thing in the browser. Huge thanks.

---

## License

ClaudeStats is licensed under the **MIT License**. See [`LICENSE`](./LICENSE) for the full text.

This project incorporates knowledge derived from [she-llac/claude-counter](https://github.com/she-llac/claude-counter) — specifically its identification of the `/api/organizations/{orgId}/usage` endpoint and response shape. `claude-counter` is also MIT-licensed.
