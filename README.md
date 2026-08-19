<div align="center">

<a href="https://www.roblox.com/games/93978595733734/Violence-District">
  <img src="https://i.ibb.co.com/mVxPwkN4/no-Filter.webp" width="240">
</a>

# zryx

**zryx** by [zaerrruwww](https://github.com/zaerrruwww) | *Original by [Rzor731](https://github.com/Rzor731)*

Automated Lua script for **Roblox Violence District** featuring Survivor auto farming, low-population server hopping, Discord webhook integration, and automatic re-execution.

![Lua](https://img.shields.io/badge/Language-Lua-2C2D72?style=for-the-badge&logo=lua)
![Roblox](https://img.shields.io/badge/Platform-Roblox-E2231A?style=for-the-badge&logo=roblox)
![Status](https://img.shields.io/badge/Status-Active-22C55E?style=for-the-badge)
![Version](https://img.shields.io/badge/Version-v1.0-blue?style=for-the-badge)
![License](https://img.shields.io/github/license/zaerrruwww/zryx-auto-farm-vd?style=for-the-badge&v=1)

</div>

---

## ✨ Features

- **Auto Farm (Survivor)**  
  - Detects the finish line on supported maps (Rooftop, HooksMeat, Church, etc.)  
  - Teleports the player to the finish after a short delay  
  - Automatically resets on each round  

- **Server Hop**  
  - Hops to servers with exactly **2 players** when a round is active and you are a **Spectator** or **Killer**  
  - Blacklists failed servers (10 minutes) and temporary reserves candidates  
  - Native teleport failure handling with fallback JobId detection  

- **Discord Webhook**  
  - Sends a compact status report after each completed round  
  - Shows **USER**, **STATUS**, **TIME**, **Screws**, **Gears**, and **Level** progression  
  - Persists attribute snapshots locally to avoid duplicate reporting  
  - Includes a **Test Webhook** button for easy configuration  

- **Auto Execute**  
  - Queues the script to re‑execute automatically after teleporting (uses `queue_on_teleport` if available)  

- **Anti-AFK**  
  - Simulates input to avoid the 20‑minute idle disconnect  
  - Runs automatically while the toggle is enabled  

- **Customizable UI**  
  - DPI scaling, corner radius, notification side, custom cursor  
  - Keybind menu (default: `RightShift`)  
  - All settings are saved and loaded automatically  

---

## 🛠️ Installation & Usage

1. **Get the script**  
   - Copy the raw content of `loader.lua` from this repository.

2. **Inject with a Roblox executor**  
   - Use any modern executor (Synapse Z, Krnl, Fluxus, etc.) that supports `loadstring` and HTTP requests.

3. **Paste and execute**  
   - Paste the script into your executor and run it.

4. **Configure the GUI**  
   - Open the menu with **RightShift** (or your custom keybind).  
   - Enable **Auto Farm** and **Server Hop** as needed.  
   - Set your **Webhook URL** and enable Webhook if you want Discord notifications.

5. **Let it run**  
   - The script will automatically farm Survivor rounds, hop servers when idle, and send webhook updates.

---

### 📥 One-Liner Execution
Copy and paste this line into your executor and run it:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/zaerrruwww/zryx-auto-farm-vd/refs/heads/main/loader.lua"))()
```

## ⚙️ Configuration Options

| Option | Description |
|--------|-------------|
| **Enable Auto Farm** | Turns the Survivor teleport farm on/off. |
| **Server Hop** | Automatically hops to low‑pop servers during rounds. |
| **Auto Execute** | Queues the script to re‑run after teleport (requires `queue_on_teleport`). |
| **Anti AFK** | Simulates input to prevent the 20‑minute idle disconnect. |
| **Webhook** | Enable/disable Discord webhook. |
| **Webhook Link** | Your Discord webhook URL (must be valid). |
| **Test Webhook** | Sends a test embed to verify your webhook configuration. |
| **Menu Keybind** | Custom key to open/close the UI (default: `RightShift`). |
| **DPI Scale / Corner Radius** | UI appearance tweaks. |

---

## ⌨️ Default Keybinds

| Action | Key |
|--------|-----|
| **Open/Close GUI** | `RightShift` |
| **Toggle Keybind Menu** | *Via UI toggle* |

> *All other options are controlled through the graphical interface.*

---

## 📦 File Structure

- `loader.lua` – Main script, loads the Obsidian UI library and runs the farm logic.  
- *External dependencies*:  
  - [Obsidian UI Library](https://github.com/deividcomsono/Obsidian) (loaded remotely)  
  - `ThemeManager` and `SaveManager` addons for UI theming and config persistence.

---

## ⚠️ Disclaimer

> **This script is intended for educational purposes only.**  
> Using automation tools in Roblox violates Roblox's Terms of Service.  
> **Use at your own risk.** The developers are not responsible for any account bans, warnings, or data loss.

---

## 🙏 Credits

- **Obsidian UI** – by [deividcomsono](https://github.com/deividcomsono)  
- **zryx** – rebranded and maintained by [zaerrruwww](https://github.com/zaerrruwww)  
- **VD-AUTO-FARM** – original script developed and maintained by [Rzor731](https://github.com/Rzor731)  

---

## 📝 Changelog

- **v1.0.0** – Initial release  
  - Survivor auto‑teleport  
  - Server hop with blacklist  
  - Discord webhook with attribute delta  
  - Auto‑execute on teleport  
  - Full UI with save/load

---

*Happy farming… but remember – play fair!* 😉
