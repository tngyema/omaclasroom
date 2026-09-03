# Omaclasroom

[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)](LICENSE)
[![Platform: Omarchy](https://img.shields.io/badge/Platform-Omarchy-purple?style=for-the-badge)](https://omarchy.org/)
[![Python 3.10+](https://img.shields.io/badge/Python-3.10+-green?style=for-the-badge)](https://www.python.org/)

**Google Classroom grades and assignments in your Omarchy bar.** Check your grades, track deadlines, and never miss an assignment again.

![Student View](Pictures/omaclasroom1.png)
![Assignments](Pictures/omaclasroom2.png)
![Courses](Pictures/omaclasroom3.png)
![Missing](Pictures/omaclasroom4.png)

---

## Quick Start

> **Requires Python 3.10+** and **`libsecret`** for credential storage.

Install the plugin and its dependency:

```sh
omarchy pkg add libsecret
omarchy plugin add https://github.com/tngyema/omaclasroom.git --enable
```

Then authorize with Google:

```sh
~/.config/omarchy/plugins/io.github.omaclasroom/omaclasroom set-token \
  --client-id YOUR_CLIENT_ID \
  --client-secret YOUR_CLIENT_SECRET
```

Your browser will open for Google authorization. After granting access, the refresh token is saved permanently — you never need to authorize again.

---

## Features

| Feature | Description |
|---------|-------------|
| **Overview Panel** | Course grades, due counts, and next-up assignments at a glance |
| **Assignments View** | All upcoming work sorted by due date |
| **Courses View** | Per-course details and assignment lists |
| **Missing View** | Overdue assignments with one-click open |
| **Auto Refresh** | Configurable interval (default: 6 hours) |
| **OAuth2 Auth** | Secure token flow via local browser redirect |
| **Keyboard Control** | Full navigation — `1`-`4` views, `S`/`T` roles, `R` refresh |

---

## Usage

| Action | Method |
|--------|--------|
| Open/close panel | Left-click the bar icon |
| Refresh data | Right-click the bar icon |
| Switch views | Press `1`, `2`, `3`, or `4` |
| Switch role | Press `S` or `T` |
| Refresh | Press `R` |
| Close panel | Press `Escape` |

---

## Configuration

```sh
# Change assignment window to 21 days
omarchy bar set io.github.omaclasroom days 21 --json

# Change refresh to every 3 hours
omarchy bar set io.github.omaclasroom refreshIntervalSec 10800 --json
```

| Setting | Default | Range | Description |
|---------|---------|-------|-------------|
| `days` | 14 | 1–60 | Assignment window in days |
| `refreshIntervalSec` | 21600 | 300–86400 | Auto-refresh interval |

---

## Google Cloud Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project (or select existing)
3. Enable the **Google Classroom API**
4. Go to **APIs & Services → Credentials**
5. Create an **OAuth 2.0 Client ID** (Desktop app type)
6. Copy the **Client ID** and **Client Secret**

---

## Credential Persistence

Omaclasroom uses OAuth2 **refresh tokens** for permanent authentication. You only need to authorize once — the token persists across reboots.

### How It Works

1. `set-token` opens your browser for a one-time Google consent
2. A refresh token is saved to your **system keyring** (or `credentials.json` as fallback on systems without `libsecret`)
3. Every refresh cycle, the stored token silently obtains a new access token — no browser, no interaction required

### When You Need to Re-authorize

- You run `omaclasroom clear-token`
- You revoke access in [Google Account permissions](https://myaccount.google.com/permissions)
- Google invalidates the token (rare — typically after 6+ months of non-use)

---

## Remove

```sh
omarchy plugin remove io.github.omaclasroom
```

---

## Privacy

- Sends authenticated HTTPS requests **only** to Google Classroom API
- Credentials stored in the **system keyring** when available, with a **file-based fallback** for systems without `libsecret`
- Credentials file uses `0600` permissions (owner-read-only)
- No data is collected, logged, or sent elsewhere

---

## Teacher Mode

**Coming soon.** Grading views, assignment management, and student progress tracking are in development.

---

## Support

If you find Omaclasroom helpful, please consider giving it a ⭐️ to show your support!

---

## License

[MIT License](LICENSE)
