# Installation

## Requirements

- A working [Ashita v4](https://www.ashitaxi.com/) installation pointed at your FFXI client.
- Windows (the addon ships a Windows-only `gdifonttexture.dll` for its custom font rendering).

## Steps

1. Grab the latest archive from the [FancyChatJP Releases](https://github.com/handomade/FancyChatJP/releases) page (not the original Arielfy FancyChat).
2. **Delete** any existing `Ashita/addons/fancychat` folder first (CatsEyeXI ships an older Arielfy build). Mixing files causes `ApplyWindowTabBuffer` nil errors.
3. Extract so that `fancychat.lua` sits directly in `Ashita/addons/fancychat/` (not one folder deeper, e.g. `fancychat/FancyChatJP-main/`).
4. Launch FFXI through Ashita as you normally would.
5. In game, type:
   ```
   /addon load fancychat
   ```
   The load line must read **`fancychat version: 1.1.8 - by: Hando`**. If it still says `0.9.xxxxxx - by: Arielfy`, the original addon is still the one being loaded.

On **CatsEyeXI**, open the launcher **ADDONS** tab and tick **Ignore Updates** for FancyChat. Otherwise the next addon update restores the bundled Arielfy build over FancyChatJP. That writes `fancychat` into `IgnoreUpdatesAddons` in `cexi_settings.json` (same folder as the launcher exe, e.g. `C:\Games\CatsEyeXI\cexi_settings.json`, not inside `Ashita`). Leaving the box unchecked is not a guarantee the files stay; tick it whenever you run JP.

ImGui tabs (and XIUI) need Japanese on Ashita's default ImGui font. That is not the GDI chat face.

1. Copy `C:\Windows\Fonts\meiryo.ttc` to `Ashita\resources\fonts\meiryo.ttc`.
2. Append the following to `Ashita\config\boot\catseyexi.ini`:

   ```
   [ashita.imgui.fonts]
   font0.family = meiryo.ttc
   font0.is_jp = true
   ```

3. Fully restart FFXI. The log should show `Loaded Font: meiryo.ttc, 18px - is_jp: 1`.

Those three lines must remain in the ini on every launch. If the CatsEyeXI launcher rewrites the file and drops them, set `"ResetIniFiles"` to `false` in `cexi_settings.json` (launcher folder, not `Ashita`), restore the three lines, and start again. See [Troubleshooting](Troubleshooting.md) if the launcher then fails to start.

The Fancychat plate will appear in the top-left of the screen. From there, type `/fchat manual` to open the in-game manual or `/fchat settings` to configure.

## VanaCore

CatsEyeXI does not use this package. On VanaCore, ImGui (settings, tabs, and XIUI) needs a separate setup zip. It is not the addon itself. It overlays the VanaCore Japanese files onto an existing FancyChatJP and XIUIJP install.

Download: [VanaCore.zip](https://github.com/handomade/FancyChatJP/releases/download/1.1.4/VanaCore.zip). Unzipping it produces the `VanaCore日本語セットアップ` folder.

1. Close VanaCore and Ashita.
2. Unzip and place that folder beside the `Ashita` and `Vanacore` folders.
3. Run `適用.bat`.

It sets `ashita.interface=4.30`, copies FancyChat window positions from the Ashita `imgui.ini`, overlays the VanaCore font files, copies Meiryo into VanaCore when Windows has it and VanaCore does not, and places `gameicons.ttf` where VanaCore loads combat icons. Previous files are kept under that folder's `backup`. Start VanaCore again afterward. Chat lines stay on the GDI font. On Japanese Windows, if the face name `Meiryo` produces no glyphs, the same face is requested as `メイリオ`.

With the chat windows locked and "move so it does not cover the FFXI UI" on, the lower window slides aside when the NPC selection menu overlaps it. VanaCore's `menu.rows` in `vanacore.ini` (3–12; the retail menu is 3) changes how many rows that menu shows. Set FancyChat's "selection menu rows" to the same number. `3` keeps the previous overlap test.

## Auto-loading on every launch

If you want Fancychat to load automatically at every game launch, add `/addon load fancychat` to your Ashita default script. In Ashita Boot's profile editor, that's the **Default Script** field.

> **Tip:** if you're loading other chat-touching add-ons alongside Fancychat, put `/addon load fancychat` **last** in the list. Fancychat is unsupported in that configuration, but loading it last gives the best odds of avoiding visual conflicts. See [Compatibility](Compatibility.md).

## Updating

1. Your settings and Notepad notes live separately in `Ashita/config/addons/fancychat/<character>/settings.json`, so they're preserved automatically across updates — nothing to do.
2. Your **custom color palettes** live in `addons/fancychat/chatcolors/` and your **custom combat filters** in `addons/fancychat/combatfilters/`. If you've created any, **back those two folders up** before overwriting the addon folder — depending on how you extract the new release, they may be overwritten or deleted.
3. Replace the contents of `Ashita/addons/fancychat/` with the new release.
4. Drop your backed-up `chatcolors/` and `combatfilters/` files back in if they got removed.

See [Data Storage](Data-Storage.md) for the full on-disk layout.

## Uninstall

Delete the `fancychat/` folder from `Ashita/addons/`. Your per-character settings persist under `Ashita/config/addons/fancychat/<character>/` until you remove that folder too.

## See also

- [Compatibility](Compatibility.md) — what's unsupported alongside Fancychat (and the "try your luck" caveat)
- [Troubleshooting](Troubleshooting.md) — what to do if the chat plate doesn't appear
