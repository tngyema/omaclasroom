<div align="center">

# 🎓 Omaclasroom

**Google Classroom for the Omarchy Bar**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python 3.10+](https://img.shields.io/badge/Python-3.10+-green.svg)](https://www.python.org/)
[![Platform: Omarchy](https://img.shields.io/badge/Platform-Omarchy-purple.svg)](https://omarchy.org/)
[![PRs Welcome](https://img.shields.io/badge/PRs-Welcome-orange.svg)](#contributing)

</div>

---

## What Is This?

Omaclasroom is a native Omarchy bar widget that brings **Google Classroom** directly into your desktop. View student grades, teacher deadlines, and upcoming assignments — all from your status bar.

No browser needed. No tab switching. Just glance at your bar.

> Built with the same patterns as [Omacanvas](https://github.com/christopherhaynes33/omacanvas), adapted for Google Classroom's OAuth2 API.

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 📊 **Overview Panel** | Course grades, due counts, and next-up assignments at a glance |
| 📝 **Assignments View** | All upcoming work sorted by due date with open/submitted grouping |
| 📚 **Courses View** | Per-course details, assignment lists, and course navigation |
| 🔄 **Auto Refresh** | Configurable refresh interval (default: 6 hours) |
| 🔐 **OAuth2 Auth** | Secure token flow via local browser redirect |
| 🗂️ **Hidden Courses** | Hide courses you don't want to see, restore them anytime |
| ⌨️ **Keyboard Control** | Full keyboard navigation — `1`/`2`/`3` for views, `S`/`T` for roles |
| 🎯 **Student + Teacher** | Automatically detects your role per course |

---

## 📋 Requirements

- **Omarchy** installation with the standard Quickshell bar
- **Python 3.10** or newer
- **`secret-tool`** (from `libsecret`) for secure credential storage
- A **Google Cloud** project with Classroom API enabled and OAuth2 credentials

Install the keyring tool if not already available:

```bash
omarchy pkg add libsecret
```

---

## 🚀 Install

```bash
omarchy plugin add https://github.com/tngyema/omaclasroom.git --enable
```

Choose a bar section when prompted (default: right side).

---

## ⚙️ Setup

### 1. Create Google Cloud Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project (or select existing)
3. Enable the **Google Classroom API**
4. Go to **APIs & Services → Credentials**
5. Create an **OAuth 2.0 Client ID** (Desktop app type)
6. Copy the **Client ID** and **Client Secret**

### 2. Authorize Omaclasroom

Run the token setup and follow the browser prompt:

```bash
~/.config/omarchy/plugins/io.github.omaclasroom/omaclasroom set-token \
  --client-id YOUR_CLIENT_ID \
  --client-secret YOUR_CLIENT_SECRET
```

Your browser will open for Google authorization. After granting access, the token is saved securely in your system keyring.

### 3. Refresh the Widget

Right-click the Omaclasroom bar icon to refresh immediately.

---

## 🎮 Usage

| Action | Method |
|--------|--------|
| Open/close panel | Left-click the bar icon |
| Refresh data | Right-click the bar icon |
| Switch views | Press `1`, `2`, or `3` |
| Switch role (Student/Teaching) | Press `S` or `T` |
| Scroll | Up/Down arrows |
| Refresh | Press `R` or Enter |
| Close panel | Escape |

---

## ⚙️ Settings

Configure via **Setup → Plugins → Omaclasroom** or the terminal:

```bash
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

## 🔑 Manage Credentials

```bash
# Replace or add credentials
omaclasroom set-token --client-id ID --client-secret SECRET

# Remove saved credentials
omaclasroom clear-token
```

---

## 🖥️ Terminal Commands

The helper can also run independently:

```bash
OMACLASROOM=~/.config/omarchy/plugins/io.github.omaclasroom/omaclasroom

$OMACLASROOM fetch --json --days 14
$OMACLASROOM set-token --client-id ID --client-secret SECRET
$OMACLASROOM clear-token
$OMACLASROOM hide-course COURSE_ID --course-name 'Old Course'
$OMACLASROOM unhide-course COURSE_ID
```

---

## 🧪 Development

```bash
# Clone the repo
git clone https://github.com/tngyema/omaclasroom.git
cd omaclasroom

# Run tests
python3 -m unittest discover -s tests -v

# Validate syntax
python3 -m py_compile omaclasroom
python3 -m json.tool manifest.json

# Install locally for testing
omarchy plugin add "$(pwd)" --enable
```

The helper uses **only Python's standard library** — no external dependencies.

---

## 📁 Project Structure

```
omaclasroom/
├── manifest.json          # Plugin metadata & settings schema
├── Panel.qml              # Main bar widget UI (Quickshell)
├── AssignmentLinkRow.qml  # Reusable assignment row component
├── omaclasroom            # Python helper (Google Classroom API)
├── tests/
│   └── test_omaclasroom.py
└── .gitignore
```

---

## 🔒 Privacy

- Sends authenticated HTTPS requests **only** to Google Classroom API
- Credentials stored in the **system keyring**, never written to config files
- Course links open in your default browser
- No data is collected, logged, or sent elsewhere

---

## 🤝 Contributing

Contributions are welcome! Feel free to:

- Report bugs via [Issues](https://github.com/tngyema/omaclasroom/issues)
- Submit pull requests
- Suggest new features

---

## 📜 License

Released under the [MIT License](LICENSE).

---

<div align="center">

**Made with ❤️ for the Omarchy community**

[![GitHub](https://img.shields.io/badge/GitHub-tngyema-181717?logo=github)](https://github.com/tngyema)

</div>
