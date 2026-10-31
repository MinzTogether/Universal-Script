<div align="center">

  <img src="assets/elysera-banner.webp" width="100%" alt="Elysera banner with centered title" />

  <p><strong>A modular Roblox client-side toolkit built with Luau.</strong></p>
  <p>
    <a href="https://github.com/MinzTogether/Universal-Script">GitHub Repository</a>
    ·
    <a href="https://www.design-ac.net/ja/free-template/twitter-header-template-5922">Banner artwork · Design AC</a>
  </p>
  <p>
    <img src="https://img.shields.io/badge/LANGUAGE-Luau-00A2FF?style=flat-square&logo=lua&logoColor=white" alt="Luau" />
    <img src="https://img.shields.io/badge/INTERFACE-Pink%20%2B%20Purple-F363E1?style=flat-square" alt="Pink and purple interface" />
    <img src="https://img.shields.io/badge/ARCHITECTURE-Modular-AF58F9?style=flat-square" alt="Modular architecture" />
  </p>

</div>

---

## 🌸 About Elysera

**Elysera** is a modular Luau project that brings a collection of Roblox client-side utilities into one unified interface.

Designed with a dark purple foundation and soft pink accents, Elysera focuses on a clean visual experience, convenient controls, and a modular structure. Each feature category is organized into its own tab, while shared interface components and settings help keep the experience consistent.

The goal is simple: **one interface, multiple utility categories, and a consistent design.**

## ✨ Main Features

### 🌐 Status & Server
Tools for server navigation and session management.

- Join a server using a Job ID or supported server link.
- Rejoin the current server or copy a join link.
- Browse public servers and view available player, ping, and FPS information.
- Find servers with options such as Server Hop, Less People, and Best Ping.
- Keep a recent-server history and return to a previous server.
- Optional automatic rejoin after a disconnect.

### 🧭 Local
Character, movement, camera, and visual utilities.

- **Movement:** Speed, Jump Boost, Gravity, Infinite Jump, Noclip, and Fly.
- **Teleport:** Click Teleport, Coordinates, Waypoints, and Player Teleport.
- **Quick Actions:** Back, Unstuck, and Respawn.
- **Camera:** Field of View, Max Zoom, Min Zoom, and Freecam.
- **Visual:** ESP, Hide Players, Full Bright, and Time of Day.
- **Utilities:** Anti AFK, Anti Void, and Reset All.

### 📊 FPS
Performance information and interface optimization.

- Monitor FPS, frame time, ping, memory usage, and performance graphs.
- Configure FPS profiles, FPS caps, and Auto Boost.
- Additional options such as Hide Far Players and Mute Audio.
- Screen modes including AFK Mode, White Screen, Black Screen, and Idle Saver.
- Customizable FPS overlay with average FPS, 1% low, and RAM information.
- Options for managing notifications, chat, and the player list.

### 🧩 Script Library
A built-in space to organize and manage scripts.

- Save, edit, duplicate, pin, export, and import scripts.
- Search and sort entries by Added, A–Z, Edited, or Recent.
- Run and stop scripts, view output, and check last-run information.
- Run clipboard content or test a script from its editor.
- Configure per-script auto-run preferences, including selected games.
- Review imported scripts before running them.

Always review scripts before running them and only use code from sources you trust.

### ⚙️ Settings
Personalize the interface and manage preferences.

- Switch between available color themes.
- Adjust UI scale, reduce motion, and configure the menu hotkey.
- Configure Auto Execute and restore selected feature states after a server change.
- Export, import, or reset supported settings.
- View runtime diagnostics and module loading information.
- Check for updates, reload, or unload Elysera.

## 🎨 Designed to Feel Consistent

Elysera uses a dark plum palette with pink, purple, and sakura highlights.

| Color | Hex |
|---|---|
| Background | <code>#1D1534</code> |
| Panel | <code>#21153A</code> |
| Header | <code>#31204B</code> |
| Border | <code>#543580</code> |
| Accent Pink | <code>#F363E1</code> |
| Accent Purple | <code>#AF58F9</code> |
| Sakura | <code>#FFB7D5</code> |

The interface includes animated tab transitions, gradient accents, floating controls, customizable themes, confirmation dialogs, and toast notifications.

## 🧩 Modular Structure

| File | Purpose |
|---|---|
| <code>MainWeb.lua</code> | Main entry point and shared interface |
| <code>Status_Server.lua</code> | Status & Server features |
| <code>Local.lua</code> | Character, camera, and visual utilities |
| <code>FPS.lua</code> | Performance monitor and FPS options |
| <code>Script.lua</code> | Script Library |
| <code>Settings.lua</code> | Themes, preferences, and diagnostics |

Each module handles its own feature tab and uses the shared interface provided by the main entry point.

---

<div align="center">

  <h3>Made with 💜 by MinzTogether</h3>
  <a href="https://github.com/MinzTogether/Universal-Script">Explore Elysera on GitHub</a>

</div>
