<div align="center">

  <img src="https://capsule-render.vercel.app/api?type=waving&color=0:AF58F9,55:F363E1,100:FFB7D5&height=220&section=header&text=Elysera&fontSize=76&fontColor=ffffff&fontAlignY=36&desc=Universal%20Roblox%20Luau%20Toolkit&descSize=18&descAlignY=58" width="100%" alt="Elysera banner" />

  <h1>✦ E L Y S E R A ✦</h1>
  <p><strong>A modular, customizable Roblox client-side toolkit.</strong></p>
  <p>
    <a href="https://github.com/MinzTogether/Universal-Script"><img src="https://img.shields.io/badge/Project-Universal--Script-AF58F9?style=for-the-badge&logo=github&logoColor=white" alt="Project" /></a>
    <img src="https://img.shields.io/badge/Language-Luau-00A2FF?style=for-the-badge&logo=lua&logoColor=white" alt="Language: Luau" />
    <img src="https://img.shields.io/badge/Interface-Pink%20%2B%20Purple-F363E1?style=for-the-badge" alt="Pink and purple interface" />
    <img src="https://img.shields.io/badge/Status-Development-FFB7D5?style=for-the-badge" alt="Development status" />
  </p>
  <p>
    <a href="#-overview">Overview</a> ·
    <a href="#-features">Features</a> ·
    <a href="#-project-structure">Structure</a> ·
    <a href="#-setup--requirements">Setup</a> ·
    <a href="#-troubleshooting">Troubleshooting</a>
  </p>
  <br />
</div>

---

## 🌸 Overview

**Elysera** is a modular Luau project built around a custom Roblox client-side interface. It brings several utility categories into one window, with a shared visual system, reusable UI components, configurable themes, and separate modules for easier maintenance.

The interface uses a dark plum foundation with pink, sakura, and purple accents. It is designed around a compact tab layout, animated controls, collapsible feature groups, and a movable / resizable window.

> **Project goal:** keep related tools in one consistent interface while allowing each feature area to be developed and maintained independently.

### ✨ Highlights

- **Modular architecture** — feature tabs are separated into individual Lua files and loaded by the main entry point.
- **Custom visual system** — shared cards, switches, dialogs, notifications, icons, and animated transitions.
- **Theme support** — color palettes can be changed without rebuilding the entire interface.
- **Persistent preferences** — supported environments can save interface settings and feature data locally.
- **Resilient module loading** — the loader includes a local cache and a retry state for modules that fail to download or initialize.
- **Discord repository notifications** — an optional GitHub Actions workflow can forward repository activity to a Discord webhook.

---

## 🎨 Interface & Design

Elysera uses a dark, softly glowing palette inspired by sakura pink and neon purple.

| Design token | Hex | Purpose |
|---|---:|---|
| Background | <code>#1D1534</code> | Main window |
| Panel | <code>#21153A</code> | Cards, buttons, dialogs |
| Panel Alt | <code>#251942</code> | Sidebar and secondary panels |
| Header | <code>#31204B</code> | Top bar and highlighted areas |
| Border | <code>#543580</code> | Borders and separators |
| Accent Pink | <code>#F363E1</code> | Primary accent and active states |
| Accent Purple | <code>#AF58F9</code> | Secondary accent and gradients |
| Sakura | <code>#FFB7D5</code> | Selected text and highlights |
| Main Text | <code>#E2BEFA</code> | Primary text |
| Sub Text | <code>#BF9DEE</code> | Secondary text |
| Danger | <code>#F7768E</code> | Warnings and destructive actions |

The UI also includes animated tab transitions, hover and press feedback, gradient accents, confirmation dialogs, toast notifications, and a floating toggle button.

---

## 🚀 Features

The repository is organized into five main tabs. The list below summarizes the capabilities described by the current module source; actual availability depends on the source being valid and the runtime supporting the required APIs.

### 1. 🌐 Status & Server

Server navigation and session utilities:

- Join a server using a Job ID or a supported Roblox server link.
- Copy a server join link and rejoin the current server.
- Browse public servers and view available player / ping / FPS information.
- Sort or choose servers using options such as **Server Hop**, **Less People**, and **Best Ping**.
- Keep a recent-server history and return to a previously visited server.
- Configure automatic rejoin after a disconnect or kick, with safeguards intended to prevent endless retry loops.

### 2. 🧭 Local

Local character, camera, and visual utilities:

