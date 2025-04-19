---
name: Bug report
about: Create a bug report to help us improve the application
title: ''
labels: ''
assignees: ''

---

* KOReader version:
* Device:

#### Issue

#### Steps to reproduce

##### `crash.log` (if applicable)
`crash.log` is a file that is automatically created when KOReader crashes. It can normally be found in the KOReader directory:

| Device      | Path                        |
|-------------|-----------------------------|
| Cervantes   | `/mnt/private/koreader`      |
| Kindle      | `koreader/`                  |
| Kobo        | `.adds/koreader/`            |
| Pocketbook  | `applications/koreader/`     |
| Android | Logs are kept in memory. Please go to [Menu] → Help → Bug Report to save these logs to a file. |
| Deb / Flatpak / AppImage | On regular desktop systems, logs can be obtained by running `koreader-20xx 2>&1 \| tee log.txt` from the terminal. |

Please try to include the relevant sections in your issue description.
You can upload the whole `crash.log` file (zipped if necessary) on GitHub by dragging and dropping it onto this textbox.

If your issue doesn't directly concern a Lua crash, we'll quite likely need you to reproduce the issue with *verbose* debug logging enabled before providing the logs to us.
To do so, go to `Top menu → Hamburger menu → Help → Report a bug` and tap `Enable verbose logging`. Restart as requested, then repeat the steps for your issue.

If you instead opt to inline it, please do so behind a spoiler tag:
<details>
  <summary>crash.log</summary>

```
<Paste crash.log content here>
```
</details>
