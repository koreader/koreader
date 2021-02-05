---
name: Bug report
about: Create a bug report to help us improve
title: ''
labels: ''
assignees: ''

---

# Bug report

**Please note we will close your issue without comment if you delete, do not read or do not fill out the issue checklist below and provide ALL the requested information. If you repeatedly fail to use the issue template, we will block you from ever submitting issues to KOReader again.**

- [ ] checked that my device is actually supported?
- [ ] updated to [last release](https://github.com/koreader/koreader/releases) or [last nightly](http://build.koreader.rocks/download/nightly/) and can still reproduce the bug?

<!-- To help us debug your issue, please complete these sections: -->

<!-- the full KOReader version, for example v2020.11 or v2020.11-55-ge0ac00f
     saying "last stable" or "last nightly" doesn't age well. -->
* KOReader version:
* Device:

#### What you were trying to do

A clear and concise description of the action that triggered the bug

#### What happened

A clear and concise description of what happened

#### Step-by-step reproduction instructions

All steps needed to reproduce the bug

#### `crash.log`

<!--

`crash.log` is a file that is automatically created when KOReader runs. It can
normally be found in the KOReader directory:

* `/mnt/private/koreader` for Cervantes
* `koreader/` directory for Kindle
* `.adds/koreader/` directory for Kobo
* `applications/koreader/` directory for Pocketbook

Android won't have a crash.log file because Google restricts what apps can log, so you'll need to obtain logs using `adb logcat KOReader:I ActivityManager:* AndroidRuntime:* DEBUG:* *:F`.

Unless you're reporting a crash you need to enable debug logs first.
To do that go to the `KOReader's file manager` -> `Tools` -> `More Tools` -> `Developer options` and check `enable debug logging`.

You need to reproduce the issue again *once* debug logs are enabled.

You can upload the whole `crash.log` file on GitHub by dragging and dropping it onto this textbox.
-->

#### test case (if applicable)

<!--

If you're reporting a bug that happens on a given document you need to attach that document to this issue or, better yet, create a test case that showcases the issue you're having.

For copyright materials you'll need to scramble the document before: have a look at [ScrambleEbook calibre plugin](https://www.mobileread.com/forums/showthread.php?t=267998)

-->