| Category | Features described in the source |
|---|---|
| Movement | Speed, Jump Boost, Gravity, Infinite Jump, Noclip, Fly |
| Teleport | Click Teleport, Coordinates, Waypoints, Player Teleport |
| Quick Actions | Back, Unstuck, Respawn |
| Camera | Field of View, Max Zoom, Min Zoom, Freecam |
| Visual | ESP, Hide Players, Full Bright, Time of Day |
| Safety / Utility | Anti AFK, Anti Void, Reset All |

### 3. 📊 FPS

Performance monitoring and display controls:

- Monitor FPS, frame time, ping, memory usage, and a performance graph.
- Choose an FPS profile, set an FPS cap, and use Auto Boost.
- Additional optimization options include Hide Far Players and Mute Audio.
- Screen options include AFK Mode, White Screen, Black Screen, and Idle Saver.
- Configure the FPS overlay, including average FPS, 1% low, and RAM information.
- Manage selected interface elements such as notifications, chat, and the player list.

### 4. 🧩 Script Library

A built-in library for organizing and managing user-provided scripts:

- Save, edit, duplicate, pin, export, and import entries.
- Search and sort scripts by **Added**, **A–Z**, **Edited**, or **Recent**.
- Undo a deletion during the available undo window.
- Run and stop scripts, inspect output, run clipboard content, and test scripts from the dialog.
- View last-run information for individual entries.
- Configure per-script auto-run rules, including selected games, with a global pause control.
- Review imported scripts before running them.
- Use editor conveniences such as line numbers and syntax coloring.

**Important:** only run code you understand and trust. Imported or copied scripts can perform actions beyond what their names suggest.

### 5. ⚙️ Settings

Interface configuration and diagnostics:

- Change the UI theme.
- Configure UI scale, reduced motion, and the menu hotkey.
- Enable or disable Auto Execute after a teleport, when the runtime supports it.
- Restore selected feature states after a server change.
- Export, import, or reset supported configuration data.
- View runtime / executor API diagnostics and module loading sources.
- Copy a diagnostic report, check for updates, reload, or unload Elysera.

---

## 🗂️ Project Structure

~~~text
Universal-Script/
│
├── MainWeb.lua                 # Main entry point and shared UI foundation
├── Status_Server.lua           # Status & Server tab
├── Local.lua                   # Local character / camera / visual tools
├── FPS.lua                     # Performance monitor and FPS options
├── Script.lua                  # Script Library
├── Settings.lua                # Themes, preferences, configuration, diagnostics
│
└── .github/
    ├── scripts/
    │   └── discord_notify.py    # GitHub event → Discord notification helper
    │
    └── workflows/
        └── discord-monitor.yml # Discord Repository Monitor workflow
~~~

### How the modules fit together

1. <code>MainWeb.lua</code> creates the shared interface, theme tokens, UI helpers, tab system, and runtime context.
2. It downloads the five feature modules from the repository's raw GitHub content.
3. Each module receives a shared context and builds its own tab.
4. Successfully initialized module source can be cached locally when file-system APIs are available.
5. <code>Settings.lua</code> is loaded last so the saved theme can be applied to the complete interface.

The current loader points to the <code>main</code> branch through <code>MODULE_REF</code>. This means module updates on that branch can affect subsequent loads.

---

## 🧰 Setup & Requirements

### Runtime requirements

This repository is **not a standalone Roblox Studio plugin, Roblox experience, or ordinary LocalScript package**. <code>MainWeb.lua</code> expects a client-side Luau environment that exposes Roblox services and certain environment-specific capabilities.

| Capability | Used for | Requirement |
|---|---|---|
| Client-side Roblox services | Player, UI, input, camera, and game state | Required |
| <code>loadstring</code> | Compiling the entry point and downloaded modules | Required by the loader |
| HTTP access | Downloading modules from GitHub | Required |
| File read / write APIs | Saved settings, library data, and module cache | Optional; persistence is limited without them |
| Folder APIs | Keeping data inside <code>workspace/Elysera/</code> | Optional |
| Clipboard API | Copy actions and diagnostic reports | Optional |
| <code>queue_on_teleport</code> equivalent | Auto Execute after teleports | Optional; needed for that feature |

The loader checks several common HTTP and clipboard function names, but compatibility is not guaranteed. Different environments expose different APIs and may behave differently.

### Entry point

<code>MainWeb.lua</code> is the entry point. The feature files are loaded by the entry point from the repository's raw GitHub content, rather than being independently launched as separate tabs.

Before attempting to run the project, review the repository health note below. The current default-branch snapshot contains unresolved merge-conflict markers, so the source needs cleanup and validation first.

### Local data

When file-system support is available, the main script organizes persistent data under:

