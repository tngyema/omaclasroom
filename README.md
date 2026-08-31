# Omaclasroom

Google Classroom grades and upcoming assignments for the Omarchy bar.

## Install

```sh
omarchy plugin add https://github.com/tngyema/omaclasroom.git --enable
```

## Setup

Install the keyring dependency:

```sh
omarchy pkg add libsecret
```

Create Google Cloud credentials with Classroom API enabled, then authorize:

```sh
~/.config/omarchy/plugins/io.github.omaclasroom/omaclasroom set-token \
  --client-id YOUR_CLIENT_ID \
  --client-secret YOUR_CLIENT_SECRET
```

Your browser will open for Google authorization. After granting access, the token is saved securely in your system keyring.

## Usage

- **Left-click** the bar icon to open/close the panel
- **Right-click** to refresh data
- Press `1`-`4` to switch views (Overview, Assignments, Missing, Courses)
- Press `S`/`T` to switch between Student and Teacher roles
- Press `R` to refresh, `Escape` to close

## Configure

```sh
# Change assignment window to 21 days
omarchy bar set io.github.omaclasroom days 21 --json

# Change refresh to every 3 hours
omarchy bar set io.github.omaclasroom refreshIntervalSec 10800 --json
```

## Remove

```sh
omarchy plugin remove io.github.omaclasroom
```
