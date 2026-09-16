# Data Storage

Everything Fancychat saves to disk lives under your Ashita install. All data files are scoped **per character** — each character on your account has its own settings, palette, notes, and saved logs.

## File layout

```
Ashita/
├── addons/fancychat/
│   ├── chatcolors/
│   │   └── colorset_*                      ← exported color palettes (you can keep many per character)
│   ├── combatfilters/
│   │   ├── example.txt                     ← shipped default filter set
│   │   └── *.txt                           ← user-managed extra filter files
│   ├── maps/
│   │   └── <Zone Name>/
│   │       ├── Maps/                       ← base floor / area maps
│   │       ├── Treasure/                   ← coffer-spawn maps
│   │       ├── Fishing/                    ← fishing-spot maps
│   │       ├── Weather/                    ← elemental-spawn maps
│   │       └── Notorious_Monsters/         ← NM maps + _nm_index.lua
│   ├── notifications/
│   │   ├── notification_1.wav              ← replace with your own to customise slot 1
│   │   ├── notification_1B.wav             ← boosted variant for slot 1 (Volume Boost)
│   │   ├── notification_2.wav
│   │   └── ...                             ← 6 fixed slots + matching B variants
│   ├── gdifonts/
│   │   ├── gameicons.ttf                   ← custom-icon font for compact combat log
│   │   └── gdifonttexture.dll              ← icon-rendering helper
│   ├── images/                             ← UI textures
│   └── ...
└── config/addons/fancychat/
    ├── <character>/
    │   └── settings.json                   ← persisted user settings (per character)
    ├── translate/
    │   └── dict.txt                        ← shared ASCII → Japanese dictionary
    └── logs/
        └── <character>/
            └── ChatLogs_YYYY_MM_DD-HH_MM_SS/
                ├── All.txt
                ├── Combat.txt
                ├── Linkshell.txt
                ├── Party.txt
                ├── Tell.txt
                ├── Shout.txt
                └── Custom.txt
```

> **Note:** saved chat logs live under `config/addons/fancychat/logs/`, **not** under the addon folder. The addon folder (`addons/fancychat/`) holds code, palettes, filters, sounds, and maps; the config folder (`config/addons/fancychat/`) holds per-character settings and saved logs. Both must be backed up to migrate everything.

## settings.json

Settings are saved automatically every time you change anything in the Settings panel. The file holds:

- Which tab each chat window is currently showing
- Font size, chat width, number of chat lines
- Plate background opacity, position offsets
- Keyboard shortcut combos and their enabled / disabled state
- Colorblind mode, custom-tab message types, chat-word alert list
- Your Notepad notes
- The currently selected combat-filter file, notification sound, and alert sound
- The on/off state of every checkbox in the Settings panel
- Translation provider and API key (Settings → Translate)

If your settings get into a bad state, deleting this file makes Fancychat fall back to defaults on next load. You will not lose any chat history — that lives in memory only — but you will lose your Notepad notes.

## Translate dictionary

Path: `Ashita/config/addons/fancychat/translate/dict.txt`

Tab-separated source → Japanese pairs written when ASCII chat is translated. Shared across characters. API keys for ChatGPT / Gemini / DeepL live in per-character `settings.json`, not in this file.


## Color sets

Plain-text `key,value` files written by **Settings → Font Colors → Export Colors**. One file per character. See [Color Palettes → Sharing palettes](Color-Palettes.md#sharing-palettes) for sharing across characters or with another player.

## Combat filter files

User-managed `.txt` files in `combatfilters/`. Pick the active one with **Settings → CL Filters → Active filter file** dropdown. See [Combat Filters](Combat-Filters.md) for filter syntax.

## Saved chat logs

Path: `Ashita/config/addons/fancychat/logs/<character>/ChatLogs_<timestamp>/`

Written **on demand** — by the **Save Chat Logs** button in **Settings → Tools** or the `/fchat savelogs` command. **They are NOT auto-saved on unload.** One subfolder per save, one `.txt` per chat tab. The unload handler only persists settings and (if **Auto-restore logs when opening Legacy Chat** is on) re-injects the buffer into the legacy chat — neither writes log files.

## Notification sounds

`addons/fancychat/notifications/` ships with six fixed sound slots: `notification_1.wav` through `notification_6.wav` (plus a `notification_<n>B.wav` boosted variant of each for the **Volume Boost** option). The **Incoming /tell notifications** and **Chat word alert** dropdowns in **Settings → Extra** offer exactly those six slots — the folder is **not** scanned for additional files.

To customise a sound, **replace** the existing `.wav` file with one of your own, keeping the exact filename. For example, to change the third notification:

- Replace `notification_3.wav` with your own sound (any standard `.wav` works).
- If you want Volume Boost to work for that slot, also replace `notification_3B.wav` with a louder copy (typically the same audio amplified by a few dB).

Adding `notification_7.wav` or any other new filename does nothing — it won't appear in the dropdown.

## Backup / migration

To back up everything, copy these two folders:

- `Ashita/addons/fancychat/` — addon code, color sets, combat filters, sounds, maps
- `Ashita/config/addons/fancychat/` — per-character settings and saved chat logs

To migrate to a new install, drop both folders in place. To share with another player, send only the specific files you want them to have (most often: a `chatcolors/colorset_*` or a `combatfilters/*.txt`).

## See also

- [Color Palettes](Color-Palettes.md) — palette file format and sharing
- [Combat Filters](Combat-Filters.md) — filter file format and scope syntax
- [Companion Panels → Notepad](Companion-Panels.md#notepad) — Notepad persistence