~~~text
workspace/
└── Elysera/
    ├── Elysera_Settings.json
    ├── Elysera_Fps.json
    ├── Elysera_Waypoints.json
    ├── Elysera_Servers.json
    ├── L-scr.json
    ├── L-scr.bak.json
    ├── L-scr.state.json
    └── cache_*.lua
~~~

The exact files present depend on which features have been used. These files may contain personal preferences, saved waypoints, server history, script-library entries, and cached module source. Review them before sharing them with anyone.

---

## ⚠️ Repository Health Note

**The current <code>main</code> branch should be treated as a development snapshot, not a verified stable release.**

During the README review, unresolved Git merge-conflict markers were found in multiple Lua files, including the main entry point and feature modules. The markers include:

~~~text
<<<<<<< HEAD
=======
>>>>>>> ...
~~~

These are Git conflict artifacts, not valid Luau syntax. They can cause compilation or loading failures until the conflicting sections are resolved.

Before calling a build usable:

1. Resolve every conflict marker in the affected Lua files.
2. Review both sides of each conflict and keep the intended implementation.
3. Run a syntax check / validation in the intended Luau environment.
4. Test each tab and optional API independently.
5. Verify that the module loader, cache fallback, settings persistence, and teleport behavior work as expected.

No successful runtime test is claimed by this README.

---

## 🔔 Discord Repository Notifications

The repository includes a GitHub Actions workflow named **Discord Repository Monitor**. It can send notifications for repository activity such as pushes, branches, pull requests, issues, comments, releases, workflow results, and other supported GitHub events.

To enable it:

1. Create a Discord webhook in the destination channel.
2. Open the repository's **Settings → Secrets and variables → Actions**.
3. Add a repository secret named <code>DISCORD_WEBHOOK</code>.
4. Trigger a supported repository event or run the workflow manually.

Keep the webhook URL private. Never commit it to the repository or paste it into public issues.

The helper script uses the Python standard library and is designed to run inside GitHub Actions. This workflow is for notifications; it is not a Lua build or test pipeline.

---

## 🛠️ Troubleshooting

| Symptom | Possible reason | What to check |
|---|---|---|
| Main script does not start | Unsupported runtime API or unresolved source conflict markers | Check the runtime output and inspect the Lua source |
| A tab shows a module error | HTTP request failed, timed out, or module initialization failed | Check network access, the module URL, and the displayed error |
| A feature does not save its state | File-system APIs are unavailable or writes failed | Check file API support and the <code>Elysera</code> data folder |
| Auto Execute is unavailable | Required teleport queue or file APIs are missing | Review the Auto Execute diagnostic reason |
| Clipboard action fails | No supported clipboard function is exposed | Check the runtime's clipboard API support |
| Theme or settings do not persist | Settings file cannot be read or written | Check file permissions and saved JSON data |

The module loader includes a Retry action and can use a previously cached module after a download or initialization failure. A cached copy does not fix an error in the main entry point itself.

---

## 🔒 Safety, Fair Use & Responsibility

- Use this project only in environments and experiences where you are permitted to do so.
- Client-side modifications, automation, teleportation, or other gameplay changes may conflict with Roblox rules or an individual experience's rules.
- Do not use the project to harass players, disrupt experiences, bypass access controls, or gain unauthorized access to other people's data.
- Review every imported script before running it. A script can do more than its description claims.
- Keep private configuration files, webhook URLs, tokens, and diagnostic information out of public commits.
- You are responsible for understanding the behavior and consequences of any code you choose to run.

---

## 🤝 Contributing

Contributions, bug reports, and thoughtful suggestions are welcome.

1. Open an issue with a clear description and reproduction details.
2. Keep changes focused and avoid mixing unrelated refactors.
3. Preserve the modular architecture and shared UI conventions.
4. Keep Lua comments, UI text, messages, and names in **English (US)**, as required by the source-file headers.
5. Test the affected module and explain what was verified in the pull request.

Please do not submit secrets, private webhook URLs, personal data, or unreviewed third-party scripts.

---

## 📄 License

No <code>LICENSE</code> file is currently present in this repository. Until a license is added, do not assume that the source is free to reuse, redistribute, or publish in modified form. Contact the repository owner for permission.

---

<div align="center">

  <h3>Made with 💜 and 🌸</h3>
  <p><strong>Elysera</strong> · A modular toolkit by <a href="https://github.com/MinzTogether">MinzTogether</a></p>
  <p>
    <a href="https://github.com/MinzTogether/Universal-Script">Repository</a>
    ·
    <a href="https://github.com/MinzTogether/Universal-Script/issues">Report an issue</a>
  </p>
  <sub>Documentation reflects the repository source reviewed on 2026-10-31.</sub>

</div>
