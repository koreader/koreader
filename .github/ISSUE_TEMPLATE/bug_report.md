---
name: Bug report
about: Create a bug report to help us improve
title: ''
labels: ''
assignees: ''

---

* KOReader version:
* Device:

#### Issue

#### Steps to reproduce

##### `crash.log` (if applicable)
`crash.log` is a file that is automatically created when KOReader crashes. It can
normally be found in the KOReader directory:

* `/mnt/private/koreader` for Cervantes
* `koreader/` directory for Kindle
* `.adds/koreader/` directory for Kobo
* `applications/koreader/` directory for Pocketbook

Android won't have a crash.log file because Google restricts what apps can log, so you'll need to obtain logs using `adb logcat KOReader:I ActivityManager:* AndroidRuntime:* DEBUG:* *:F`.


Please try to include the relevant sections in your issue description.
You can upload the whole `crash.log` file on GitHub by dragging and
dropping it onto this textbox.
