# MYSTRY-Decompiling

Universal Roblox game dumper and script decompiler. Recreated from SSI++ (SynSaveInstance++), optimized for Solara, Fluxus, Delta, Celery, and Wave executors.

## Features

- **Full Game Dumping** — Saves the entire game hierarchy to `.rbxlx` (XML) format
- **Script Decompilation** — Extracts source from LocalScripts, ModuleScripts, and Scripts
- **25+ Property Serializers** — Handles CFrame, Vector3, Color3, Font, UDim2, Terrain, etc.
- **Universal API Finder** — Auto-detects executor APIs via registry scanning
- **SharedString Deduplication** — Reduces file size by storing repeated strings once
- **SafeMode** — Anti-detection mode for protected games
- **NilInstances** — Dumps instances with no parent
- **KillAllScripts** — Neutralizes game anti-cheat scripts during save
- **Loading String** — Real-time status display showing phase, progress %, and elapsed time

## Scripts

| File | Purpose |
|---|---|
| `save-instance-plus.lua` | Full game dumper — saves entire game to `.rbxlx` |
| `decompile-all.lua` | Quick script-only decompiler — dumps all scripts to text |
| `analyze-binary.ps1` | PE binary analyzer — extracts imports, sections, strings from `.exe` files |

## Usage

### Full Game Save
```lua
local save = loadstring(game:HttpGet("https://raw.githubusercontent.com/mystry112000/MYSTRY-Decompiling/main/save-instance-plus.lua"))()

-- Basic save
save()

-- Custom options
save({
    mode = "full",              -- "full", "optimized", or "scripts"
    noscripts = false,          -- Skip script decompilation
    save_bytecode = true,       -- Save bytecode as base64
    safe_mode = false,          -- Anti-detection (recommended for protected games)
    nil_instances = true,       -- Save instances with no parent
    show_status = true,         -- Show loading string GUI
    timeout = 30,               -- Decompiler timeout in seconds
    readme = true,              -- Generate metadata .txt file
})
```

### Quick Script Decompiler
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/mystry112000/MYSTRY-Decompiling/main/decompile-all.lua"))()
```

### Binary Analyzer (Windows PowerShell)
```powershell
.\analyze-binary.ps1 -FilePath "C:\path\to\file.exe"
```

## Loading String

The script includes a **real-time loading display** that shows:
```
[MYSTRY] Phase: Scanning game | Progress: 23% | Elapsed: 5s | /
```

**Why this matters:** Without a loading indicator, the executor appears frozen during long saves. Users might think it crashed and close it. The loading string updates every 0.25 seconds with:
- **Phase** — Current operation (Scanning, Workspace, LocalPlayer, NilInstances, Writing)
- **Progress %** — Estimated completion percentage
- **Elapsed** — Time since start
- **Spinner** — Visual indicator (`|`, `/`, `-`, `\`)

Color changes: Cyan = working, Green = success, Red = error. Auto-destroys 3 seconds after completion.

## Options Reference

| Option | Type | Default | Description |
|---|---|---|---|
| `mode` | string | `"full"` | Save mode: full/optimized/scripts |
| `noscripts` | bool | `false` | Skip all script decompilation |
| `save_bytecode` | bool | `false` | Save script bytecode as base64 |
| `safe_mode` | bool | `false` | Anti-detection (disables 3D rendering) |
| `nil_instances` | bool | `false` | Save instances without a parent |
| `isolate_local_player` | bool | `false` | Save LocalPlayer separately |
| `isolate_players` | bool | `false` | Save all players separately |
| `ignore_default_properties` | bool | `true` | Skip properties matching default values |
| `timeout` | number | `15` | Decompiler timeout in seconds |
| `readme` | bool | `true` | Generate metadata .txt file |
| `show_status` | bool | `true` | Show loading string GUI |
| `kill_all_scripts` | bool | `false` | Kill game scripts during save |
| `anti_idle` | bool | `false` | Prevent idle kick |
| `anonymous` | bool | `false` | Redact username/userid |
| `shutdown_when_done` | bool | `false` | Close game after save |
| `avoid_file_overwrite` | bool | `true` | Auto-increment filename if exists |

## Supported Executors

| Executor | Compatibility |
|---|---|
| Solara | Full |
| Fluxus | Full |
| Delta | Full |
| Celery | Full (with chunked writing) |
| Wave | Full |
| Synapse X | Full |
| Script-Ware | Full |

## How It Works

1. **Detects executor** via `identifyexecutor()` / `getexecutorname()` / `whatexecutor()`
2. **Finds missing APIs** by scanning the registry for function signatures
3. **Fetches Roblox API** dump from GitHub for property definitions
4. **Traverses game hierarchy** recursively, serializing each instance to XML
5. **Decompiles scripts** using the executor's `decompile()` function
6. **Deduplicates strings** via SharedString system
7. **Writes output** via `writefile()` (or chunked via `appendfile()` for large files)

## Notes

- **Terrain** is NOT included in this version. A separate terrain patch script is available.
- **Server Scripts** cannot be decompiled — they run on Roblox servers, not your client.
- **Large games** (50,000+ instances) may take 2-5 minutes. Don't close the executor.
- **Anti-cheat games** may require `safe_mode = true`.

## License

Recreated from the open-source [UniversalSynSaveInstance](https://github.com/luau/UniversalSynSaveInstance) project.
