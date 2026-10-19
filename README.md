# Outlook for Mac (OWA wrapper)

A Mac-native wrapper around Outlook Web App (OWA) for on-premises Exchange
servers. It loads your organization's OWA in a WebKit window and adds:

- Mac menu commands and keyboard shortcuts for mail, calendar, people and tasks
- Shortcuts / App Intents actions: compose, search, unread count, recent
  messages, next meeting, today's meetings, open a view, find messages
- Automations (Settings > Automations): run a Shortcut on new mail, before a
  meeting, when the unread count changes, or on sign-out
- Sign-in credentials kept in the Keychain; a user stylesheet you can edit
  (View > Edit Stylesheet…)

## Requirements

- macOS 14 or later
- Xcode with Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

The Xcode project is generated from `project.yml` and is not checked in, so
run XcodeGen first:

```sh
xcodegen generate && xcodebuild
```

Or run `xcodegen generate` and open `OutlookMac.xcodeproj` in Xcode.

## First run

On first launch the app asks for your Exchange server's OWA address, for
example `https://mail.example.com/owa/`. Only `https://` addresses are
accepted. Change it later from the app menu with Change Server….

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Cmd-N | New message |
| Cmd-R | Reply |
| Shift-Cmd-R | Reply all |
| Shift-Cmd-F | Forward |
| Opt-Cmd-F | Search |
| Opt-Cmd-P | Pin |
| Shift-Cmd-J | Mark as junk |
| Ctrl-Cmd-A | Archive |
| Shift-Cmd-L | Flag |
| Shift-Cmd-U | Mark as read |
| Opt-Shift-Cmd-U | Mark as unread |
| Cmd-1 / Cmd-2 / Cmd-3 / Cmd-4 | Inbox / Calendar / People / Tasks |
| Ctrl-Cmd-1 to Ctrl-Cmd-4 | Calendar day / work week / week / month |
| Opt-Cmd-R | Reload |
| Cmd-= / Cmd-- | Zoom in / out |
| Cmd-0 | Reset zoom to the default 90% |

The full list is in the Mail, Calendar, People, Tasks and View menus
(`Menus/AppCommands.swift`).

## Status

Experimental and unsigned. Build it yourself; macOS will not open a
downloaded copy without Gatekeeper approval.
