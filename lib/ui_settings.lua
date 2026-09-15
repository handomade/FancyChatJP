-- lib/ui_settings.lua  Settings tabbed window.  Six tabs: Chat
-- Window, Font Colors, Shortcuts, Extra, CL Filters, Tools.

require('common')
local imgui     = require('imgui')
local imguiWrap = require('imguiWrap')
local utils     = require('utils')
local help      = require('help')
local state     = require('lib.state')

local fcw            = state.fcw
local tab            = state.tab
local set            = state.set
local par            = state.par
local b              = state.b
local allSettings    = state.allSettings
local defaultColors  = state.defaultColors
local colorDesc      = state.colorDesc
local gamepadButtons = state.gamepadButtons

local M = {}

-- Module-level cache of the filters/<kind>/ directory listing,
-- keyed by kind ('combat' / 'other').  Populated lazily on the first
-- frame each Filters sub-tab is drawn so the dir scan doesn't run
-- every frame.  The "Refresh" button next to each picker re-scans
-- its own kind on demand.
local cachedFilterFiles = { combat = nil, other = nil }

function M.draw_settings_panel()

	-- When the panel is closed, sync the persisted values back into
	-- the `set.*` working copy so the next open shows the current
	-- state and not stale pending edits.
	if not allSettings.settingsOpened[1] then
		set.SecondChat[1]        = allSettings.SecondChat[1]
		set.ChatLineMaxL         = allSettings.chatLineMaxL
		set.PlateBGColor         = allSettings.rectSettings.fill_color
		set.FontHeight           = allSettings.fontSettings.font_height
		set.InstantChatScroll[1] = allSettings.InstantChatScroll[1]
		set.SplitLinkshellTab[1] = allSettings.SplitLinkshellTab[1]
		for ct = 1, #allSettings.CustomTabModes do
			set.CustomTabModes[ct] = allSettings.CustomTabModes[ct]
		end
		set.ChatLines = allSettings.ChatLines
		-- Drop any pending gamepad-binding listen when the panel is
		-- closed - otherwise the user could walk away from Settings
		-- with a listen still armed and accidentally rebind an action
		-- by pressing a controller button.
		gamepadButtons.listenKey = nil
		return
	end

	ResetAutoHideTimer()
	PushWindowStyle()

	local dsize = imgui.GetIO().DisplaySize

	imgui.SetNextWindowSize({dsize.x / 3.8, dsize.y / 2.7})
	imgui.SetNextWindowSizeConstraints({550, 300}, {FLT_MAX, FLT_MAX})
	imgui.Begin('FancyChat \232\168\173\229\174\154##_'+fcw[1].PlayerName, allSettings.settingsOpened,
		bit.bor(ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse, ImGuiWindowFlags_NoNav))

	local setsizex, setsizey = imgui.GetWindowSize()

	if imgui.BeginTabBar('##fancychat_tabbar', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then

		----------------------------------------------------------------
		-- Tab: Chat Window
		----------------------------------------------------------------
		if imgui.BeginTabItem('\227\131\129\227\131\163\227\131\131\227\131\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166', nil) then
			imguiWrap.BeginChild('##Chat Window Child',
				{(setsizex * 3.8 / 3.9) - (12 * (1 - (setsizex * 3.8 / 1920))) - 3, setsizey * 2.7 / 2.8 - 60}, true)

			local fontSize = T{set.FontHeight}
			local cposY = imgui.GetCursorPosY()
			local cposX = imgui.GetCursorPosX()
			imgui.Text('\227\131\149\227\130\169\227\131\179\227\131\136\227\130\181\227\130\164\227\130\186')
			imgui.SameLine()
			imgui.SetCursorPosY(cposY - 3)
			imgui.PushItemWidth(dsize.x / 7.5)
			imgui.SetCursorPosX((dsize.x / 4.3 - dsize.x / 8) * (1920 / dsize.x))
			if imgui.SliderInt('##FontSizeSlider', fontSize, 14, 50, '%d', ImGuiSliderFlags_AlwaysClamp) then
				set.FontHeight = fontSize[1]
			end

			local lineSize = T{set.ChatLineMaxL}
			cposY = imgui.GetCursorPosY()
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosY(cposY + 10)
			imgui.Text('\227\131\129\227\131\163\227\131\131\227\131\136\229\185\133')
			imgui.SameLine()
			imgui.SetCursorPosY(cposY + 7)
			imgui.SetCursorPosX((dsize.x / 4.3 - dsize.x / 8) * (1920 / dsize.x))
			if imgui.SliderInt('##ChatWidthSlider', lineSize, 60, 135, '%d', ImGuiSliderFlags_AlwaysClamp) then
				set.ChatLineMaxL = lineSize[1]
			end

			-- Decode the persisted ARGB into a {0..1} alpha float plus
			-- a {r,g,b} float triple so two widgets can edit them
			-- independently.  Both writes flow through `recompose` at
			-- the bottom of the block so the channels they don't own
			-- are preserved.
			local plateBGcolor = set.PlateBGColor
			local plateBGAlpha = T{tonumber(bit.rshift(plateBGcolor, 24)) / 255}
			local plateBGRGB   = T{
				bit.band(bit.rshift(plateBGcolor, 16), 0xFF) / 255,
				bit.band(bit.rshift(plateBGcolor,  8), 0xFF) / 255,
				bit.band(plateBGcolor,                 0xFF) / 255,
			}
			local plateBGchanged = false

			cposY = imgui.GetCursorPosY()
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosY(cposY + 10)
			imgui.Text('\232\131\140\230\153\175\227\129\174\228\184\141\233\128\143\230\152\142\229\186\166')
			imgui.SameLine()
			imgui.SetCursorPosY(cposY + 7)
			imgui.SetCursorPosX((dsize.x / 4.3 - dsize.x / 8) * (1920 / dsize.x))
			if imgui.SliderFloat('##plateBGAlphaSlider', plateBGAlpha, 0, 1.0, '%.2f',
				bit.bor(ImGuiSliderFlags_AlwaysClamp, ImGuiSliderFlags_NoRoundToFormat)) then
				plateBGchanged = true
			end

			-- Background colour picker.  ColorButton renders just the
			-- swatch; clicking it opens our own modal-style popup that
			-- holds the full ColorPicker3 + an explicit Done button to
			-- dismiss it (Escape doesn't reliably close ImGui popups on
			-- the Ashita 4.30 binding, so click-outside or Done are the
			-- only ways out).  Alpha is handled by the slider on the
			-- row above, hence NoAlpha on both widgets.
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY + 10)
			imgui.Text('\232\131\140\230\153\175\232\137\178')
			imgui.SameLine()
			imgui.SetCursorPosY(cposY + 7)
			imgui.SetCursorPosX((dsize.x / 4.3 - dsize.x / 8) * (1920 / dsize.x))
			local swatchColor = T{plateBGRGB[1], plateBGRGB[2], plateBGRGB[3], 1.0}
			if imgui.ColorButton('##plateBGSwatch', swatchColor,
				ImGuiColorEditFlags_NoAlpha, {dsize.x / 7.5, 20}) then
				imgui.OpenPopup('##plateBGColorPopup')
			end
			if imgui.BeginPopup('##plateBGColorPopup') then
				if imgui.ColorPicker3('##plateBGColorPickerWidget', plateBGRGB,
					bit.bor(ImGuiColorEditFlags_NoLabel,
					        ImGuiColorEditFlags_NoAlpha)) then
					plateBGchanged = true
				end
				imgui.Separator()
				if imgui.Button('\231\162\186\229\174\154##plateBGColorConfirm', {-1, 0}) then
					imgui.CloseCurrentPopup()
				end
				imgui.EndPopup()
			end

			if plateBGchanged then
				set.PlateBGColor = bit.bor(
					bit.lshift(bit.tobit(plateBGAlpha[1] * 255), 24),
					bit.lshift(bit.tobit(plateBGRGB[1]   * 255), 16),
					bit.lshift(bit.tobit(plateBGRGB[2]   * 255),  8),
					bit.tobit(plateBGRGB[3] * 255))
			end

			local chatlines = T{set.ChatLines}
			cposY = imgui.GetCursorPosY()
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosY(cposY + 10)
			imgui.Text('\232\161\168\231\164\186\232\161\140\230\149\176')
			imgui.SameLine()
			imgui.SetCursorPosY(cposY + 7)
			imgui.SetCursorPosX((dsize.x / 4.3 - dsize.x / 8) * (1920 / dsize.x))
			if imgui.SliderInt('##ChatLinesSlider', chatlines, 8, 16, '%d', ImGuiSliderFlags_AlwaysClamp) then
				set.ChatLines = chatlines[1]
			end
			imgui.PopItemWidth()

			imgui.Dummy({0, 5})
			if imgui.Checkbox('\231\172\1722\227\131\129\227\131\163\227\131\131\227\131\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\130\146\230\156\137\229\138\185\227\129\171\227\129\153\227\130\139', {set.SecondChat[1]}) then
				set.SecondChat[1] = not set.SecondChat[1]
			end

			imgui.Dummy({0, 2})
			imgui.Dummy({18, 0})
			imgui.SameLine()
			if not allSettings.HideCombatFromAll2 then
				allSettings.HideCombatFromAll2 = T{false}
			end
			if imgui.Checkbox('\231\172\1722\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\174\227\128\140\229\133\168\227\129\166\227\128\141\227\129\139\227\130\137\230\136\166\233\151\152\227\130\146\233\153\164\227\129\143##HideCombatFromAll2', {allSettings.HideCombatFromAll2[1]}) then
				allSettings.HideCombatFromAll2[1] = not allSettings.HideCombatFromAll2[1]
				if allSettings.SecondChat[1] then
					RefreshAllTabBuffer(2)
				end
				SaveSettings()
			end
			AddTooltip('\231\172\1722\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\174\227\128\140\229\133\168\227\129\166\227\128\141\227\130\191\227\131\150\227\129\160\227\129\145\227\128\129\230\136\166\233\151\152\227\131\173\227\130\176\227\130\146\233\153\164\227\129\141\227\129\190\227\129\153\227\128\130\231\172\1721\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\175\230\136\166\233\151\152\227\130\191\227\131\150\227\129\174\227\129\190\227\129\190\228\189\191\227\129\136\227\129\190\227\129\153\227\128\130\229\134\141\232\181\183\229\139\149\227\129\175\228\184\141\232\166\129\227\129\167\227\129\153\227\128\130Extra \227\129\174\227\128\140\229\133\168\227\129\166\227\130\191\227\131\150\227\129\139\227\130\137\233\154\160\227\129\153\227\128\141\227\129\175\228\184\161\230\150\185\227\129\174\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\171\229\138\185\227\129\141\227\129\190\227\129\153\227\128\130', 0, true)

			imgui.Dummy({0, 5})
			imgui.Text('\227\130\171\227\130\185\227\130\191\227\131\160\227\130\191\227\131\150\227\129\171\232\161\168\231\164\186\227\129\153\227\130\139\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184')
			AddTooltip('Extra \232\168\173\229\174\154\227\129\174\227\128\140\229\133\168\227\129\166\227\130\191\227\131\150\227\129\139\227\130\137\230\136\166\233\151\152/\227\130\171\227\130\185\227\130\191\227\131\160\227\130\146\233\154\160\227\129\153\227\128\141\227\129\140\227\130\170\227\131\179\227\129\174\227\129\168\227\129\141\227\128\129\227\129\147\227\129\147\227\129\167\233\129\184\227\130\147\227\129\160\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\175\229\133\168\227\129\166\227\130\191\227\131\150\227\129\171\227\129\175\229\135\186\227\129\190\227\129\155\227\130\147\227\128\130', 0, true)
			if imgui.Checkbox('NPC',  {set.CustomTabModes[1]}) then set.CustomTabModes[1] = not set.CustomTabModes[1] end imgui.SameLine()
			cposY = imgui.GetCursorPosY()
			AddTooltip('\227\130\181\227\131\188\227\131\144\227\131\188\232\168\173\229\174\154\227\129\171\227\130\136\227\129\163\227\129\166\227\129\175\227\128\129NPC\229\143\176\232\169\158\227\130\146\229\143\150\227\130\138\227\129\147\227\129\188\227\129\151\227\129\159\227\130\138\227\128\129/say \227\130\146\230\139\190\227\129\163\227\129\166\227\129\151\227\129\190\227\129\134\227\129\147\227\129\168\227\129\140\227\129\130\227\130\138\227\129\190\227\129\153\227\128\130', 4) imgui.SameLine() imgui.SetCursorPosY(cposY)
			if imgui.Checkbox('Tell', {set.CustomTabModes[4]}) then set.CustomTabModes[4] = not set.CustomTabModes[4] end imgui.SameLine()
			if imgui.Checkbox('\227\131\145\227\131\188\227\131\134\227\130\163',{set.CustomTabModes[3]}) then set.CustomTabModes[3] = not set.CustomTabModes[3] end imgui.SameLine()
			-- Linkshell row mirrors the tab itself: with split off the
			-- user sees the single LS checkbox driving slot [2]; with
			-- split on they see independent L1 / L2 checkboxes driving
			-- slots [6] / [7].  The parser only consults the slot(s)
			-- relevant to the active split state.
			if set.SplitLinkshellTab[1] then
				if imgui.Checkbox('L1',   {set.CustomTabModes[6]}) then set.CustomTabModes[6] = not set.CustomTabModes[6] end imgui.SameLine()
				if imgui.Checkbox('L2',   {set.CustomTabModes[7]}) then set.CustomTabModes[7] = not set.CustomTabModes[7] end imgui.SameLine()
			else
				if imgui.Checkbox('LS',   {set.CustomTabModes[2]}) then set.CustomTabModes[2] = not set.CustomTabModes[2] end imgui.SameLine()
			end
			if imgui.Checkbox('\227\130\183\227\131\163\227\130\166\227\131\136',{set.CustomTabModes[5]}) then set.CustomTabModes[5] = not set.CustomTabModes[5] end

			imgui.Dummy({0, 10})
			if imgui.Checkbox('\230\150\176\231\157\128\227\130\146\229\141\179\229\186\167\227\129\171\232\161\168\231\164\186\239\188\136\227\130\185\227\130\175\227\131\173\227\131\188\227\131\171\227\130\162\227\131\139\227\131\161\227\129\170\227\129\151\239\188\137##InstantChatScroll', {set.InstantChatScroll[1]}) then
				set.InstantChatScroll[1] = not set.InstantChatScroll[1]
			end
			AddTooltip('\227\130\170\227\131\179\227\129\171\227\129\153\227\130\139\227\129\168\227\128\129\230\150\176\231\157\128\232\161\140\227\129\140\228\184\139\227\129\139\227\130\137\230\187\145\227\130\137\227\129\154\227\129\153\227\129\144\227\129\171\232\161\168\231\164\186\227\129\149\227\130\140\227\129\190\227\129\153\227\128\130\230\136\166\233\151\152\227\131\173\227\130\176\227\129\140\229\191\153\227\129\151\227\129\132\227\129\168\227\129\141\227\130\132\228\189\142FPS\229\144\145\227\129\145\227\128\130\227\130\162\227\131\137\227\130\170\227\131\179\229\134\141\232\181\183\229\139\149\229\190\140\227\129\171\229\143\141\230\152\160\227\129\149\227\130\140\227\129\190\227\129\153\227\128\130', 4)

			imgui.Dummy({0, 5})
			if imgui.Checkbox('\227\131\170\227\131\179\227\130\175\227\130\183\227\130\167\227\131\171\227\130\191\227\131\150\227\130\146 L1 / L2 \227\129\171\229\136\134\229\137\178##SplitLinkshellTab', {set.SplitLinkshellTab[1]}) then
				set.SplitLinkshellTab[1] = not set.SplitLinkshellTab[1]
				-- Migrate the Custom-tab LS membership across the
				-- split / no-split transition so the checkboxes the
				-- user is about to see reflect a sensible default:
				--   OFF -> ON : LS=true expands into both L1+L2; LS
				--               slot is cleared.
				--   ON  -> OFF: both L1+L2 collapse into LS=true; if
				--               only one (or neither) was on, LS
				--               defaults to false per spec.  L1/L2
				--               slots are cleared either way.
				if set.SplitLinkshellTab[1] then
					if set.CustomTabModes[2] then
						set.CustomTabModes[6] = true
						set.CustomTabModes[7] = true
					else
						set.CustomTabModes[6] = false
						set.CustomTabModes[7] = false
					end
					set.CustomTabModes[2] = false
				else
					if set.CustomTabModes[6] and set.CustomTabModes[7] then
						set.CustomTabModes[2] = true
					else
						set.CustomTabModes[2] = false
					end
					set.CustomTabModes[6] = false
					set.CustomTabModes[7] = false
				end
			end
			AddTooltip('\227\130\170\227\131\179\227\129\171\227\129\153\227\130\139\227\129\168\227\128\129\227\131\170\227\131\179\227\130\175\227\130\183\227\130\167\227\131\171\227\130\191\227\131\150\227\129\140 L1 / L2 \227\129\1742\227\129\164\227\129\171\229\136\134\227\129\139\227\130\140\227\129\190\227\129\153\227\128\130LS1 \227\129\175 L1\227\128\129LS2 \227\129\175 L2 \227\129\184\230\140\175\227\130\138\229\136\134\227\129\145\227\130\137\227\130\140\227\129\190\227\129\153\227\128\130\229\144\132\227\131\129\227\131\163\227\131\131\227\131\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\167\231\139\172\231\171\139\227\129\151\227\129\166\233\129\184\227\129\185\227\129\190\227\129\153\227\128\130\227\130\162\227\131\137\227\130\170\227\131\179\229\134\141\232\181\183\229\139\149\229\190\140\227\129\171\229\143\141\230\152\160\227\129\149\227\130\140\227\129\190\227\129\153\227\128\130', 4)

			imgui.Dummy({0, 5})
			if imgui.Button('\229\136\157\230\156\159\229\128\164\227\129\171\230\136\187\227\129\153') then
				set.ChatLineMaxL         = 100
				set.PlateBGColor         = bit.lshift(bit.tobit(0.3 * 255), 24)
				set.FontHeight           = 20
				set.ChatLines            = 8
				set.SecondChat[1]        = false
				set.InstantChatScroll[1] = false
				set.SplitLinkshellTab[1] = false
				set.CustomTabModes       = T{false, false, false, false, false, false, false}
			end

			imgui.Dummy({0, 5})
			imgui.TextColored({1.0, 0.2, 0.2, 1.0}, '^')
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY - 20)

			imgui.TextColored({1.0, 0.2, 0.2, 1.0}, '|')
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY - 20)
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosX(cposX + 15)
			imgui.TextColored({1.0, 0.2, 0.2, 1.0}, '\228\184\138\232\168\152\227\129\174\229\164\137\230\155\180\227\129\175\227\130\162\227\131\137\227\130\170\227\131\179\229\134\141\232\181\183\229\139\149\229\190\140\227\129\171\229\143\141\230\152\160\227\129\149\227\130\140\227\129\190\227\129\153')
			AddTooltip('\228\184\138\227\129\174\233\160\133\231\155\174\227\129\175\227\130\162\227\131\137\227\130\170\227\131\179\227\130\146\229\134\141\232\181\183\229\139\149\227\129\153\227\130\139\227\129\190\227\129\167\229\143\141\230\152\160\227\129\149\227\130\140\227\129\190\227\129\155\227\130\147', 1, 1)
			if imgui.Button('\229\134\141\232\181\183\229\139\149\227\129\151\227\129\166\233\129\169\231\148\168') then
				fcw[1].Closing = true
				if not set.SecondChat[1] then
					allSettings.GuideMeSecondWindow[1] = false
				end
				allSettings.SecondChat[1]            = set.SecondChat[1]
				allSettings.ChatLines                = set.ChatLines
				allSettings.fontSettings.font_height = set.FontHeight
				allSettings.rectSettings.fill_color  = set.PlateBGColor
				allSettings.chatLineMaxL             = set.ChatLineMaxL
				allSettings.InstantChatScroll[1]     = set.InstantChatScroll[1]
				allSettings.SplitLinkshellTab[1]     = set.SplitLinkshellTab[1]
				for ct = 1, #set.CustomTabModes do
					allSettings.CustomTabModes[ct] = set.CustomTabModes[ct]
				end
				SaveSettings()
				AshitaCore:GetChatManager():QueueCommand(1, '/addon reload fancychat')
			end

			imgui.Dummy({0, 20})
			imgui.Text('\229\133\168\232\167\146\227\129\174\229\185\133\239\188\136\229\141\138\232\167\146\230\175\148\239\188\137')
			AddTooltip('\229\133\168\232\167\146\239\188\136\230\188\162\229\173\151\227\131\187\227\129\139\227\129\170\239\188\1371\230\150\135\229\173\151\227\129\140\227\128\129\229\141\138\232\167\146\228\189\149\230\150\135\229\173\151\229\136\134\227\129\168\227\129\151\227\129\166\230\138\152\227\130\138\232\191\148\227\129\149\227\130\140\227\130\139\227\129\139\227\129\167\227\129\153\227\128\130Meiryo \227\129\175\227\129\138\227\129\138\227\130\136\227\129\157 1.70\227\128\129MS Gothic \227\129\175 2.00\227\128\130\230\150\176\227\129\151\227\129\132\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\139\227\130\137\227\129\153\227\129\144\229\143\141\230\152\160\227\129\149\227\130\140\227\129\190\227\129\153\239\188\136\229\134\141\232\181\183\229\139\149\228\184\141\232\166\129\239\188\137\227\128\130\231\171\175\227\130\136\227\130\138\230\151\169\227\129\143\230\138\152\227\130\140\227\130\139\227\129\170\227\130\137\228\184\139\227\129\146\227\128\129\227\129\175\227\129\191\229\135\186\227\129\153\227\129\170\227\130\137\228\184\138\227\129\146\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130', 0, true)
			local cjkRatio = T{allSettings.cjkWidthRatio or 1.70}
			imgui.PushItemWidth(dsize.x / 7.5)
			if imgui.SliderFloat('##CjkWidthRatioSlider', cjkRatio, 1.50, 2.00, '%.2f',
				bit.bor(ImGuiSliderFlags_AlwaysClamp, ImGuiSliderFlags_NoRoundToFormat)) then
				allSettings.cjkWidthRatio = cjkRatio[1]
				SaveSettings()
			end
			imgui.PopItemWidth()
			imgui.SameLine()
			if imgui.Button('1.70##CjkWidthRatioMeiryo') then
				allSettings.cjkWidthRatio = 1.70
				SaveSettings()
			end
			imgui.SameLine()
			if imgui.Button('2.00##CjkWidthRatioGothic') then
				allSettings.cjkWidthRatio = 2.00
				SaveSettings()
			end

			imgui.Dummy({0, 35})
			imgui.Text('\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\228\189\141\231\189\174\227\129\174\229\190\174\232\170\191\230\149\180')
			AddTooltip('\230\137\139\229\139\149\227\129\167\229\139\149\227\129\139\227\129\151\227\129\159\227\129\130\227\129\168\227\129\171\227\128\1291\227\131\148\227\130\175\227\130\187\227\131\171\229\141\152\228\189\141\227\129\167\228\189\141\231\189\174\227\130\146\229\144\136\227\130\143\227\129\155\227\130\139\227\129\159\227\130\129\227\129\174\230\147\141\228\189\156\227\129\167\227\129\153', 0)
			imgui.Dummy({0, 25})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('1##Window1', {set.AdjWin1[1]}) then set.AdjWin1[1] = not set.AdjWin1[1] end imgui.SameLine() imgui.Dummy({2, 0}) imgui.SameLine()
			if imgui.Checkbox('2##Window2', {set.AdjWin2[1]}) then set.AdjWin2[1] = not set.AdjWin2[1] end

			imgui.SameLine() imgui.Dummy({10, 0}) imgui.SameLine()

			if imgui.ArrowButton('#AnchorL', ImGuiDir_Left) then
				if set.AdjWin1[1] then allSettings.WindowPosOffset[1] = allSettings.WindowPosOffset[1] - 1 end
				if set.AdjWin2[1] then allSettings.WindowPosOffset[3] = allSettings.WindowPosOffset[3] - 1 end
				fcw[1].PositionLinesRequest = {true, true}
				fcw[2].PositionLinesRequest = {true, true}
			end
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY - 51)
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosX(cposX + 154)
			if imgui.ArrowButton('#AnchorU', ImGuiDir_Up) then
				if set.AdjWin1[1] then allSettings.WindowPosOffset[2] = allSettings.WindowPosOffset[2] - 1 end
				if set.AdjWin2[1] then allSettings.WindowPosOffset[4] = allSettings.WindowPosOffset[4] - 1 end
				fcw[1].PositionLinesRequest = {true, true}
				fcw[2].PositionLinesRequest = {true, true}
			end
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY - 1)
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosX(cposX + 161)
			imgui.Text('+')
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY - 3)
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosX(cposX + 154)
			if imgui.ArrowButton('#AnchorD', ImGuiDir_Down) then
				if set.AdjWin1[1] then allSettings.WindowPosOffset[2] = allSettings.WindowPosOffset[2] + 1 end
				if set.AdjWin2[1] then allSettings.WindowPosOffset[4] = allSettings.WindowPosOffset[4] + 1 end
				fcw[1].PositionLinesRequest = {true, true}
				fcw[2].PositionLinesRequest = {true, true}
			end
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY - 51)
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosX(cposX + 177)
			if imgui.ArrowButton('#AnchorR', ImGuiDir_Right) then
				if set.AdjWin1[1] then allSettings.WindowPosOffset[1] = allSettings.WindowPosOffset[1] + 1 end
				if set.AdjWin2[1] then allSettings.WindowPosOffset[3] = allSettings.WindowPosOffset[3] + 1 end
				fcw[1].PositionLinesRequest = {true, true}
				fcw[2].PositionLinesRequest = {true, true}
			end
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY - 53)
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosX(cposX + 230)
			imgui.Text('W1 [x:'..tostring(allSettings.WindowPosOffset[1])..', y:'..tostring(allSettings.WindowPosOffset[2])..']\nW2 [x:'..tostring(allSettings.WindowPosOffset[3])..', y:'..tostring(allSettings.WindowPosOffset[4])..']')
			cposX = imgui.GetCursorPosX()
			imgui.SetCursorPosX(cposX + 230)
			if imgui.Button('\228\191\157\229\173\152##Offsets') then SaveSettings() end imgui.SameLine()
			if imgui.Button('\227\131\170\227\130\187\227\131\131\227\131\136##Offsets') then allSettings.WindowPosOffset = {0, 0, 0, 0} end

			imgui.Dummy({0, 20})
			if imgui.Checkbox('\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\228\189\141\231\189\174\227\130\146\229\155\186\229\174\154\239\188\136\227\131\137\227\131\169\227\131\131\227\130\176\231\132\161\229\138\185\239\188\137##WindowLock', {allSettings.LockWindowPos[1]}) then
				allSettings.LockWindowPos[1] = not allSettings.LockWindowPos[1]
				SaveSettings()
			end
			imgui.Dummy({0, 5})
			if imgui.Checkbox('\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\130\146\233\150\139\227\129\132\227\129\166\227\130\130 FancyChat \227\130\146\232\161\168\231\164\186\227\129\151\227\129\159\227\129\190\227\129\190##ShowWithLegacy', {allSettings.ShowWithLegacy[1]}) then
				allSettings.ShowWithLegacy[1] = not allSettings.ShowWithLegacy[1]
				SaveSettings()
			end
			AddTooltip('\227\130\170\227\131\149\239\188\136\229\136\157\230\156\159\229\128\164\239\188\137\227\129\167\227\129\175\227\128\129\229\190\147\230\157\165\227\129\174FFXI\227\131\129\227\131\163\227\131\131\227\131\136\227\130\146\227\130\175\227\131\170\227\131\131\227\130\175\227\129\151\227\129\159\227\130\138\229\133\165\229\138\155\227\130\146\233\150\139\227\129\132\227\129\159\231\158\172\233\150\147\227\129\171 FancyChat \227\129\140\233\154\160\227\130\140\227\129\190\227\129\153\227\128\130\227\130\170\227\131\179\227\129\171\227\129\153\227\130\139\227\129\168\228\184\161\230\150\185\228\184\166\227\130\147\227\129\167\232\161\168\231\164\186\227\129\149\227\130\140\227\129\190\227\129\153\227\128\130', 4)
			imgui.Dummy({0, 5})
			if imgui.Checkbox('1\231\149\170\231\155\174\227\129\174\227\131\129\227\131\163\227\131\131\227\131\136\227\129\171\227\131\152\227\131\171\227\131\151 (?) \227\131\156\227\130\191\227\131\179\227\130\146\232\161\168\231\164\186##HelpButton', {allSettings.HelpButton[1]}) then
				allSettings.HelpButton[1] = not allSettings.HelpButton[1]
				SaveSettings()
			end
			AddTooltip('1\231\149\170\231\155\174\227\129\174\227\131\129\227\131\163\227\131\131\227\131\136\229\183\166\228\184\138\227\129\174 (?) \227\130\162\227\130\164\227\130\179\227\131\179\227\129\174\232\161\168\231\164\186\227\130\146\229\136\135\227\130\138\230\155\191\227\129\136\227\129\190\227\129\153\227\128\130\227\131\155\227\131\144\227\131\188\227\129\167\227\131\158\227\130\166\227\130\185 / \227\130\173\227\131\188\227\131\156\227\131\188\227\131\137\230\147\141\228\189\156\227\129\174\231\176\161\230\152\147\228\184\128\232\166\167\227\129\140\229\135\186\227\129\190\227\129\153\227\128\130', 4)
			imgui.Dummy({0, 5})
			if imgui.Checkbox('\227\130\191\227\131\150\227\130\146\229\183\166\228\184\139\227\129\171\227\130\179\227\131\179\227\131\145\227\130\175\227\131\136\233\133\141\231\189\174##ComapctBL', {allSettings.CompactTabsBL[1]}) then
				allSettings.CompactTabsBL[1] = not allSettings.CompactTabsBL[1]
				SaveSettings()
			end
			imgui.Dummy({0, 5})
			if imgui.Checkbox('\232\135\170\229\139\149\227\129\167\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\130\146\233\154\160\227\129\153', {allSettings.AutoHideWindow[1]}) then
				allSettings.AutoHideWindow[1] = not allSettings.AutoHideWindow[1]
				SaveSettings()
			end
			imgui.PushItemWidth(dsize.x / 10)
			cposY = imgui.GetCursorPosY()
			cposX = imgui.GetCursorPosX()
			imgui.Dummy({3, 0}) imgui.SameLine() imgui.Text('L')
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 18)
			imgui.Dummy({20, 0}) imgui.SameLine()
			imgui.Text('\232\135\170\229\139\149\233\157\158\232\161\168\231\164\186\227\129\190\227\129\167\227\129\174\231\167\146\230\149\176 >')
			imgui.SameLine()
			imgui.SetCursorPosY(cposY + 0.5)
			imgui.SetCursorPosX((dsize.x / 3.7 - dsize.x / 8) * (1920 / dsize.x))
			local ahtime = {allSettings.AutoHideTimeMax}
			if imgui.SliderInt('##AutoHideSlider', ahtime, 5, 60, '%d', ImGuiSliderFlags_AlwaysClamp) then
				allSettings.AutoHideTimeMax = ahtime[1]
				SaveSettings()
			end
			imgui.PopItemWidth()
			imgui.Dummy({0, 5})
			if imgui.Checkbox('\227\131\137\227\131\131\227\130\173\227\131\179\227\130\176UI\227\129\174\229\185\133\227\130\146\227\131\129\227\131\163\227\131\131\227\131\136\227\129\174\229\141\138\229\136\134\227\129\171\227\129\153\227\130\139', {allSettings.UseHalfLength[1]}) then
				allSettings.UseHalfLength[1] = not allSettings.UseHalfLength[1]
				SaveSettings()
			end
			AddTooltip('GuideMe / \227\131\161\227\131\162\229\184\179\227\129\170\227\129\169\227\128\129\227\131\129\227\131\163\227\131\131\227\131\136\227\129\171\227\131\137\227\131\131\227\130\173\227\131\179\227\130\176\227\129\153\227\130\139UI\227\129\174\229\185\133\227\130\146\227\128\129\227\131\129\227\131\163\227\131\131\227\131\136\229\185\133\227\129\174\229\141\138\229\136\134\227\129\171\227\129\151\227\129\190\227\129\153\227\128\130', 4)
			imgui.Dummy({0, 5})
			if imgui.Checkbox('FFXI\227\129\174UI\227\129\168\233\135\141\227\129\170\227\130\137\227\129\170\227\129\132\227\130\136\227\129\134\227\129\171\227\129\154\227\130\137\227\129\153', {allSettings.EnabledChatMove[1]}) then
				allSettings.EnabledChatMove[1] = not allSettings.EnabledChatMove[1]
				SaveSettings()
			end
			imgui.Dummy({1, 0}) imgui.SameLine() imgui.Text('|  2\231\149\170\231\155\174\227\129\174\227\131\129\227\131\163\227\131\131\227\131\136\227\129\174\229\139\149\228\189\156')
			local csmodes = {{'Nothing', 1, '\228\189\149\227\130\130\227\129\151\227\129\170\227\129\132'}, {'Hide 2nd', 2, '2\231\149\170\231\155\174\227\130\146\233\154\160\227\129\153'}, {'Shift along', 3, '\228\184\128\231\183\146\227\129\171\227\129\154\227\130\137\227\129\153'}}
			local cs_preview = allSettings.CSMode[1]
			for CS_i = 1, #csmodes do
				if csmodes[CS_i][2] == allSettings.CSMode[2] or csmodes[CS_i][1] == allSettings.CSMode[1] then
					cs_preview = csmodes[CS_i][3]
					break
				end
			end
			imgui.Dummy({1, 0}) imgui.SameLine() imgui.SetCursorPosY(imgui.GetCursorPosY() + 4) imgui.Text('| ') imgui.SetCursorPosY(imgui.GetCursorPosY() - 4) imgui.SameLine()
			if imgui.BeginCombo('##ChatShiftMode', cs_preview, ImGuiComboFlags_None) then
				for CS_i = 1, #csmodes do
					if imgui.Selectable(csmodes[CS_i][3]) then
						allSettings.CSMode = {csmodes[CS_i][1], csmodes[CS_i][2]}
						SaveSettings()
					end
				end
				imgui.EndCombo()
			end
			imgui.Dummy({1, 0}) imgui.SameLine() imgui.Text('| ') imgui.SameLine()
			if imgui.Checkbox('\227\130\170\227\131\188\227\131\136\227\131\136\227\131\169\227\131\179\227\130\185\227\131\172\227\131\188\227\131\136\227\131\161\227\131\139\227\131\165\227\131\188\227\129\168\227\130\130\233\135\141\227\129\170\227\130\137\227\129\170\227\129\132\227\130\136\227\129\134\227\129\171\227\129\153\227\130\139', {allSettings.MoveChatATMenu[1]}) then
				allSettings.MoveChatATMenu[1] = not allSettings.MoveChatATMenu[1]
				SaveSettings()
			end
			imgui.Dummy({3, 0}) imgui.SameLine() imgui.Text('L')
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 18)
			imgui.Dummy({27, 0}) imgui.SameLine()
			imgui.Text('[ \229\174\159\233\168\147\231\154\132 ]\n[ FFXI\227\129\174UI\227\129\168\233\135\141\227\129\170\227\129\163\227\129\159\227\130\137\227\131\129\227\131\163\227\131\131\227\131\136\228\189\141\231\189\174\227\130\146\227\129\154\227\130\137\227\129\151\227\129\190\227\129\153 ]\n[ \227\130\136\227\129\143\228\189\191\227\129\134\227\130\178\227\131\188\227\131\160UI\227\129\171\229\175\190\229\191\156 ]\n[ \227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\228\189\141\231\189\174\227\129\174\229\155\186\229\174\154\227\129\140\227\130\170\227\131\179\227\129\174\227\129\168\227\129\141\227\129\174\227\129\191\229\139\149\228\189\156 ]')

			imgui.EndChild()
			imgui.EndTabItem()
		end

		----------------------------------------------------------------
		-- Tab: Font Colors
		----------------------------------------------------------------
		if imgui.BeginTabItem('\227\131\149\227\130\169\227\131\179\227\131\136\232\137\178', nil) then
			imguiWrap.BeginChild('leftpane',
				{((setsizex * 3.8 / 3.9) - (12 * (1 - (setsizex * 3.8 / 1920))) - 3) * set.colorTextW, setsizey * 2.7 / 3 - 60}, true)

			local keys = {}
			local tmpcolor = {}
			for key in pairs(allSettings.colors) do
				table.insert(keys, key)
			end
			-- Sort by the human-readable label from colorDesc (the [1]
			-- field of each entry in defaults.color_descriptions) so the
			-- left-pane row order matches what the user actually reads,
			-- not the underlying internal key.  Falls back to the raw key
			-- if a color slot is missing a description entry.
			table.sort(keys, function(a, b)
				local la = colorDesc[a] and colorDesc[a][1] or a
				local lb = colorDesc[b] and colorDesc[b][1] or b
				return la < lb
			end)
			local skip = {'combat', 'combatspell', 'cexi'}
			set.colorTextW = 0
			for _, key in ipairs(keys) do
				if not utils.FindInStringTable(key, skip, 0) then
					set.colorTextW = math.max(AddSetColor(key, allSettings.colors[key], tmpcolor), set.colorTextW)
				end
			end
			set.colorTextW = set.colorTextW / (setsizex - ((12 * (1 - (setsizex * 3.8 / 1920))) - 3 * 2))

			imgui.EndChild()

			imgui.SameLine()

			imguiWrap.BeginChild('righttpane',
				{((setsizex * 3.8 / 3.9) - (12 * (1 - (setsizex * 3.8 / 1920))) - 3) * (1 - (set.colorTextW + 0.01)), setsizey * 2.7 / 3 - 60}, true)

			imgui.Text('\227\130\171\227\131\169\227\131\188\227\131\148\227\131\131\227\130\171\227\131\188')
			imgui.Separator()
			imgui.TextWrapped('\232\137\178\227\130\146\233\129\184\227\130\147\227\129\167\227\128\129\229\183\166\227\131\154\227\130\164\227\131\179\227\129\174\231\159\162\229\141\176\227\131\156\227\130\191\227\131\179\227\129\167\229\137\178\227\130\138\229\189\147\227\129\166\227\129\190\227\129\153\227\128\130')
			if tmpcolor[1] then set.PickedColor = utils.cloneTable(tmpcolor[1]) end
			imgui.PushItemWidth(dsize.x / (set.colorTextW * 25))
			imgui.ColorPicker3('\227\131\151\227\131\172\227\131\147\227\131\165\227\131\188', set.PickedColor)
			imgui.PopItemWidth()
			imgui.EndChild()

			if imgui.Button('\232\137\178\227\130\146\227\131\170\227\130\187\227\131\131\227\131\136') then
				allSettings.colors = utils.cloneTable(defaultColors)
				SaveSettings()
			end
			imgui.SameLine()
			if imgui.Button('\232\137\178\227\130\146\230\155\184\227\129\141\229\135\186\227\129\151') then
				-- Mutex: opening Export closes Import.
				set.colorIO.importOpen      = false
				-- (Re-)open: hard-regenerate the suggested filename.
				set.colorIO.exportOpen      = true
				set.colorIO.exportName[1]   = utils.NextColorsetName(addon.path, fcw[1].PlayerName)
			end
			imgui.SameLine()
			if imgui.Button('\232\137\178\227\130\146\232\170\173\227\129\191\232\190\188\227\129\191') then
				set.colorIO.exportOpen      = false
				set.colorIO.importOpen      = true
				set.colorIO.importFiles     = utils.ListColorsetFiles(addon.path)
				set.colorIO.importSelected  = 0
			end
			imgui.SameLine()
			AddTooltip('\227\131\149\227\130\161\227\130\164\227\131\171\227\129\175\231\155\180\230\142\165\231\183\168\233\155\134\227\129\151\227\129\170\227\129\132\227\129\167\227\129\143\227\129\160\227\129\149\227\129\132\239\188\129', 3, true)
			imgui.EndTabItem()
		end

		----------------------------------------------------------------
		-- Tab: Shortcuts
		----------------------------------------------------------------
		if imgui.BeginTabItem('\227\130\183\227\131\167\227\131\188\227\131\136\227\130\171\227\131\131\227\131\136', nil) then
			imguiWrap.BeginChild('##Shortcuts Child',
				{(setsizex * 3.8 / 3.9) - (12 * (1 - (setsizex * 3.8 / 1920))) - 3, setsizey * 2.7 / 2.8 - 60}, true)

			local letter   = utils.keycodes       [utils.findIndexOfValue(utils.keycodes,        allSettings.shortcutHide ) ][1]
			local letterS  = utils.keycodesSpecial[utils.findIndexOfValue(utils.keycodesSpecial, allSettings.shortcutHideS) ][1]
			local letter2  = utils.keycodes       [utils.findIndexOfValue(utils.keycodes,        allSettings.shortcutTab  ) ][1]
			local letterS2 = utils.keycodesSpecial[utils.findIndexOfValue(utils.keycodesSpecial, allSettings.shortcutTabS ) ][1]
			local letter3  = utils.keycodes       [utils.findIndexOfValue(utils.keycodes,        allSettings.shortcutTab2 ) ][1]
			local letterS3 = utils.keycodesSpecial[utils.findIndexOfValue(utils.keycodesSpecial, allSettings.shortcutTab2S) ][1]
			local letter4  = utils.keycodes       [utils.findIndexOfValue(utils.keycodes,        allSettings.shortcutBig  ) ][1]
			local letterS4 = utils.keycodesSpecial[utils.findIndexOfValue(utils.keycodesSpecial, allSettings.shortcutBigS ) ][1]

			-- Hide shortcut
			imgui.Text('FancyChat \227\130\146\228\184\128\230\153\130\231\154\132\227\129\171\233\154\160\227\129\153')
			AddTooltip('FancyChat \227\130\146\228\184\128\230\153\130\231\154\132\227\129\171\233\154\160\227\129\151\227\128\129\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\130\146\229\134\141\232\161\168\231\164\186\227\129\151\227\129\190\227\129\153\227\128\130', 0)
			local cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY + 5)
			if imgui.Checkbox('\230\156\137\229\138\185##HideShortcut', {allSettings.shortcutHideEnabled[1]}) then
				allSettings.shortcutHideEnabled[1] = not allSettings.shortcutHideEnabled[1]
				SaveSettings()
			end
			imgui.PushItemWidth(dsize.x / 15)
			if imgui.BeginCombo('##HideShortcutComboS', letterS, ImGuiComboFlags_None) then
				for KC_i = 1, #utils.keycodesSpecial do
					if imgui.Selectable(utils.keycodesSpecial[KC_i][1], letterS == utils.keycodesSpecial[KC_i][1]) then
						allSettings.shortcutHideS = utils.keycodesSpecial[KC_i][2]
						SaveSettings()
					end
				end
				imgui.EndCombo()
			end
			imgui.SameLine()
			if imgui.BeginCombo('##HideShortcutCombo', letter, ImGuiComboFlags_None) then
				for KC_i = 1, #utils.keycodes do
					if utils.keycodes[KC_i][1] ~= letter2 and utils.keycodes[KC_i][1] ~= letter3 and utils.keycodes[KC_i][1] ~= letter4 then
						if imgui.Selectable(utils.keycodes[KC_i][1], letter == utils.keycodes[KC_i][1]) then
							allSettings.shortcutHide = utils.keycodes[KC_i][2]
							SaveSettings()
						end
					end
				end
				imgui.EndCombo()
			end
			imgui.PopItemWidth()

			imgui.Dummy({0, 20})

			-- BigMode shortcut
			imgui.Text('\227\131\147\227\131\131\227\130\176\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\131\162\227\131\188\227\131\137')
			AddTooltip('1\231\149\170\231\155\174\227\129\174\227\131\129\227\131\163\227\131\131\227\131\136\227\130\146 Big Mode \227\129\167\232\161\168\231\164\186\227\129\151\227\129\190\227\129\153\227\128\130', 0)
			if imgui.Checkbox('\230\156\137\229\138\185##BigShortcut', {allSettings.shortcutBigEnabled[1]}) then
				allSettings.shortcutBigEnabled[1] = not allSettings.shortcutBigEnabled[1]
				SaveSettings()
			end
			imgui.PushItemWidth(dsize.x / 15)
			if imgui.BeginCombo('##BigShortcutComboS', letterS4, ImGuiComboFlags_None) then
				for KC_i = 1, #utils.keycodesSpecial do
					if imgui.Selectable(utils.keycodesSpecial[KC_i][1], letterS4 == utils.keycodesSpecial[KC_i][1]) then
						allSettings.shortcutBigS = utils.keycodesSpecial[KC_i][2]
						SaveSettings()
					end
				end
				imgui.EndCombo()
			end
			imgui.SameLine()
			if imgui.BeginCombo('##BigShortcutCombo', letter4, ImGuiComboFlags_None) then
				for KC_i = 1, #utils.keycodes do
					if utils.keycodes[KC_i][1] ~= letter and utils.keycodes[KC_i][1] ~= letter2 and utils.keycodes[KC_i][1] ~= letter3 then
						if imgui.Selectable(utils.keycodes[KC_i][1], letter4 == utils.keycodes[KC_i][1]) then
							allSettings.shortcutBig = utils.keycodes[KC_i][2]
							SaveSettings()
						end
					end
				end
				imgui.EndCombo()
			end
			imgui.PopItemWidth()

			imgui.Dummy({0, 20})

			-- Tab cycle (window 1) shortcut
			imgui.Text('\227\131\129\227\131\163\227\131\131\227\131\136\227\130\191\227\131\150\227\130\146\229\136\135\227\130\138\230\155\191\227\129\136\239\188\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\1661\239\188\137')
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY + 5)
			if imgui.Checkbox('\230\156\137\229\138\185##TabShortcut', {allSettings.shortcutTabEnabled[1]}) then
				allSettings.shortcutTabEnabled[1] = not allSettings.shortcutTabEnabled[1]
				SaveSettings()
			end
			imgui.PushItemWidth(dsize.x / 15)
			if imgui.BeginCombo('##TabShortcutComboS', letterS2, ImGuiComboFlags_None) then
				for KC_i = 1, #utils.keycodesSpecial do
					if imgui.Selectable(utils.keycodesSpecial[KC_i][1], letterS2 == utils.keycodesSpecial[KC_i][1]) then
						allSettings.shortcutTabS = utils.keycodesSpecial[KC_i][2]
						SaveSettings()
					end
				end
				imgui.EndCombo()
			end
			imgui.SameLine()
			if imgui.BeginCombo('##TabShortcutCombo', letter2, ImGuiComboFlags_None) then
				for KC_i = 1, #utils.keycodes do
					if utils.keycodes[KC_i][1] ~= letter and utils.keycodes[KC_i][1] ~= letter3 and utils.keycodes[KC_i][1] ~= letter4 then
						if imgui.Selectable(utils.keycodes[KC_i][1], letter2 == utils.keycodes[KC_i][1]) then
							allSettings.shortcutTab = utils.keycodes[KC_i][2]
							SaveSettings()
						end
					end
				end
				imgui.EndCombo()
			end
			imgui.PopItemWidth()

			imgui.Dummy({0, 20})

			-- Tab cycle (window 2) shortcut
			imgui.Text('\227\131\129\227\131\163\227\131\131\227\131\136\227\130\191\227\131\150\227\130\146\229\136\135\227\130\138\230\155\191\227\129\136\239\188\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\1662\239\188\137')
			cposY = imgui.GetCursorPosY()
			imgui.SetCursorPosY(cposY + 5)
			if imgui.Checkbox('\230\156\137\229\138\185##Tab2Shortcut', {allSettings.shortcutTab2Enabled[1]}) then
				allSettings.shortcutTab2Enabled[1] = not allSettings.shortcutTab2Enabled[1]
				SaveSettings()
			end
			imgui.PushItemWidth(dsize.x / 15)
			if imgui.BeginCombo('##Tab2ShortcutComboS', letterS3, ImGuiComboFlags_None) then
				for KC_i = 1, #utils.keycodesSpecial do
					if imgui.Selectable(utils.keycodesSpecial[KC_i][1], letterS3 == utils.keycodesSpecial[KC_i][1]) then
						allSettings.shortcutTab2S = utils.keycodesSpecial[KC_i][2]
						SaveSettings()
					end
				end
				imgui.EndCombo()
			end
			imgui.SameLine()
			if imgui.BeginCombo('##TabShortcutCombo2', letter3, ImGuiComboFlags_None) then
				for KC_i = 1, #utils.keycodes do
					if utils.keycodes[KC_i][1] ~= letter and utils.keycodes[KC_i][1] ~= letter2 and utils.keycodes[KC_i][1] ~= letter4 then
						if imgui.Selectable(utils.keycodes[KC_i][1], letter2 == utils.keycodes[KC_i][1]) then
							allSettings.shortcutTab2 = utils.keycodes[KC_i][2]
							SaveSettings()
						end
					end
				end
				imgui.EndCombo()
			end
			imgui.PopItemWidth()

			imgui.Dummy({0, 10})
			if imgui.Button('\227\130\173\227\131\188\229\137\178\227\130\138\229\189\147\227\129\166\227\130\146\229\136\157\230\156\159\229\140\150') then
				allSettings.shortcutHide  = 46
				allSettings.shortcutTab   = 45
				allSettings.shortcutTab2  = 48
				allSettings.shortcutBig   = 34
				allSettings.shortcutHideS = 42
				allSettings.shortcutTabS  = 42
				allSettings.shortcutTab2S = 42
				allSettings.shortcutBigS  = 42
			end

			-- Inline command reference
			imgui.Dummy({0, 20})
			imgui.Text('\227\131\158\227\130\175\227\131\173\231\148\168\227\130\179\227\131\158\227\131\179\227\131\137')
			local cmds = {
				{'/fancychat settings', '[\232\168\173\229\174\154\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\130\146\233\150\139\233\150\137]'},
				{'/fancychat guideme',  '[GuideMe \227\130\146\233\150\139\233\150\137]'},
				{'/fancychat notes',    '[\227\131\161\227\131\162\229\184\179\227\130\146\233\150\139\233\150\137]'},
				{'/fancychat ffo',      '[\231\148\168\232\170\158\232\190\158\229\133\184\227\130\146\230\164\156\231\180\162]'},
				{'/fancychat compact',  '[\227\130\191\227\131\150\227\129\174\227\130\179\227\131\179\227\131\145\227\130\175\227\131\136\232\161\168\231\164\186\227\130\146\229\136\135\230\155\191]'},
				{'/fancychat manual',   '[\227\131\158\227\131\139\227\131\165\227\130\162\227\131\171\227\130\146\233\150\139\227\129\143]'},
				{'/fancychat bigmode',  '[BigMode \227\130\170\227\131\188\227\131\144\227\131\188\227\131\172\227\130\164\227\130\146\229\136\135\230\155\191]'},
				{'/fancychat tod',      '[\231\178\190\229\175\134TOD\227\130\191\227\130\164\227\131\160\227\130\185\227\130\191\227\131\179\227\131\151\227\130\146\229\136\135\230\155\191]'},
				{'/fancychat ts',       '[\231\143\190\229\156\168\230\153\130\229\136\187\227\130\146\232\161\168\231\164\186]'},
				{'/fancychat savelogs', '[\227\131\129\227\131\163\227\131\131\227\131\136\227\131\173\227\130\176\227\130\146\228\191\157\229\173\152]'},
			}
			for _, c in ipairs(cmds) do
				imgui.Dummy({0, 5}) imgui.Dummy({3, 0}) imgui.SameLine()
				imgui.Text(c[1])
				imgui.Dummy({23, 0}) imgui.SameLine()
				imgui.Text(c[2])
			end

			-- Built-in (non-configurable) mouse + keyboard interactions
			-- baked into the chat windows.  Distinct from the
			-- configurable shortcuts above  these are hard-coded
			-- behaviors users may not know exist.  Same [Name]\n* keys
			-- pattern as before for visual consistency.
			imgui.Dummy({0, 20})
			imgui.Text('\227\129\157\227\129\174\228\187\150\227\129\174\230\147\141\228\189\156')
			local interactions = {
				{'\227\131\129\227\131\163\227\131\131\227\131\136\232\161\140\227\130\146\227\130\175\227\131\170\227\131\131\227\131\151\227\131\156\227\131\188\227\131\137\227\129\171\227\130\179\227\131\148\227\131\188',   '\227\131\129\227\131\163\227\131\131\227\131\136\232\161\140\227\130\146\229\183\166\227\130\175\227\131\170\227\131\131\227\130\175'},
				{'\227\131\150\227\131\169\227\130\166\227\130\182\227\129\167URL\227\130\146\233\150\139\227\129\143',                 '[link] \227\130\191\227\130\176\227\130\146\229\183\166\227\130\175\227\131\170\227\131\131\227\130\175'},
				{'\227\130\168\227\131\170\227\130\162\229\156\176\229\155\179 / \230\164\156\231\180\162\227\131\157\227\131\131\227\131\151\227\130\162\227\131\131\227\131\151',       '\227\130\168\227\131\170\227\130\162\229\144\141\227\130\146\229\144\171\227\130\128\232\161\140\227\130\146 Ctrl + \229\183\166\227\130\175\227\131\170\227\131\131\227\130\175'},
				{'\227\131\161\227\131\162\229\184\179\227\129\171\227\131\129\227\131\163\227\131\131\227\131\136\232\161\140\227\130\146\228\191\157\229\173\152',             '\227\131\129\227\131\163\227\131\131\227\131\136\232\161\140\227\130\146 Shift + \229\183\166\227\130\175\227\131\170\227\131\131\227\130\175\239\188\136\230\156\128\229\164\16710\228\187\182\239\188\137'},
				{'\227\131\129\227\131\163\227\131\131\227\131\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\130\146\231\167\187\229\139\149',             '\227\131\129\227\131\163\227\131\131\227\131\136\230\157\191\227\130\146\229\183\166\227\131\137\227\131\169\227\131\131\227\130\176'},
				{'\230\156\128\230\150\176\232\161\140\227\129\184\227\130\184\227\131\163\227\131\179\227\131\151\239\188\136\227\130\185\227\130\175\227\131\173\227\131\188\227\131\171\232\167\163\233\153\164\239\188\137',   '\227\129\169\227\129\147\227\129\167\227\130\130\229\143\179\227\130\175\227\131\170\227\131\131\227\130\175'},
				{'\227\131\129\227\131\163\227\131\131\227\131\136\229\177\165\230\173\180\227\130\146\227\130\185\227\130\175\227\131\173\227\131\188\227\131\171',             '\227\131\158\227\130\166\227\130\185\227\131\155\227\130\164\227\131\188\227\131\171'},
				{'\233\171\152\233\128\159\227\130\185\227\130\175\227\131\173\227\131\188\227\131\171\239\188\1365\232\161\140\239\188\137',               'Shift + \227\131\158\227\130\166\227\130\185\227\131\155\227\130\164\227\131\188\227\131\171'},
				{'\227\130\179\227\131\179\227\131\145\227\130\175\227\131\136\227\131\144\227\131\188\227\129\171\232\168\173\229\174\154\227\130\162\227\130\164\227\130\179\227\131\179\227\130\146\229\135\186\227\129\153',   '\227\130\179\227\131\179\227\131\145\227\130\175\227\131\136\227\130\191\227\131\150\227\129\174\229\177\149\233\150\139\227\130\162\227\130\164\227\130\179\227\131\179\227\129\171 Shift+\227\131\155\227\131\144\227\131\188'},
				{'\229\156\176\229\155\179 / \230\164\156\231\180\162\227\131\157\227\131\131\227\131\151\227\130\162\227\131\131\227\131\151\227\130\146\233\150\137\227\129\152\227\130\139',      '\229\164\150\229\129\180\227\130\146\227\130\175\227\131\170\227\131\131\227\130\175\227\128\129\227\129\190\227\129\159\227\129\175 Escape'},
			}
			for _, s in ipairs(interactions) do
				imgui.Dummy({0, 8})
				imgui.Dummy({3, 0}) imgui.SameLine()
				imgui.Text('['..s[1]..']')
				imgui.Dummy({0, 4})
				imgui.Dummy({3, 0}) imgui.SameLine()
				imgui.Text('- '..s[2])
			end

			imgui.EndChild()
			imgui.EndTabItem()
		end

		----------------------------------------------------------------
		-- Tab: Gamepad
		----------------------------------------------------------------
		if imgui.BeginTabItem('\227\130\178\227\131\188\227\131\160\227\131\145\227\131\131\227\131\137', nil) then
			imguiWrap.BeginChild('##Gamepad Child',
				{(setsizex * 3.8 / 3.9) - (12 * (1 - (setsizex * 3.8 / 1920))) - 3, setsizey * 2.7 / 2.8 - 60}, true)

			-- Resolve an XInput button id (e.g. 12) to a label for the
			-- UI.  In Xbox-controller mode we look up the friendly name
			-- ('A', 'LB', 'RT', ...) from utils.gamepadButtonList; in
			-- generic mode (default) we just show the raw button index,
			-- because non-Xbox pads map physical buttons to different
			-- XInput numbers than an Xbox pad would.
			local function gp_label_for(id)
				if type(id) == 'string' then
					local hat_name = ({
						hat_up    = '\227\131\143\227\131\131\227\131\136 \228\184\138',
						hat_down  = '\227\131\143\227\131\131\227\131\136 \228\184\139',
						hat_left  = '\227\131\143\227\131\131\227\131\136 \229\183\166',
						hat_right = '\227\131\143\227\131\131\227\131\136 \229\143\179',
					})[id]
					if hat_name then return hat_name end
				end
				if allSettings.XboxController[1] then
					local idx = utils.findIndexOfValue(utils.gamepadButtonList, id)
					if idx then return utils.gamepadButtonList[idx][1] end
				end
				return tostring(id)
			end

			-- Place the info icon at a column past the widest row label,
			-- measured at runtime via CalcTextSize so the position is
			-- correct regardless of the active font (gdifonts, scale,
			-- etc.).  Falls back to a generous fixed minimum if the
			-- measurement returns 0 for any reason.
			local longest_gp_label = '\228\191\174\233\163\190\227\131\156\227\130\191\227\131\179\239\188\136\230\138\188\227\129\151\227\129\166\227\129\132\227\130\139\233\150\147\227\129\160\227\129\145\227\131\138\227\131\147\230\156\137\229\138\185\239\188\137'
			local label_w          = imgui.CalcTextSize(longest_gp_label)
			local GP_TOOLTIP_X     = math.max((label_w or 0) + 20, 320)

			local function gp_inline_tooltip(message)
				imgui.SameLine(GP_TOOLTIP_X)
				imguiWrap.Image(fcw[1].TextureIDInfo, {15, 15})
				if imgui.IsItemHovered(0) then
					ShowTooltip(message)
				end
			end

			-- Draw one row: text label + a "listen" button showing the
			-- current binding.  Clicking the button arms a one-shot
			-- gamepad capture (handled in lib/input.lua's xinput_button
			-- callback); the very next button press becomes the new
			-- binding.  Clicking the same button again - or pressing
			-- Escape - cancels.  If the captured button was already
			-- bound to another action, the two actions swap.
			--
			-- color (optional) is an {r,g,b,a} table; when set the
			-- label is drawn via TextColored, used to highlight the
			-- Modifier row (the gate that has to be held for every
			-- other binding to fire).
			local function draw_gp_row(label, key, tooltip, color)
				if color then
					imgui.TextColored(color, label)
				else
					imgui.Text(label)
				end
				if tooltip then gp_inline_tooltip(tooltip) end
				local is_listen = (gamepadButtons.listenKey == key)
				local btn_text  = is_listen
					and '(\227\130\178\227\131\188\227\131\160\227\131\145\227\131\131\227\131\137\227\129\174\227\131\156\227\130\191\227\131\179\227\130\146\230\138\188\227\129\153 - Esc\227\129\167\227\130\173\227\131\163\227\131\179\227\130\187\227\131\171)'
					or  gp_label_for(allSettings.GamepadBindings[key])
				-- Highlight the active row so it's obvious which one
				-- is waiting for input.
				if is_listen then
					imgui.PushStyleColor(ImGuiCol_Button,        {0.55, 0.35, 0.10, 1.0})
					imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.65, 0.45, 0.15, 1.0})
					imgui.PushStyleColor(ImGuiCol_ButtonActive,  {0.75, 0.55, 0.20, 1.0})
				end
				if imgui.Button(btn_text..'##GP_'..key, {dsize.x / 6, 0}) then
					if is_listen then
						gamepadButtons.listenKey = nil
					else
						gamepadButtons.listenKey = key
					end
				end
				if is_listen then imgui.PopStyleColor(3) end
				imgui.Dummy({0, 8})
			end

			-- Top-of-tab toggles: master enable + label style.
			if imgui.Checkbox('\227\130\178\227\131\188\227\131\160\227\131\145\227\131\131\227\131\137\227\129\167\227\131\129\227\131\163\227\131\131\227\131\136\230\147\141\228\189\156##GamepadNav', {allSettings.GamepadNav[1]}) then
				allSettings.GamepadNav[1] = not allSettings.GamepadNav[1]
				SaveSettings()
			end
			AddTooltip('\227\130\178\227\131\188\227\131\160\227\131\145\227\131\131\227\131\137\229\133\165\229\138\155\227\129\174\227\131\158\227\130\185\227\130\191\227\131\188\227\130\185\227\130\164\227\131\131\227\131\129\227\129\167\227\129\153\227\128\130\227\130\170\227\131\179\227\129\171\227\129\151\227\129\166\227\128\129\228\191\174\233\163\190\227\131\156\227\130\191\227\131\179\239\188\136\229\136\157\230\156\159\227\129\175 LB\239\188\137\227\130\146\230\138\188\227\129\151\227\129\170\227\129\140\227\130\137\228\187\150\227\129\174\229\137\178\227\130\138\229\189\147\227\129\166\227\129\175\229\139\149\227\129\141\227\129\190\227\129\155\227\130\147\227\128\130Xbox\228\187\165\229\164\150\227\129\174\227\131\145\227\131\131\227\131\137\227\129\175 DirectInput \227\129\167\229\177\139\227\130\139\227\129\174\227\129\167\227\128\129\228\184\139\227\129\174\229\137\178\227\130\138\229\189\147\227\129\166\227\130\146\229\143\150\227\130\138\231\155\180\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130', 4)
			imgui.Dummy({0, 5})
			if imgui.Checkbox('Xbox \227\130\179\227\131\179\227\131\136\227\131\173\227\131\188\227\131\169\227\131\188##XboxLabels', {allSettings.XboxController[1]}) then
				allSettings.XboxController[1] = not allSettings.XboxController[1]
				SaveSettings()
			end
			AddTooltip('\227\130\170\227\131\179\227\129\171\227\129\153\227\130\139\227\129\168\227\131\156\227\130\191\227\131\179\229\144\141\227\130\146 Xbox \232\161\168\232\168\152\239\188\136A, B, LB, RT \227\129\170\227\129\169\239\188\137\227\129\167\232\161\168\231\164\186\227\129\151\227\129\190\227\129\153\227\128\130\227\130\170\227\131\149\227\129\171\227\129\153\227\130\139\227\129\168\231\148\159\227\129\174 XInput \231\149\170\229\143\183\227\129\167\227\129\153\227\128\130Xbox\228\187\165\229\164\150\227\129\174\227\131\145\227\131\131\227\131\137\227\129\167\227\129\175\227\130\170\227\131\149\227\129\174\227\129\187\227\129\134\227\129\140\229\174\137\229\133\168\227\129\167\227\129\153\227\128\130', 4)
			imgui.Dummy({0, 10})

			imgui.Text('\230\156\128\229\190\140\227\129\171\229\143\151\227\129\145\229\143\150\227\129\163\227\129\159\229\133\165\229\138\155')
			if not gamepadButtons.lastApi then
				imgui.TextColored({0.70, 0.70, 0.70, 1.0},
					'\227\129\190\227\129\160\227\129\130\227\130\138\227\129\190\227\129\155\227\130\147\227\128\130\227\130\179\227\131\179\227\131\136\227\131\173\227\131\188\227\131\169\227\131\188\227\129\174\227\131\156\227\130\191\227\131\179\227\130\146\230\138\188\227\129\153\227\129\168\231\149\170\229\143\183\227\129\140\229\135\186\227\129\190\227\129\153\227\128\130')
			else
				local api_name = (gamepadButtons.lastApi == 'dinput') and 'DirectInput' or 'XInput'
				local hat_dir  = gamepadButtons.lastHatDir
				local hat_jp   = ({
					up    = '\228\184\138',
					down  = '\228\184\139',
					left  = '\229\183\166',
					right = '\229\143\179',
				})[hat_dir]
				local hat_txt  = hat_jp
					and ('  (\227\131\143\227\131\131\227\131\136 '..hat_jp..')')
					or ''
				imgui.Text(string.format('%s  \227\131\156\227\130\191\227\131\179 %s  \231\138\182\230\133\139 %s%s',
					api_name, tostring(gamepadButtons.lastButton), tostring(gamepadButtons.lastState), hat_txt))
				if gamepadButtons.lastApi == 'dinput' then
					imgui.TextColored({1.00, 0.75, 0.30, 1.0},
						'DirectInput \227\129\167\227\129\153\227\128\130\229\136\157\230\156\159\227\129\174 Xbox \231\149\170\229\143\183\227\129\168\227\129\175\228\184\128\232\135\180\227\129\151\227\129\170\227\129\132\227\129\174\227\129\167\227\128\129\228\184\139\227\129\174\232\161\140\227\129\167\227\131\156\227\130\191\227\131\179\227\130\146\229\143\150\227\130\138\231\155\180\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130')
					imgui.TextColored({0.80, 0.85, 0.70, 1.0},
						'\229\141\129\229\173\151\227\130\173\227\131\188\227\129\175\227\131\143\227\131\131\227\131\136\239\188\136\232\167\146\229\186\166\239\188\137\227\129\167\227\129\153\227\128\130\229\137\178\227\130\138\229\189\147\227\129\166\228\184\173\227\129\175\230\150\185\229\144\145\227\130\146\227\131\143\227\131\131\227\131\136\229\183\166\227\129\170\227\129\169\227\129\168\232\161\168\231\164\186\227\129\151\227\129\190\227\129\153\227\128\130')
				end
			end
			imgui.Dummy({0, 15})

			imgui.Text('\227\130\178\227\131\188\227\131\160\227\131\145\227\131\131\227\131\137\227\129\174\227\131\156\227\130\191\227\131\179\229\137\178\227\130\138\229\189\147\227\129\166')
			AddTooltip('\232\161\140\227\129\174\229\143\179\229\129\180\227\130\146\227\130\175\227\131\170\227\131\131\227\130\175\227\129\153\227\130\139\227\129\168\227\128\129\230\172\161\227\129\171\230\138\188\227\129\151\227\129\159\227\130\178\227\131\188\227\131\160\227\131\145\227\131\131\227\131\137\227\131\156\227\130\191\227\131\179\227\130\146\229\137\178\227\130\138\229\189\147\227\129\166\227\129\190\227\129\153\227\128\130\227\129\153\227\129\167\227\129\171\228\187\150\227\129\174\230\147\141\228\189\156\227\129\167\228\189\191\227\129\163\227\129\166\227\129\132\227\130\139\227\131\156\227\130\191\227\131\179\227\129\170\227\130\137\227\128\1292\227\129\164\227\129\174\229\137\178\227\130\138\229\189\147\227\129\166\227\129\140\229\133\165\227\130\140\230\155\191\227\130\143\227\130\138\227\129\190\227\129\153\227\128\130\227\130\185\227\131\134\227\130\163\227\131\131\227\130\175\227\129\174\227\130\185\227\130\175\227\131\173\227\131\188\227\131\171\232\187\184\227\129\175\229\164\137\230\155\180\227\129\167\227\129\141\227\129\190\227\129\155\227\130\147\227\128\130', 0)
			imgui.Dummy({0, 4})
			imgui.TextColored({0.70, 0.70, 0.70, 1.0},
				'\232\161\140\227\129\174\229\143\179\229\129\180\227\129\174\227\131\156\227\130\191\227\131\179\227\130\146\227\130\175\227\131\170\227\131\131\227\130\175\227\129\151\227\129\166\227\129\139\227\130\137\227\128\129\229\137\178\227\130\138\229\189\147\227\129\166\227\129\159\227\129\132')
			imgui.TextColored({0.70, 0.70, 0.70, 1.0},
				'\227\130\179\227\131\179\227\131\136\227\131\173\227\131\188\227\131\169\227\131\188\227\129\174\227\131\156\227\130\191\227\131\179\227\130\146\230\138\188\227\129\151\227\129\190\227\129\153\227\128\130Esc \227\129\167\227\130\173\227\131\163\227\131\179\227\130\187\227\131\171\227\128\130')
			imgui.Dummy({0, 10})

			draw_gp_row('\228\191\174\233\163\190\227\131\156\227\130\191\227\131\179\239\188\136\230\138\188\227\129\151\227\129\166\227\129\132\227\130\139\233\150\147\227\129\160\227\129\145\227\131\138\227\131\147\230\156\137\229\138\185\239\188\137', 'modifier',
				'\230\138\188\227\129\151\227\129\166\227\129\132\227\130\139\233\150\147\227\128\129\228\184\139\227\129\174\227\130\178\227\131\188\227\131\160\227\131\145\227\131\131\227\131\137\229\137\178\227\130\138\229\189\147\227\129\166\227\129\140\230\156\137\229\138\185\227\129\171\227\129\170\227\130\138\227\129\190\227\129\153\227\128\130\227\129\147\227\129\174\233\150\147\227\128\129\228\187\150\227\129\174\227\131\156\227\130\191\227\131\179\227\129\175\227\130\178\227\131\188\227\131\160\229\129\180\227\129\171\230\184\161\227\130\138\227\129\190\227\129\155\227\130\147\227\128\130',
				{1.00, 0.65, 0.20, 1.0})
			draw_gp_row('\227\130\191\227\131\150\229\136\135\230\155\191\239\188\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\1661\239\188\137',     'cyclePrimaryTab')
			draw_gp_row('\227\130\191\227\131\150\229\136\135\230\155\191\239\188\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\1662\239\188\137',     'cycleSecondaryTab')
			draw_gp_row('\230\156\128\230\150\176\232\161\140\227\129\184\227\130\184\227\131\163\227\131\179\227\131\151',           'snapToBottom')
			draw_gp_row('BigMode \227\130\146\229\136\135\230\155\191',             'toggleBigMode',
				'BigMode \228\184\173\227\129\175\227\128\129\228\191\174\233\163\190\227\131\156\227\130\191\227\131\179\239\188\139\229\183\166\229\143\179\227\129\167\227\130\166\227\130\163\227\131\179\227\131\137\227\130\1661\227\128\129\229\143\179\227\129\167\227\130\166\227\130\163\227\131\179\227\131\137\227\130\1662\227\129\171\229\136\135\227\130\138\230\155\191\227\129\136\227\129\190\227\129\153\227\128\130\231\172\1722\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\140\230\156\137\229\138\185\227\129\174\227\129\168\227\129\141\227\129\171\228\189\191\227\129\136\227\129\190\227\129\153\227\128\130')
			draw_gp_row('FFXI\227\131\129\227\131\163\227\131\131\227\131\136\229\133\165\229\138\155\227\130\146\233\150\139\227\129\143',     'openChatInput')
			draw_gp_row('\229\133\165\229\138\155\227\130\146\227\130\179\227\131\158\227\131\179\227\131\137\227\129\168\227\129\151\227\129\166\233\128\129\228\191\161',   'submitInput',
				'\227\129\132\227\129\190 FFXI \227\129\174\227\131\129\227\131\163\227\131\131\227\131\136\229\133\165\229\138\155\230\172\132\227\129\171\227\129\130\227\130\139\232\161\140\227\130\146\233\128\129\228\191\161\227\129\151\227\129\190\227\129\153\227\128\130')
			draw_gp_row('\227\130\179\227\131\158\227\131\179\227\131\137\229\177\165\230\173\180: \229\137\141\227\129\184',         'historyPrev')
			draw_gp_row('\227\130\179\227\131\158\227\131\179\227\131\137\229\177\165\230\173\180: \230\172\161\227\129\184',         'historyNext')
			draw_gp_row('\227\131\151\227\131\170\227\130\187\227\131\131\227\131\136\227\130\179\227\131\158\227\131\179\227\131\137: \229\137\141\227\129\184',   'presetPrev',
				'FFXI \229\133\165\229\138\155\228\184\173\227\129\175\227\131\151\227\131\170\227\130\187\227\131\131\227\131\136\227\130\179\227\131\158\227\131\179\227\131\137\227\128\130BigMode \228\184\173\227\129\175\227\130\166\227\130\163\227\131\179\227\131\137\227\130\1661\227\129\171\229\136\135\227\130\138\230\155\191\227\128\130DirectInput \227\129\174\229\141\129\229\173\151\227\130\173\227\131\188\229\183\166\227\129\175\227\131\143\227\131\131\227\131\136\227\129\168\227\129\151\227\129\166\232\135\170\229\139\149\227\129\167\232\170\141\232\173\152\227\129\151\227\129\190\227\129\153\227\128\130')
			draw_gp_row('\227\131\151\227\131\170\227\130\187\227\131\131\227\131\136\227\130\179\227\131\158\227\131\179\227\131\137: \230\172\161\227\129\184',   'presetNext',
				'FFXI \229\133\165\229\138\155\228\184\173\227\129\175\227\131\151\227\131\170\227\130\187\227\131\131\227\131\136\227\130\179\227\131\158\227\131\179\227\131\137\227\128\130BigMode \228\184\173\227\129\175\227\130\166\227\130\163\227\131\179\227\131\137\227\130\1662\227\129\171\229\136\135\227\130\138\230\155\191\227\128\130DirectInput \227\129\174\229\141\129\229\173\151\227\130\173\227\131\188\229\143\179\227\129\175\227\131\143\227\131\131\227\131\136\227\129\168\227\129\151\227\129\166\232\135\170\229\139\149\227\129\167\232\170\141\232\173\152\227\129\151\227\129\190\227\129\153\227\128\130')

			imgui.Dummy({0, 6})
			if imgui.Button('\229\136\157\230\156\159\229\128\164\227\129\171\230\136\187\227\129\153##GPReset') then
				allSettings.GamepadBindings.modifier          = 8
				allSettings.GamepadBindings.cyclePrimaryTab   = 9
				allSettings.GamepadBindings.cycleSecondaryTab = 17
				allSettings.GamepadBindings.snapToBottom      = 13
				allSettings.GamepadBindings.toggleBigMode     = 15
				allSettings.GamepadBindings.openChatInput     = 14
				allSettings.GamepadBindings.submitInput       = 12
				allSettings.GamepadBindings.historyPrev       = 0
				allSettings.GamepadBindings.historyNext       = 1
				allSettings.GamepadBindings.presetPrev        = 2
				allSettings.GamepadBindings.presetNext        = 3
				SaveSettings()
			end

			imgui.EndChild()
			imgui.EndTabItem()
		end

		----------------------------------------------------------------
		-- Tab: Extra
		----------------------------------------------------------------
		if imgui.BeginTabItem('\227\129\157\227\129\174\228\187\150', nil) then
			imguiWrap.BeginChild('##Extra Child',
				{(setsizex * 3.8 / 3.9) - (12 * (1 - (setsizex * 3.8 / 1920))) - 3, setsizey * 2.7 / 2.8 - 60}, true)

			imgui.Text('\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\129\184\227\129\174\232\161\168\231\164\186\227\130\146\227\131\150\227\131\173\227\131\131\227\130\175')
			AddTooltip('\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\129\184\227\129\174\231\157\128\228\191\161\227\130\146\230\173\162\227\130\129\227\128\129FancyChat \227\129\160\227\129\145\227\129\171\232\161\168\231\164\186\227\129\151\227\129\190\227\129\153\227\128\130\230\150\176\231\157\128\230\153\130\227\129\174\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\228\188\184\231\184\174\227\130\162\227\131\139\227\131\161\239\188\136\227\129\161\227\130\137\227\129\164\227\129\141\239\188\137\227\130\130\230\173\162\227\129\190\227\130\138\227\129\190\227\129\153\227\128\130', 0)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\227\129\153\227\129\185\227\129\166', {allSettings.blockAll[1]}) then
				allSettings.blockAll[1] = not allSettings.blockAll[1]
				if allSettings.blockAll[1] then
					if not set.Popup[1] then set.Popup[1] = true end
				else
					set.Popup[1] = false
					allSettings.autoDumpChat[1] = false
				end
				SaveSettings()
			end
			if set.Popup[1] then
				AddWarning('\228\184\128\233\128\154\227\130\138\227\131\134\227\130\185\227\131\136\230\184\136\227\129\191\227\129\167\227\129\153\227\129\140\227\128\129\230\156\170\231\162\186\232\170\141\227\129\174\229\160\180\233\157\162\227\129\167\227\129\175\228\188\154\232\169\177\227\129\140\233\128\178\227\130\129\227\130\137\227\130\140\227\129\170\227\129\143\227\129\170\227\130\139\229\143\175\232\131\189\230\128\167\227\129\140\227\129\130\227\130\138\227\129\190\227\129\153\227\128\130\n\n\229\149\143\233\161\140\227\129\140\229\135\186\227\129\159\227\130\137\227\130\170\227\131\149\227\129\171\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130\n\n\227\130\181\227\131\157\227\131\188\227\131\136\231\148\168\227\129\171\227\131\129\227\131\163\227\131\131\227\131\136\227\131\173\227\130\176\227\130\146\230\143\144\229\135\186\227\129\153\227\130\139\227\129\168\227\129\141\227\129\175\227\128\129\227\128\140\227\131\132\227\131\188\227\131\171\227\128\141\227\129\174\227\128\140\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\129\174\227\131\173\227\130\176\227\130\146\229\190\169\229\133\131\227\128\141\227\130\146\228\189\191\227\129\132\227\128\129\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\129\174\227\130\185\227\130\175\227\131\170\227\131\188\227\131\179\227\130\183\227\131\167\227\131\131\227\131\136\227\130\146\230\146\174\227\129\163\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130', 350)
			end
			AddTooltip('NPC\228\188\154\232\169\177\227\129\167\232\169\176\227\129\190\227\130\139\229\160\180\229\144\136\227\129\175\227\130\170\227\131\149\227\129\171\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132', 4, 1)
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\230\136\166\233\151\152\227\129\174\227\129\191\239\188\136\230\142\168\229\165\168\239\188\137', {allSettings.blockCombat[1]}) then
				allSettings.blockCombat[1] = not allSettings.blockCombat[1]
				SaveSettings()
			end

			imgui.Dummy({0, 15})
			imgui.Text('\227\131\129\227\131\163\227\131\131\227\131\136\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\174\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\239\188\136\229\174\159\233\168\147\231\154\132\239\188\137')
			AddTooltip('\227\129\157\227\129\174\229\160\180\227\129\167\231\180\160\230\151\169\227\129\143\229\136\135\227\130\138\230\155\191\227\129\136\227\130\139\231\148\168\227\129\167\227\129\153\227\128\130\227\129\190\227\129\154\227\129\175\227\130\178\227\131\188\227\131\160\230\156\172\228\189\147\227\129\174\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\227\130\146\228\189\191\227\129\163\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130', 0, 1)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\230\136\166\233\151\152\227\131\187\227\130\171\227\130\185\227\130\191\227\131\160\227\131\173\227\130\176\227\130\146\227\128\140\229\133\168\227\129\166\227\128\141\227\130\191\227\131\150\227\129\139\227\130\137\233\154\160\227\129\153', {allSettings.HideCombatFromAll[1]}) then
				allSettings.HideCombatFromAll[1] = not allSettings.HideCombatFromAll[1]
				if allSettings.HideCombatFromAll[1] then
					tab.Tabs[1] = 'AllAlt'
					if allSettings.SelectedTab == 'All' then tab.NextTab = 'AllAlt' end
					if allSettings.SecondChat[1] and allSettings.SelectedTab2 == 'All' then
						tab.NextTab2 = 'AllAlt'
					end
				else
					tab.Tabs[1] = 'All'
					if allSettings.SelectedTab == 'AllAlt' then tab.NextTab = 'All' end
					if allSettings.SecondChat[1] and allSettings.SelectedTab2 == 'AllAlt' then
						tab.NextTab2 = 'All'
					end
				end
				SaveSettings()
			end
			AddTooltip('\228\184\161\230\150\185\227\129\174\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\174\227\128\140\229\133\168\227\129\166\227\128\141\227\130\191\227\131\150\227\129\139\227\130\137\230\136\166\233\151\152\227\131\187\227\130\171\227\130\185\227\130\191\227\131\160\227\131\173\227\130\176\227\130\146\233\154\160\227\129\151\227\129\190\227\129\153\227\128\130\231\172\1722\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\160\227\129\145\233\153\164\227\129\141\227\129\159\227\129\132\227\129\168\227\129\141\227\129\175\227\128\129\227\131\129\227\131\163\227\131\131\227\131\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\232\168\173\229\174\154\227\129\174\227\128\140\231\172\1722\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\174\227\128\140\229\133\168\227\129\166\227\128\141\227\129\139\227\130\137\230\136\166\233\151\152\227\130\146\233\153\164\227\129\143\227\128\141\227\130\146\228\189\191\227\129\163\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130', 4, true)
			-- Filter mode selector.  Text-based = the three legacy
			-- boolean toggles that use name-matching in the parser;
			-- Packet-based = the 0x0028-driven hierarchy that's
			-- mutually exclusive with the text-based system.  Picking
			-- one hides the other's controls below.
			imgui.Dummy({0, 8})
			imgui.Dummy({5, 0}) imgui.SameLine()
			-- Align the label with the radio circles by using the same
			-- frame padding ImGui applies to the radio widgets.
			imgui.AlignTextToFramePadding()
			imgui.Text('\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\230\150\185\229\188\143:')
			imgui.SameLine()
			if imgui.RadioButton('\227\131\134\227\130\173\227\130\185\227\131\136', not allSettings.PacketFilterEnabled2[1]) then
				allSettings.PacketFilterEnabled2[1] = false
				SaveSettings()
			end
			imgui.SameLine()
			local cposY = imgui.GetCursorPosY()
			AddTooltip('\227\131\134\227\130\173\227\130\185\227\131\136\230\150\185\229\188\143\227\129\175\227\130\162\227\130\175\227\130\191\227\131\188\229\144\141\227\129\160\227\129\145\227\129\167\229\136\164\229\174\154\227\129\151\227\129\190\227\129\153\227\128\130\229\144\140\227\129\152\229\144\141\229\137\141\227\129\174\227\131\136\227\131\169\227\130\185\227\131\136\227\131\187\227\131\154\227\131\131\227\131\136\227\131\187\227\131\149\227\130\167\227\131\173\227\131\188\227\129\140\232\191\145\227\129\143\227\129\171\227\129\132\227\130\139\227\129\168\227\128\129\233\154\160\227\129\151\227\129\159\227\129\132\231\155\184\230\137\139\227\129\174\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\140\230\188\143\227\130\140\227\130\139\227\129\147\227\129\168\227\129\140\227\129\130\227\130\138\227\129\190\227\129\153\227\128\130\227\130\136\227\129\143\232\181\183\227\129\141\227\130\139\227\129\170\227\130\137\227\131\145\227\130\177\227\131\131\227\131\136\230\150\185\229\188\143\227\129\171\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130\227\130\181\227\131\188\227\131\144\227\131\188\227\129\174\227\130\168\227\131\179\227\131\134\227\130\163\227\131\134\227\130\163ID\227\129\167\229\136\164\229\174\154\227\129\153\227\130\139\227\129\174\227\129\167\227\128\129\229\144\140\229\144\141\227\129\167\227\130\130\230\183\183\229\144\140\227\129\151\227\129\190\227\129\155\227\130\147\227\128\130', 4, true)
			imgui.SameLine() imgui.SetCursorPosY(cposY)
			if imgui.RadioButton('\227\131\145\227\130\177\227\131\131\227\131\136', allSettings.PacketFilterEnabled2[1]) then
				allSettings.PacketFilterEnabled2[1] = true
				SaveSettings()
			end

			if not allSettings.PacketFilterEnabled2[1] then
				-- Text-based system: the original three checkboxes.
				imgui.Dummy({0, 5})
				imgui.Dummy({5, 0}) imgui.SameLine()
				if imgui.Checkbox('\227\130\162\227\131\169\227\130\164\227\130\162\227\131\179\227\130\185\227\129\174\230\136\166\233\151\152\227\131\173\227\130\176\227\130\146\233\154\160\227\129\153', {allSettings.hideAlliance[1]}) then
					allSettings.hideAlliance[1] = not allSettings.hideAlliance[1]
					if not allSettings.hideAlliance[1] then allSettings.hideNonYou[1] = false end
					SaveSettings()
				end
				imgui.Dummy({0, 5})
				imgui.Dummy({5, 0}) imgui.SameLine()
				if imgui.Checkbox('\227\131\145\227\131\188\227\131\134\227\130\163\228\187\165\229\164\150\227\129\174\230\136\166\233\151\152\227\131\173\227\130\176\227\130\146\233\154\160\227\129\153', {allSettings.hideNonParty[1]}) then
					allSettings.hideNonParty[1] = not allSettings.hideNonParty[1]
					if not allSettings.hideNonParty[1] then allSettings.hideNonYou[1] = false end
					SaveSettings()
				end
				imgui.Dummy({15, 0}) imgui.SameLine() imgui.Text('L')
				imgui.SetCursorPosY(imgui.GetCursorPosY() - 20)
				imgui.Dummy({27, 0}) imgui.SameLine()
				if imgui.Checkbox('\232\135\170\229\136\134\227\129\168\227\131\154\227\131\131\227\131\136\227\129\174\227\131\173\227\130\176\227\129\160\227\129\145\232\161\168\231\164\186', {allSettings.hideNonYou[1]}) then
					allSettings.hideNonYou[1] = not allSettings.hideNonYou[1]
					if allSettings.hideNonYou[1] then allSettings.hideNonParty[1] = true end
					if allSettings.hideNonYou[1] then allSettings.hideAlliance[1] = true end
					SaveSettings()
				end
			else
				-- Packet-based system: a 5-way hierarchy radio.  Each
				-- level subsumes everything stricter (level 1 shows
				-- all, level 5 shows only the player).  TARGET (the
				-- mob you / party are engaged with) is always shown.
				imgui.Dummy({0, 5})
				imgui.Dummy({5, 0}) imgui.SameLine()
				imgui.Text('\230\136\166\233\151\152\227\131\173\227\130\176\227\129\174\232\161\168\231\164\186\231\175\132\229\155\178:')
				AddTooltip('\232\135\170\229\136\134\227\129\190\227\129\159\227\129\175\227\131\145\227\131\188\227\131\134\227\130\163\227\129\140\228\186\164\230\136\166\228\184\173\227\129\174\227\131\162\227\131\179\227\130\185\227\130\191\227\131\188\227\129\175\227\128\129\228\184\139\227\129\174\227\129\169\227\130\140\227\130\146\233\129\184\227\130\147\227\129\167\227\130\130\229\184\184\227\129\171\232\161\168\231\164\186\227\129\149\227\130\140\227\129\190\227\129\153\227\128\130', 0, 1)
				imgui.Dummy({0, 3})
				local levels = {
					{1, '\229\133\168\229\147\161\239\188\136\227\129\157\227\129\174\228\187\150 + \227\130\162\227\131\169\227\130\164\227\130\162\227\131\179\227\130\185 + \227\131\145\227\131\188\227\131\134\227\130\163 + \232\135\170\229\136\134 + \227\131\154\227\131\131\227\131\136\239\188\137'},
					{2, '\227\130\162\227\131\169\227\130\164\227\130\162\227\131\179\227\130\185 + \227\131\145\227\131\188\227\131\134\227\130\163 + \232\135\170\229\136\134 + \227\131\154\227\131\131\227\131\136'},
					{3, '\227\131\145\227\131\188\227\131\134\227\130\163 + \232\135\170\229\136\134 + \227\131\154\227\131\131\227\131\136'},
					{4, '\232\135\170\229\136\134 + \227\131\154\227\131\131\227\131\136'},
					{5, '\232\135\170\229\136\134\227\129\174\227\129\191'},
				}
				for _, lv in ipairs(levels) do
					imgui.Dummy({15, 0}) imgui.SameLine()
					if imgui.RadioButton(lv[2]..'##PacketFilterLevel'..tostring(lv[1]),
						allSettings.PacketFilterLevel == lv[1]) then
						allSettings.PacketFilterLevel = lv[1]
						SaveSettings()
					end
				end

				-- Restrict the always-shown TARGET scope to packets
				-- where the player is among the targets.  Useful in
				-- "only show what's happening to me" play.
				imgui.Dummy({0, 5})
				imgui.Dummy({15, 0}) imgui.SameLine()
				if imgui.Checkbox('\232\135\170\229\136\134\227\129\140\229\175\190\232\177\161\227\129\174TARGET\232\161\140\229\139\149\227\129\160\227\129\145\232\161\168\231\164\186##PacketFilterTargetMeOnly',
					{allSettings.PacketFilterTargetMeOnly[1]}) then
					allSettings.PacketFilterTargetMeOnly[1] = not allSettings.PacketFilterTargetMeOnly[1]
					SaveSettings()
				end
				AddTooltip('\227\130\170\227\131\179\227\129\171\227\129\153\227\130\139\227\129\168\227\128\129\228\186\164\230\136\166\228\184\173\227\131\162\227\131\179\227\130\185\227\130\191\227\131\188\227\129\174\232\161\140\229\139\149\227\129\175\227\128\129\232\135\170\229\136\134\227\129\140\229\175\190\232\177\161\227\129\171\229\144\171\227\129\190\227\130\140\227\130\139\227\129\168\227\129\141\227\129\160\227\129\145\232\161\168\231\164\186\227\129\151\227\129\190\227\129\153\227\128\130\227\131\145\227\131\188\227\131\134\227\130\163\227\131\161\227\131\179\227\131\144\227\131\188\227\129\160\227\129\145\227\129\171\229\189\147\227\129\159\227\129\163\227\129\159\230\148\187\230\146\131\227\131\187\227\130\162\227\131\147\227\131\170\227\131\134\227\130\163\227\129\175\233\154\160\227\130\140\227\129\190\227\129\153\227\128\130', 4)
			end

			imgui.Dummy({0, 5})
			imgui.Text('\227\129\157\227\129\174\228\187\150\227\129\174\232\168\173\229\174\154')
			AddTooltip('\232\169\179\227\129\151\227\129\143\227\129\175\227\131\158\227\131\139\227\131\165\227\130\162\227\131\171\227\130\146\229\143\130\231\133\167\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132', 0)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\227\130\179\227\131\179\227\131\145\227\130\175\227\131\136\230\136\166\233\151\152\227\131\173\227\130\176', {allSettings.CompactCombat[1]}) then
				allSettings.CompactCombat[1] = not allSettings.CompactCombat[1]
				SaveSettings()
			end
			AddTooltip('simplelog \227\129\170\227\129\169\228\187\150\227\129\174\227\131\129\227\131\163\227\131\131\227\131\136\230\148\185\229\164\137\227\130\162\227\131\137\227\130\170\227\131\179\227\130\146\228\189\191\227\129\134\229\160\180\229\144\136\227\129\175\227\130\170\227\131\149\227\129\171\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130', 4)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\227\130\191\227\130\164\227\131\160\227\130\185\227\130\191\227\131\179\227\131\151', {allSettings.timeStamp[1]}) then
				allSettings.timeStamp[1] = not allSettings.timeStamp[1]
				if allSettings.timeStamp[1] then allSettings.timeStampLine[1] = false end
				SaveSettings()
			end
			imgui.Dummy({15, 0}) imgui.SameLine() imgui.Text('L')
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 18)
			imgui.Dummy({30, 0}) imgui.SameLine()
			imgui.Text('\229\189\162\229\188\143')
			imgui.SameLine()
			local formats = {'[00:00:00]', '[00:00]'}
			local currentFormat = formats[allSettings.FormatTSMode]
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 3)
			imgui.PushItemWidth(dsize.x / 15)
			if imgui.BeginCombo('##TimestampFormat', currentFormat, ImGuiComboFlags_None) then
				if imgui.Selectable(formats[1], currentFormat == formats[1]) then allSettings.FormatTSMode = 1 end
				if imgui.Selectable(formats[2], currentFormat == formats[2]) then allSettings.FormatTSMode = 2 end
				SaveSettings()
				imgui.EndCombo()
			end
			imgui.PopItemWidth()
			imgui.SameLine()
			if imgui.Checkbox('12\230\153\130\233\150\147\232\161\168\231\164\186', {allSettings.TimeStamp12h[1]}) then
				allSettings.TimeStamp12h[1] = not allSettings.TimeStamp12h[1]
				SaveSettings()
			end
			AddTooltip('13\230\153\130\228\187\165\233\153\141\227\129\17512\227\130\146\229\188\149\227\129\132\227\129\166\232\161\168\231\164\186\227\129\151\227\129\190\227\129\153\239\188\136\228\190\139: 14:30 \226\134\146 2:30\239\188\137\227\128\130AM/PM \227\129\175\229\135\186\227\129\151\227\129\190\227\129\155\227\130\147\227\128\130', 4)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\227\130\191\227\130\164\227\131\160\227\130\185\227\130\191\227\131\179\227\131\151\227\130\146\231\139\172\231\171\139\227\129\151\227\129\159\232\161\140\227\129\171\227\129\153\227\130\139', {allSettings.timeStampLine[1]}) then
				allSettings.timeStampLine[1] = not allSettings.timeStampLine[1]
				if allSettings.timeStampLine[1] then allSettings.timeStamp[1] = false end
				SaveSettings()
			end
			imgui.Dummy({15, 0}) imgui.SameLine() imgui.Text('L')
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 18)
			imgui.Dummy({30, 0}) imgui.SameLine()
			imgui.Text('\233\150\147\233\154\148')
			imgui.SameLine()
			local minutes = {
				{'1 minute', 60, '1\229\136\134'},
				{'5 minutes', 300, '5\229\136\134'},
				{'10 minutes', 600, '10\229\136\134'},
				{'30 minutes', 1800, '30\229\136\134'},
				{'60 minutes', 3600, '60\229\136\134'},
			}
			local freq_preview = allSettings.timeStampLineFreq[1]
			for TS_i = 1, #minutes do
				if minutes[TS_i][1] == allSettings.timeStampLineFreq[1] then
					freq_preview = minutes[TS_i][3]
					break
				end
			end
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 3)
			imgui.PushItemWidth(dsize.x / 15)
			if imgui.BeginCombo('##TimeStampLineFreq', freq_preview, ImGuiComboFlags_None) then
				for TS_i = 1, #minutes do
					if imgui.Selectable(minutes[TS_i][3]) then
						allSettings.timeStampLineFreq = {minutes[TS_i][1], minutes[TS_i][2]}
						SaveSettings()
					end
				end
				imgui.EndCombo()
			end
			imgui.PopItemWidth()
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('R0 \230\153\130\227\129\171\232\173\166\229\145\138\227\130\146\229\135\186\227\129\153', {allSettings.R0warning[1]}) then
				allSettings.R0warning[1] = not allSettings.R0warning[1]
				SaveSettings()
			end
			AddTooltip('R0\239\188\136\229\136\135\230\150\173\227\129\174\228\186\136\229\133\134\239\188\137\227\129\140\229\135\186\227\129\159\227\129\168\227\129\141\227\129\171\227\131\129\227\131\163\227\131\131\227\131\136\227\129\184\232\173\166\229\145\138\227\130\146\229\135\186\227\129\151\227\129\190\227\129\153\227\128\130', 4)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\231\178\190\229\175\134TOD\227\130\191\227\130\164\227\131\160\227\130\185\227\130\191\227\131\179\227\131\151', {allSettings.PreciseTS[1]}) then
				allSettings.PreciseTS[1] = not allSettings.PreciseTS[1]
				SaveSettings()
			end
			AddTooltip('\230\149\181\227\130\146\229\128\146\227\129\151\227\129\159\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\174\230\168\170\227\129\171\227\128\129\231\167\146\229\141\152\228\189\141\227\129\174\230\153\130\229\136\187\227\130\146\228\187\152\227\129\145\227\129\190\227\129\153\227\128\130', 4)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('Tell \231\157\128\228\191\161\233\128\154\231\159\165', {allSettings.tellNotification[1]}) then
				allSettings.tellNotification[1] = not allSettings.tellNotification[1]
				SaveSettings()
			end
			AddTooltip('Tell \227\130\146\229\143\151\227\129\145\229\143\150\227\129\163\227\129\159\227\129\168\227\129\141\227\129\171\227\128\129\233\129\184\227\130\147\227\129\160\233\128\154\231\159\165\233\159\179\227\130\146\233\179\180\227\130\137\227\129\151\227\129\190\227\129\153\227\128\130', 4)
			imgui.Dummy({15, 0}) imgui.SameLine() imgui.Text('L')
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 20)
			imgui.Dummy({27, 0}) imgui.SameLine()
			imgui.PushItemWidth(dsize.x / 8)
			if imgui.BeginCombo('##NotificationShould', allSettings.selectedNotification, ImGuiComboFlags_None) then
				for NS_i = 1, 6 do
					if imgui.Selectable('notification_'..tostring(NS_i)) then
						allSettings.selectedNotification = 'notification_'..tostring(NS_i)
						SaveSettings()
					end
				end
				imgui.EndCombo()
			end
			imgui.PopItemWidth()
			imgui.SameLine()
			if imgui.ArrowButton('PlayNotification', ImGuiDir_Right) then
				ashita.misc.play_sound(string.format('%s\\notifications\\%s%s.wav',
					addon.path, allSettings.selectedNotification, allSettings.boostNotification[1] and 'B' or ''))
			end
			imgui.SameLine()
			imgui.Text('\229\134\141\231\148\159')
			imgui.Dummy({15, 0}) imgui.SameLine() imgui.Text('L')
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 20)
			imgui.Dummy({27, 0}) imgui.SameLine()
			if imgui.Checkbox('\233\159\179\233\135\143\227\131\150\227\131\188\227\130\185\227\131\136', {allSettings.boostNotification[1]}) then
				allSettings.boostNotification[1] = not allSettings.boostNotification[1]
				SaveSettings()
			end
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\229\141\152\232\170\158\227\130\162\227\131\169\227\131\188\227\131\136', {allSettings.Alert[1]}) then
				allSettings.Alert[1] = not allSettings.Alert[1]
				SaveSettings()
			end
			AddTooltip('\230\140\135\229\174\154\227\129\151\227\129\159\229\141\152\232\170\158\227\129\140\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\171\229\144\171\227\129\190\227\130\140\227\130\139\227\129\168\227\128\129\233\129\184\227\130\147\227\129\160\233\128\154\231\159\165\233\159\179\227\130\146\233\179\180\227\130\137\227\129\151\227\129\190\227\129\153\227\128\130', 4)
			imgui.Dummy({15, 0}) imgui.SameLine() imgui.Text('L')
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 18)
			imgui.Dummy({30, 0}) imgui.SameLine()
			imgui.Text('\227\130\162\227\131\169\227\131\188\227\131\136\229\141\152\232\170\158') imgui.SameLine()
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 2)
			imgui.PushItemWidth(dsize.x / 10)
			imgui.InputText('##AlertWords', set.alertBuffer, 255,
				bit.bor(ImGuiInputTextFlags_CharsNoBlank, ImGuiInputTextFlags_CallbackAlways),
				function()
					allSettings.alertwords = set.alertBuffer[1]:gsub('\0', '')
					set.alertList = utils.stringsplit(allSettings.alertwords, ',')
					SaveSettings()
				end)
			imgui.SameLine()
			AddTooltip('\229\141\152\232\170\158\227\129\175\227\130\171\227\131\179\227\131\158\229\140\186\229\136\135\227\130\138\227\128\130\229\164\167\230\150\135\229\173\151\229\176\143\230\150\135\229\173\151\227\129\175\229\140\186\229\136\165\227\129\151\227\129\190\227\129\155\227\130\147\227\128\130', 4)
			imgui.Dummy({15, 0}) imgui.SameLine() imgui.Text('L')
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 20)
			imgui.Dummy({27, 0}) imgui.SameLine()
			imgui.PushItemWidth(dsize.x / 8)
			if imgui.BeginCombo('##AlertShould', allSettings.selectedAlert, ImGuiComboFlags_None) then
				for AS_i = 1, 6 do
					if imgui.Selectable('notification_'..tostring(AS_i)) then
						allSettings.selectedAlert = 'notification_'..tostring(AS_i)
						SaveSettings()
					end
				end
				imgui.EndCombo()
			end
			imgui.PopItemWidth()
			imgui.SameLine()
			if imgui.ArrowButton('PlayAlert', ImGuiDir_Right) then
				ashita.misc.play_sound(string.format('%s\\notifications\\%s%s.wav',
					addon.path, allSettings.selectedAlert, allSettings.boostAlert[1] and 'B' or ''))
			end
			imgui.SameLine()
			imgui.Text('\229\134\141\231\148\159')
			imgui.Dummy({15, 0}) imgui.SameLine() imgui.Text('L')
			imgui.SetCursorPosY(imgui.GetCursorPosY() - 20)
			imgui.Dummy({27, 0}) imgui.SameLine()
			if imgui.Checkbox('\233\159\179\233\135\143\227\131\150\227\131\188\227\130\185\227\131\136##Alert', {allSettings.boostAlert[1]}) then
				allSettings.boostAlert[1] = not allSettings.boostAlert[1]
				SaveSettings()
			end
			if allSettings.Alert[1] then
				imgui.Dummy({15, 0}) imgui.SameLine() imgui.Text('L')
				imgui.SetCursorPosY(imgui.GetCursorPosY() - 18)
				imgui.Dummy({30, 0}) imgui.SameLine()
				imgui.Text('\229\175\190\232\177\161\227\131\129\227\131\163\227\131\179\227\131\141\227\131\171')
				local channels = {'Say', '\227\130\183\227\131\163\227\130\166\227\131\136', '\227\131\145\227\131\188\227\131\134\227\130\163', '\227\131\170\227\131\179\227\130\175\227\130\183\227\130\167\227\131\171', '\227\131\166\227\131\139\227\131\134\227\130\163'}
				for c_i = 1, 5 do
					imgui.Dummy({0, 5})
					imgui.Dummy({30, 0}) imgui.SameLine()
					if imgui.Checkbox(channels[c_i], {allSettings.alertOptions[c_i]}) then
						allSettings.alertOptions[c_i] = not allSettings.alertOptions[c_i]
						SaveSettings()
					end
				end
			end

			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\227\130\162\227\130\164\227\131\134\227\131\160 / \227\130\162\227\131\147\227\131\170\227\131\134\227\130\163 / \233\173\148\230\179\149\227\130\146\227\131\155\227\131\144\227\131\188\227\129\167\227\131\151\227\131\172\227\131\147\227\131\165\227\131\188', {allSettings.ItemPreview[1]}) then
				allSettings.ItemPreview[1] = not allSettings.ItemPreview[1]
				SaveSettings()
			end
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\130\146\233\150\139\227\129\132\227\129\159\227\129\168\227\129\141\227\129\171\227\131\173\227\130\176\227\130\146\229\190\169\229\133\131', {allSettings.autoDumpChat[1]}) then
				if not allSettings.autoDumpChat[1] and allSettings.blockAll[1] then
					allSettings.autoDumpChat[1] = true
				elseif allSettings.autoDumpChat[1] then
					allSettings.autoDumpChat[1] = false
				end
				SaveSettings()
			end
			AddTooltip('\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\129\184\227\129\174\229\133\168\227\131\150\227\131\173\227\131\131\227\130\175\227\129\140\227\130\170\227\131\179\227\129\174\227\129\168\227\129\141\227\129\160\227\129\145\228\189\191\227\129\136\227\129\190\227\129\153\227\128\130\n\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\130\146\233\150\139\227\129\132\227\129\159\227\129\168\227\129\141\227\129\171\227\128\129FancyChat \229\129\180\227\129\174\229\177\165\230\173\180\227\130\146\229\190\169\229\133\131\227\129\151\227\129\190\227\129\153\227\128\130', 4)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\228\184\142\227\131\128\227\131\161\227\131\188\227\130\184 / \232\162\171\227\131\128\227\131\161\227\131\188\227\130\184\227\130\146\232\137\178\232\166\154\227\130\181\227\131\157\227\131\188\227\131\136\233\133\141\232\137\178\227\129\171', {allSettings.ColorBlind[1]}) then
				allSettings.ColorBlind[1] = not allSettings.ColorBlind[1]
				SaveSettings()
			end
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('\227\131\129\227\131\163\227\131\131\227\131\136\229\177\165\230\173\180\227\130\146\233\171\152\233\128\159\227\130\185\227\130\175\227\131\173\227\131\188\227\131\171', {allSettings.EnableFastScroll[1]}) then
				allSettings.EnableFastScroll[1] = not allSettings.EnableFastScroll[1]
				SaveSettings()
			end
			AddTooltip('\227\131\129\227\131\163\227\131\131\227\131\136\228\184\138\227\129\171\227\131\158\227\130\166\227\130\185\227\130\146\231\189\174\227\129\141\227\128\129[Shift] + [<] \227\129\190\227\129\159\227\129\175 [>] \227\129\167\229\177\165\230\173\180\227\130\146\232\164\135\230\149\176\232\161\140\227\129\190\227\129\168\227\130\129\227\129\166\233\128\129\227\130\140\227\129\190\227\129\153\227\128\130', 4)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('GuideMe / \227\131\161\227\131\162\229\184\179\227\130\146\231\172\1722\227\131\129\227\131\163\227\131\131\227\131\136\227\129\171\227\131\137\227\131\131\227\130\173\227\131\179\227\130\176', {allSettings.GuideMeSecondWindow[1]}) then
				if allSettings.SecondChat[1] then
					allSettings.GuideMeSecondWindow[1] = not allSettings.GuideMeSecondWindow[1]
					SaveSettings()
				end
			end
			AddTooltip('\231\172\1722\227\131\129\227\131\163\227\131\131\227\131\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\140\230\156\137\229\138\185\227\129\170\227\129\168\227\129\141\227\129\160\227\129\145\228\189\191\227\129\136\227\129\190\227\129\153\227\128\130', 4)
			-- "Enable FC color marking" toggle is hidden for now 
			-- the addon currently relies on FC marking being on for
			-- correct combat / actor highlighting and legacy-escape
			-- handling.  The underlying allSettings.EnableFCColorMarking
			-- flag is still respected throughout the codebase, so this
			-- block can be re-enabled later without other changes.
			--[[
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox('Enable FC color marking', {allSettings.EnableFCColorMarking[1]}) then
				allSettings.EnableFCColorMarking[1] = not allSettings.EnableFCColorMarking[1]
				SaveSettings()
			end
			AddTooltip('Uses and FC color formatting (Recommended). Disable to try use default color markings.', 4)
			]]
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if imgui.Checkbox(allSettings.heartEmoji[1] and ' <3' or ' ', {allSettings.heartEmoji[1]}) then
				allSettings.heartEmoji[1] = not allSettings.heartEmoji[1]
				SaveSettings()
			end

			imgui.EndChild()
			imgui.EndTabItem()
		end

		----------------------------------------------------------------
		-- Tab: Filters  (contains two sub-tabs: Combat / Other)
		----------------------------------------------------------------
		if imgui.BeginTabItem('\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188', nil) then
			imguiWrap.BeginChild('##Filters Child',
				{(setsizex * 3.8 / 3.9) - (12 * (1 - (setsizex * 3.8 / 1920))) - 3, setsizey * 2.7 / 2.8 - 60}, true)

			-- Draw the file-picker + master-toggle + active-filter table
			-- for one filter kind.  Driven by the per-kind table below
			-- so both Combat Filters and Other Filters use identical UI
			-- with only the underlying setting keys + folder path swapped.
			--
			-- kind          : 'combat' / 'other' (passed to utils.* helpers)
			-- masterKey     : key in allSettings holding the master toggle
			-- selectedKey   : key in allSettings holding the active filename
			-- missingKey    : key in `set` holding the file-missing flag
			-- listKey       : key in `par` holding the parsed filter list
			-- folderName    : on-disk subfolder name (for Open Folder button)
			-- introBlurb    : top-of-tab descriptive paragraph
			-- masterLabel   : label on the enable checkbox
			-- tableHeader   : label above the result table
			local function draw_filter_panel(opts)
				imgui.PushTextWrapPos(imgui.GetWindowWidth() * 0.96)
				imgui.TextWrapped(opts.introBlurb)
				imgui.Dummy({0, 5})

				-- Detection point: every frame the sub-tab is open.
				CheckActiveFilter(opts.kind)

				-- File picker.  The list itself is cached in
				-- cachedFilterFiles[kind] to avoid running the dir
				-- scan every frame -- Refresh re-scans on demand.
				if cachedFilterFiles[opts.kind] == nil then
					cachedFilterFiles[opts.kind] = utils.ListFilters(opts.kind)
				end
				local filterFiles = cachedFilterFiles[opts.kind]
				local missing     = set[opts.missingKey]

				imgui.Text('\228\189\191\231\148\168\227\129\153\227\130\139\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\227\131\149\227\130\161\227\130\164\227\131\171:')
				imgui.SameLine()
				imgui.SetNextItemWidth(setsizex * 0.4)
				local comboLabel = allSettings[opts.selectedKey] or ''
				if missing then
					comboLabel = '[\232\166\139\227\129\164\227\129\139\227\130\138\227\129\190\227\129\155\227\130\147] '..comboLabel
				end
				if imgui.BeginCombo('##SelectedFilter_'..opts.kind, comboLabel, ImGuiComboFlags_None) then
					if #filterFiles == 0 then
						imgui.TextDisabled('(filters/'..opts.kind..'/ \227\129\171 .txt \227\129\140\227\129\130\227\130\138\227\129\190\227\129\155\227\130\147)')
					else
						for fi = 1, #filterFiles do
							if imgui.Selectable(filterFiles[fi], filterFiles[fi] == allSettings[opts.selectedKey]) then
								allSettings[opts.selectedKey] = filterFiles[fi]
								par[opts.listKey] = utils.LoadFilters(opts.kind, allSettings[opts.selectedKey])
								SaveSettings()
								CheckActiveFilter(opts.kind)
							end
						end
					end
					imgui.EndCombo()
				end
				imgui.SameLine()
				if imgui.Button('\230\155\180\230\150\176##FilterFiles_'..opts.kind) then
					cachedFilterFiles[opts.kind] = utils.ListFilters(opts.kind)
					CheckActiveFilter(opts.kind)
				end
				AddTooltip('filters/'..opts.kind..'/ \227\129\174\227\129\169\227\129\174\227\131\149\227\130\161\227\130\164\227\131\171\227\130\146\228\189\191\227\129\134\227\129\139\227\130\146\233\129\184\227\129\179\227\129\190\227\129\153\227\128\130\n\n\227\128\140\230\155\180\230\150\176\227\128\141\227\129\167\227\131\149\227\130\169\227\131\171\227\131\128\227\130\146\229\134\141\227\130\185\227\130\173\227\131\163\227\131\179\227\129\151\227\128\129\232\191\189\229\138\160\227\131\187\230\148\185\229\144\141\227\129\151\227\129\159 .txt \227\130\146\229\143\141\230\152\160\227\129\151\227\129\190\227\129\153\227\128\130', 4)
				imgui.Dummy({0, 5})

				if missing then
					imgui.TextColored({1.0, 0.3, 0.3, 1.0}, '[!] \228\189\191\231\148\168\228\184\173\227\129\174\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\227\131\149\227\130\161\227\130\164\227\131\171\227\129\140\227\131\149\227\130\169\227\131\171\227\131\128\227\129\171\227\129\130\227\130\138\227\129\190\227\129\155\227\130\147\227\128\130')
					imgui.TextColored({1.0, 0.3, 0.3, 1.0}, '    \227\128\140\230\155\180\230\150\176\227\128\141\227\130\146\230\138\188\227\129\151\227\129\166\227\129\139\227\130\137\227\128\129\227\131\137\227\131\173\227\131\131\227\131\151\227\131\128\227\130\166\227\131\179\227\129\167\229\136\165\227\131\149\227\130\161\227\130\164\227\131\171\227\130\146\233\129\184\227\130\147\227\129\167\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130')
					imgui.Dummy({0, 5})
				end

				if imgui.Button('\233\129\184\230\138\158\227\131\149\227\130\161\227\130\164\227\131\171\227\130\146\231\183\168\233\155\134##'..opts.kind) then
					local filepath = addon.path..'\\filters\\'..opts.kind..'\\'..allSettings[opts.selectedKey]
					os.execute('start "" "'..filepath..'"')
				end
				if missing and imgui.IsItemHovered() then
					ShowTooltip('\228\189\191\231\148\168\228\184\173\227\129\174\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\227\131\149\227\130\161\227\130\164\227\131\171\227\129\140\227\129\130\227\130\138\227\129\190\227\129\155\227\130\147\227\128\130\228\184\138\227\129\174\227\131\137\227\131\173\227\131\131\227\131\151\227\131\128\227\130\166\227\131\179\227\129\139\227\130\137\229\136\165\227\131\149\227\130\161\227\130\164\227\131\171\227\130\146\233\129\184\227\130\147\227\129\167\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130')
				end
				imgui.SameLine()
				if imgui.Button('\233\129\184\230\138\158\227\131\149\227\130\161\227\130\164\227\131\171\227\130\146\229\134\141\232\170\173\232\190\188##'..opts.kind) then
					par[opts.listKey] = utils.LoadFilters(opts.kind, allSettings[opts.selectedKey])
					CheckActiveFilter(opts.kind)
				end
				if missing and imgui.IsItemHovered() then
					ShowTooltip('\228\189\191\231\148\168\228\184\173\227\129\174\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\227\131\149\227\130\161\227\130\164\227\131\171\227\129\140\227\129\130\227\130\138\227\129\190\227\129\155\227\130\147\227\128\130\228\184\138\227\129\174\227\131\137\227\131\173\227\131\131\227\131\151\227\131\128\227\130\166\227\131\179\227\129\139\227\130\137\229\136\165\227\131\149\227\130\161\227\130\164\227\131\171\227\130\146\233\129\184\227\130\147\227\129\167\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130')
				end
				imgui.SameLine()
				if imgui.Button('\227\131\149\227\130\169\227\131\171\227\131\128\227\130\146\233\150\139\227\129\143##'..opts.kind) then
					os.execute('start "" "'..addon.path..'\\filters\\'..opts.kind..'\\"')
				end
				AddTooltip('filters/'..opts.kind..'/ \227\130\146\227\130\168\227\130\175\227\130\185\227\131\151\227\131\173\227\131\188\227\131\169\227\131\188\227\129\167\233\150\139\227\129\141\227\128\129\227\131\149\227\130\161\227\130\164\227\131\171\227\129\174\232\191\189\229\138\160\227\130\132\230\148\185\229\144\141\227\129\140\227\129\167\227\129\141\227\129\190\227\129\153\227\128\130', 4)
				imgui.Separator()
				imgui.Dummy({0, 5})

				if imgui.Checkbox(opts.masterLabel..'##master_'..opts.kind, {allSettings[opts.masterKey][1]}) then
					allSettings[opts.masterKey][1] = not allSettings[opts.masterKey][1]
					SaveSettings()
					if allSettings[opts.masterKey][1] then
						CheckActiveFilter(opts.kind)
					end
				end
				imgui.Dummy({0, 5})

				if allSettings[opts.masterKey][1] then
					imgui.Text(opts.tableHeader)
					-- Scope ('Applied to') only exists for combat
					-- filters - for the 'other' kind every line is
					-- always treated as scope = '_z' (all), so we drop
					-- the column entirely to avoid a useless "All"
					-- repeated down the table.
					local hasScope = opts.kind == 'combat'
					local nCols    = hasScope and 2 or 1
					if imgui.BeginTable('resultTable_'..opts.kind, nCols,
						bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersH, ImGuiTableFlags_BordersV, ImGuiTableFlags_ContextMenuInBody)) then
						if hasScope then
							imgui.TableSetupColumn('\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188',     ImGuiTableColumnFlags_WidthFixed,   imgui.GetWindowWidth() * 0.7, 0)
							imgui.TableSetupColumn('\229\175\190\232\177\161', ImGuiTableColumnFlags_WidthStretch, 0, 0)
						else
							imgui.TableSetupColumn('\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188', ImGuiTableColumnFlags_WidthStretch, 0, 0)
						end
						imgui.TableHeadersRow()
						local list = par[opts.listKey]
						for cf = 1, #list do
							imgui.TableNextRow()
							imgui.TableSetColumnIndex(0)
							imgui.PushTextWrapPos(imgui.GetWindowWidth() * (hasScope and 0.7 or 0.95))
							imgui.TextWrapped(list[cf][1]:replace('%', '%%'))
							imgui.PopTextWrapPos()
							if hasScope then
								imgui.TableSetColumnIndex(1)
								local cf_scope = ''
								if list[cf][2] then
									if     list[cf][2] == '_z' then cf_scope = cf_scope + '\227\129\153\227\129\185\227\129\166'
									elseif list[cf][2] == '_y' then cf_scope = cf_scope + '\232\135\170\229\136\134\228\187\165\229\164\150'
									elseif list[cf][2] == '_p' then cf_scope = cf_scope + '\227\131\145\227\131\188\227\131\134\227\130\163\228\187\165\229\164\150' end
								end
								imgui.PushTextWrapPos(imgui.GetWindowWidth() * 0.9)
								imgui.TextWrapped(cf_scope)
								imgui.PopTextWrapPos()
							end
						end
						imgui.PopTextWrapPos()
						imgui.EndTable()
					end
				end
			end

			if imgui.BeginTabBar('##FiltersInnerTabs', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
				if imgui.BeginTabItem('\230\136\166\233\151\152\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188', nil) then
					draw_filter_panel({
						kind        = 'combat',
						masterKey   = 'CustomFilters',
						selectedKey = 'SelectedCombatFilter',
						missingKey  = 'filterFileMissing',
						listKey     = 'customFilters',
						introBlurb  = 'filters/combat \227\131\149\227\130\169\227\131\171\227\131\128\227\129\174\227\131\134\227\130\173\227\130\185\227\131\136\227\131\149\227\130\161\227\130\164\227\131\171\227\129\171\229\141\152\232\170\158\227\130\146\230\155\184\227\129\143\227\129\168\227\128\129\230\136\166\233\151\152\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\130\146\233\154\160\227\129\155\227\129\190\227\129\153\227\128\130\229\144\132\227\131\149\227\130\161\227\130\164\227\131\171\227\129\175\227\128\129\233\154\160\227\129\151\227\129\159\227\129\132\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\171\229\144\171\227\129\190\227\130\140\227\130\139\229\141\152\232\170\158\227\129\174\227\131\170\227\130\185\227\131\136\227\129\167\227\129\153\227\128\130\n\239\188\136\228\190\139: effect wears off\239\188\137\n\n> \229\141\152\232\170\158\227\129\175\227\128\129\227\130\162\227\131\137\227\130\170\227\131\179\230\148\185\229\164\137\229\137\141\227\129\174\227\130\178\227\131\188\227\131\160\230\156\172\228\189\147\227\129\174\230\136\166\233\151\152\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\171\229\144\171\227\129\190\227\130\140\227\130\139\229\191\133\232\166\129\227\129\140\227\129\130\227\130\138\227\129\190\227\129\153\n> \229\164\167\230\150\135\229\173\151\229\176\143\230\150\135\229\173\151\227\129\175\229\140\186\229\136\165\227\129\151\227\129\190\227\129\155\227\130\147\n> \232\169\179\231\180\176\227\129\175\229\144\132\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\227\131\149\227\130\161\227\130\164\227\131\171\229\134\133\227\129\171\227\129\130\227\130\138\227\129\190\227\129\153\n\n!!! \227\131\170\227\130\185\227\131\136\227\129\140\233\157\158\229\184\184\227\129\171\233\149\183\227\129\132\227\129\168\232\178\160\232\141\183\227\129\140\233\171\152\227\129\143\227\129\170\227\130\138\227\129\190\227\129\153 !!!',
						masterLabel = '\230\136\166\233\151\152\227\131\173\227\130\176\227\129\174\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\227\130\146\230\156\137\229\138\185\227\129\171\227\129\153\227\130\139',
						tableHeader = '\231\143\190\229\156\168\227\129\174\230\136\166\233\151\152\227\131\173\227\130\176\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188:',
					})
					imgui.EndTabItem()
				end

				if imgui.BeginTabItem('\227\129\157\227\129\174\228\187\150\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188', nil) then
					draw_filter_panel({
						kind        = 'other',
						masterKey   = 'OtherFilters',
						selectedKey = 'SelectedOtherFilter',
						missingKey  = 'otherFilterFileMissing',
						listKey     = 'otherFilters',
						introBlurb  = 'filters/other \227\131\149\227\130\169\227\131\171\227\131\128\227\129\174\227\131\134\227\130\173\227\130\185\227\131\136\227\131\149\227\130\161\227\130\164\227\131\171\227\129\171\229\141\152\232\170\158\227\130\146\230\155\184\227\129\143\227\129\168\227\128\129\230\136\166\233\151\152\228\187\165\229\164\150\227\129\174\227\131\129\227\131\163\227\131\131\227\131\136\239\188\136NPC\229\143\176\232\169\158\227\128\129\227\130\183\227\130\185\227\131\134\227\131\160\227\128\129Tell\227\128\129\227\130\183\227\131\163\227\130\166\227\131\136\227\129\170\227\129\169\239\188\137\227\130\146\233\154\160\227\129\155\227\129\190\227\129\153\227\128\130\229\144\132\227\131\149\227\130\161\227\130\164\227\131\171\227\129\175\227\128\129\233\154\160\227\129\151\227\129\159\227\129\132\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\171\229\144\171\227\129\190\227\130\140\227\130\139\229\141\152\232\170\158\227\129\174\227\131\170\227\130\185\227\131\136\227\129\167\227\129\153\227\128\130\n\n> \229\141\152\232\170\158\227\129\175\227\128\129\227\130\162\227\131\137\227\130\170\227\131\179\230\148\185\229\164\137\229\137\141\227\129\174\227\130\178\227\131\188\227\131\160\230\156\172\228\189\147\227\129\174\227\131\161\227\131\131\227\130\187\227\131\188\227\130\184\227\129\171\229\144\171\227\129\190\227\130\140\227\130\139\229\191\133\232\166\129\227\129\140\227\129\130\227\130\138\227\129\190\227\129\153\n> \229\164\167\230\150\135\229\173\151\229\176\143\230\150\135\229\173\151\227\129\175\229\140\186\229\136\165\227\129\151\227\129\190\227\129\155\227\130\147\n> \232\169\179\231\180\176\227\129\175\229\144\132\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\227\131\149\227\130\161\227\130\164\227\131\171\229\134\133\227\129\171\227\129\130\227\130\138\227\129\190\227\129\153\n\n!!! \227\131\170\227\130\185\227\131\136\227\129\140\233\157\158\229\184\184\227\129\171\233\149\183\227\129\132\227\129\168\232\178\160\232\141\183\227\129\140\233\171\152\227\129\143\227\129\170\227\130\138\227\129\190\227\129\153 !!!',
						masterLabel = '\227\129\157\227\129\174\228\187\150\227\131\129\227\131\163\227\131\131\227\131\136\227\129\174\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188\227\130\146\230\156\137\229\138\185\227\129\171\227\129\153\227\130\139',
						tableHeader = '\231\143\190\229\156\168\227\129\174\227\129\157\227\129\174\228\187\150\227\131\149\227\130\163\227\131\171\227\130\191\227\131\188:',
					})
					imgui.EndTabItem()
				end

				imgui.EndTabBar()
			end

			imgui.EndChild()
			imgui.EndTabItem()
		end

		----------------------------------------------------------------
		-- Tab: Tools
		----------------------------------------------------------------
		if imgui.BeginTabItem('\227\131\132\227\131\188\227\131\171', nil) then
			imguiWrap.BeginChild('##Tools Child',
				{(setsizex * 3.8 / 3.9) - (12 * (1 - (setsizex * 3.8 / 1920))) - 3, setsizey * 2.7 / 2.8 - 60}, true)

			-- Save Chat Logs
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if fcw[1].TextureIDLogs ~= nil and fcw[1].TextureIDLoading ~= nil then
				if imguiWrap.ImageButton('TextureIDLogs',
					fcw[1].SaveStart == 0 and fcw[1].TextureIDLogs or fcw[1].TextureIDLoading,
					{dsize.x / 100, dsize.x / 100}, {-0.01, -0.01}, {1.01, 1.01},
					-1, {0, 0, 0, 0}, {1, 1, 1, 1}) then
					if fcw[1].SaveStart == 0 then
						fcw[1].SaveStart = os.clock() - fcw[1].SaveStart
						AshitaCore:GetChatManager():QueueCommand(-1, '/fancychat savelogs')
					end
				end
			end
			if os.clock() - fcw[1].SaveStart > fcw[1].SaveCD then
				fcw[1].SaveStart = 0
			end
			imgui.SameLine()
			imgui.SetCursorPosY(imgui.GetCursorPosY() + dsize.x / 300)
			if fcw[1].SaveStart > 0 then imgui.Text('\228\191\157\229\173\152\228\184\173...') else imgui.Text('\227\131\129\227\131\163\227\131\131\227\131\136\227\131\173\227\130\176\227\130\146\228\191\157\229\173\152') end

			-- Open Logs Folder
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if fcw[1].TextureIDFolder ~= nil then
				if imguiWrap.ImageButton('TextureIDFolder', fcw[1].TextureIDFolder,
					{dsize.x / 100, dsize.x / 100}, {-0.01, -0.01}, {1.01, 1.01},
					-1, {0, 0, 0, 0}, {1, 1, 1, 1}) then
					local logsDir = AshitaCore:GetInstallPath()
						..'\\config\\addons\\'..addon.name..'\\logs\\'..fcw[1].PlayerName
					os.execute('mkdir "'..logsDir..'" 2>nul')
					os.execute('start "" "'..logsDir..'"')
				end
			end
			imgui.SameLine()
			imgui.SetCursorPosY(imgui.GetCursorPosY() + dsize.x / 300)
			imgui.Text('\227\131\173\227\130\176\227\131\149\227\130\169\227\131\171\227\131\128\227\130\146\233\150\139\227\129\143')

			-- Open Manual
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if fcw[1].TextureIDManual ~= nil then
				if imguiWrap.ImageButton('TextureIDManual', fcw[1].TextureIDManual,
					{dsize.x / 100, dsize.x / 100}, {0.01, 0.01}, {0.99, 0.99},
					-1, {0, 0, 0, 0}, {1, 1, 1, 1}) then
					help.opened[1] = not help.opened[1]
				end
			end
			imgui.SameLine()
			imgui.SetCursorPosY(imgui.GetCursorPosY() + dsize.x / 300)
			imgui.Text('\227\131\158\227\131\139\227\131\165\227\130\162\227\131\171\227\130\146\233\150\139\227\129\143')

			-- Restore Legacy Chat Logs (DumpChat)
			imgui.Dummy({0, 5})
			imgui.Dummy({5, 0}) imgui.SameLine()
			if fcw[1].TextureIDDumpchat ~= nil then
				if imguiWrap.ImageButton('TextureIDDumpchat', fcw[1].TextureIDDumpchat,
					{dsize.x / 100, dsize.x / 100}, {0.05, 0.01}, {0.98, 1.0},
					-1, {0, 0, 0, 0}, {1, 1, 1, 1}) then
					DumpChat('-------------- \227\131\129\227\131\163\227\131\131\227\131\136\227\130\146\229\190\169\229\133\131\227\129\151\227\129\190\227\129\151\227\129\159 --------------')
					b.OriginalBuffer = T{}
				end
			end
			imgui.SameLine()
			imgui.SetCursorPosY(imgui.GetCursorPosY() + dsize.x / 300)
			imgui.Text('\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\129\174\227\131\173\227\130\176\227\130\146\229\190\169\229\133\131')
			AddTooltip('\229\190\147\230\157\165\227\131\129\227\131\163\227\131\131\227\131\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\171\229\177\165\230\173\180\227\130\146\230\136\187\227\129\151\227\129\190\227\129\153\227\128\130\227\130\181\227\131\157\227\131\188\227\131\136\231\148\168\227\129\174\227\130\185\227\130\175\227\131\170\227\131\188\227\131\179\227\130\183\227\131\167\227\131\131\227\131\136\227\130\146\230\146\174\227\130\139\227\129\168\227\129\141\227\129\171\228\189\191\227\129\132\227\129\190\227\129\153\227\128\130', 0, 1)

			imgui.EndChild()
			imgui.EndTabItem()
		end

		----------------------------------------------------------------
		-- Tab: Credits
		----------------------------------------------------------------
		if imgui.BeginTabItem('\227\130\175\227\131\172\227\130\184\227\131\131\227\131\136', nil) then
			imguiWrap.BeginChild('##Credits Child',
				{(setsizex * 3.8 / 3.9) - (12 * (1 - (setsizex * 3.8 / 1920))) - 3, setsizey * 2.7 / 2.8 - 60}, true)

			imgui.Dummy({0, 15})

			-- ----- Centered logo at the top -----
			-- Sized to 35% of the child width (capped at 220 px) so it
			-- scales nicely on different Settings-window widths but never
			-- dominates the tab.  TextureIDLogo is loaded from
			-- images/logo.png in utils.LoadTextures().
			if fcw[1].TextureIDLogo ~= nil then
				local _winW    = imgui.GetWindowWidth()
				local _logoSz  = math.min(_winW * 0.35, 220)
				imgui.SetCursorPosX((_winW - _logoSz) * 0.5)
				-- UV crop: shows the central 80% x 80% of the source
				-- texture (10% trimmed from each side).  The texture
				-- has transparent padding around the visible artwork;
				-- cropping eliminates the dead space so the visible
				-- logo content fills the rect and the version caption
				-- below sits flush against it.
				imgui.Image(fcw[1].TextureIDLogo,
				            {_logoSz, _logoSz*0.8},
				            {0, 0.1},   -- uv0 (top-left)
				            {1, 0.85})   -- uv1 (bottom-right)
				-- Tight to the logo so the version reads as a caption.
				imgui.Dummy({0, 2})
			end

			-- ----- Version + author line, centered, yellow -----
			-- FancyChatJP uses its own semver (e.g. 1.0.1), not
			-- upstream's "<major>.<minor>.<YYMMDD>R" date stamp.
			local _winW       = imgui.GetWindowWidth()
			local _versionStr = tostring(addon.version or '')

			local _YELLOW = {1.0, 0.92, 0.16, 1.0}

			local _line1 = '\227\131\144\227\131\188\227\130\184\227\131\167\227\131\179: '..(_versionStr ~= '' and _versionStr or '?')
			local _w1    = imgui.CalcTextSize(_line1)
			imgui.SetCursorPosX((_winW - _w1) * 0.5)
			imgui.TextColored(_YELLOW, _line1)

			local _line2 = '\228\189\156\230\136\144\232\128\133 Arielfy / Hando'
			local _w2    = imgui.CalcTextSize(_line2)
			imgui.SetCursorPosX((_winW - _w2) * 0.5)
			imgui.TextColored(_YELLOW, _line2)

			imgui.Dummy({0, 15})

			-- Section-header colour, shared by Links / Major Thanks /
			-- Special Thanks for visual consistency.  Light azure.
			local _SECTION = {0.50, 0.78, 0.95, 1.0}

			-- ----- Links -----
			imgui.TextColored(_SECTION, '\227\131\170\227\131\179\227\130\175')
			imgui.Separator()
			imgui.Dummy({0, 8})

			-- Each entry is {label, url}.  Empty url shows "(link coming)"
			-- as a disabled placeholder; otherwise the URL is rendered
			-- as a clickable hyperlink that opens in the default
			-- browser via imguiWrap.TextLinkOpenURL.  Labels (and the
			-- matching bullet) are in a light-purple hue distinct from
			-- the Major Thanks green / light-red.
			local _LIGHT_PURPLE = {0.80, 0.65, 0.95, 1.0}
			local _links = {
				{'FancyChat JP GitHub:',   addon.link or 'https://github.com/handomade/FancyChatJP'},
				{'FancyChat (original):',  'https://github.com/ariel-logos/Fancychat'},
				{'Arielfy GitHub:',        'https://github.com/ariel-logos'},
				{'ElfyLab:',               'http://ariel-logos.github.io/ElfyLab'},
			}
			for _, _link in ipairs(_links) do
				imgui.Dummy({30, 0}) imgui.SameLine()
				-- Color-matched bullet (same trick as the Major-Thanks
				-- helper: push ImGuiCol_Text just for the bullet glyph,
				-- then restore).
				imgui.PushStyleColor(ImGuiCol_Text, _LIGHT_PURPLE)
				imgui.Bullet()
				imgui.PopStyleColor()
				imgui.TextColored(_LIGHT_PURPLE, _link[1])
				imgui.SameLine()
				if _link[2] ~= '' then
					-- Strip the scheme AND leading "www." from the
					-- displayed URL so it reads cleanly ("github.com/foo"
					-- rather than "https://www.github.com/foo"); the
					-- click target still uses the full URL so the
					-- browser launches correctly.
					local _display = _link[2]
						:gsub('^https?://', '')
						:gsub('^www%.', '')
					imguiWrap.TextLinkOpenURL(_display, _link[2])
				else
					imgui.TextDisabled('\239\188\136\230\186\150\229\130\153\228\184\173\239\188\137')
				end
			end

			imgui.Dummy({0, 25})

			-- ----- Major Thanks -----
			-- Two colour-coded subsections under one header: the Ashita
			-- platform contributors (green) and the testers (light red
			-- - kept distinctly red rather than pink by keeping the
			-- green channel noticeably higher than blue).  Each name
			-- can carry an optional URL; when set, it renders as
			-- "Name(<clickable url>)" with no space before the parens.
			imgui.TextColored(_SECTION, '\231\137\185\229\136\165\227\129\170\230\132\159\232\172\157')
			imgui.Separator()
			imgui.Dummy({0, 8})

			local _GREEN     = {0.45, 0.85, 0.55, 1.0}  -- soft light green
			local _LIGHT_RED = {0.95, 0.45, 0.35, 1.0}  -- #F27359, red-orange (NOT pink)

			local function _credit(name, url, color)
				imgui.Dummy({30, 0}) imgui.SameLine()
				-- Bullet tinted to match the name's color: temporarily
				-- override ImGuiCol_Text so the bullet glyph picks up
				-- our hue, then restore.  Bullet() finishes with an
				-- internal SameLine so the name lands on the same row.
				imgui.PushStyleColor(ImGuiCol_Text, color)
				imgui.Bullet()
				imgui.PopStyleColor()
				imgui.TextColored(color, name)
				if url and url ~= '' then
					local _href = url:find('://') and url or ('https://'..url)
					-- Display-only: scheme + leading "www." stripped so
					-- "https://www.foo.com" reads as "foo.com".  Click
					-- target keeps the full URL.
					local _display = url
						:gsub('^https?://', '')
						:gsub('^www%.', '')
					imgui.SameLine(0, 0)
					imgui.Text('  (')
					imgui.SameLine(0, 0)
					imguiWrap.TextLinkOpenURL(_display, _href)
					imgui.SameLine(0, 0)
					imgui.Text(')')
				end
			end

			-- Subsection 1: Ashita platform + key devs (green)
			imgui.Dummy({10, 0}) imgui.SameLine()
			imgui.Text('\227\130\162\227\131\137\227\130\170\227\131\179\233\150\139\231\153\186\227\131\132\227\131\188\227\131\171\227\129\168\227\128\129\229\138\169\227\129\145\227\129\168\229\191\141\232\128\144\227\129\171\230\132\159\232\172\157\227\129\151\227\129\190\227\129\153:')
			imgui.Dummy({0, 4})
			-- TODO: fill optional URLs.  Empty string = no link.
			local _ashita = {
				{'The Ashita Team', ''},
				{'atom0s',          ''},
				{'Thorny',          ''},
			}
			for _, _e in ipairs(_ashita) do
				_credit(_e[1], _e[2], _GREEN)
			end

			-- Visual break between the two subsections; the colour
			-- shift carries most of the separation.
			imgui.Dummy({0, 12})

			-- Subsection 2: Testers (light red)
			imgui.Dummy({10, 0}) imgui.SameLine()
			imgui.Text('\227\131\144\227\130\176\229\160\177\229\145\138\227\129\168\227\131\149\227\130\163\227\131\188\227\131\137\227\131\144\227\131\131\227\130\175\227\130\146\227\129\143\227\130\140\227\129\159\227\131\134\227\130\185\227\130\191\227\131\188\227\129\174\231\154\134\227\129\149\227\130\147:')
			imgui.Dummy({0, 4})
			-- TODO: fill optional URLs.  Empty string = no link.
			local _testers = {
				{'Zeratia', ''},
				{'Mod',     ''},
				{'Carver',  'www.catseyexi.com'},
				{'Emy',     ''},
				{'Sky',     ''},
			}
			for _, _e in ipairs(_testers) do
				_credit(_e[1], _e[2], _LIGHT_RED)
			end

			imgui.Dummy({0, 25})

			-- ----- Special Thanks -----
			-- Free-form section at the bottom for shoutouts, dedications,
			-- inside jokes, whatever you want.  Edit the lines below.
			-- TextWrapped honors the child's content width so long lines
			-- wrap to fit the panel.
			imgui.TextColored(_SECTION, '\227\130\185\227\131\154\227\130\183\227\131\163\227\131\171\227\130\181\227\131\179\227\130\175\227\130\185')
			imgui.Separator()
			imgui.Dummy({0, 8})

			imgui.PushTextWrapPos(imgui.GetWindowWidth() * 0.95)
			imgui.Dummy({10, 0}) imgui.SameLine()
			imgui.TextWrapped('\227\129\147\227\129\1741\229\185\180\227\128\129\233\131\168\229\177\139\227\129\171\227\129\147\227\130\130\227\129\163\227\129\166\227\129\147\227\129\174\227\131\151\227\131\173\227\130\184\227\130\167\227\130\175\227\131\136\227\130\146\233\128\178\227\130\129\227\130\139\231\167\129\227\130\146\232\166\139\229\174\136\227\129\163\227\129\166\227\129\143\227\130\140\227\129\159\229\174\182\230\151\143\227\129\168\229\143\139\228\186\186\227\129\159\227\129\161\227\129\184\227\128\130\227\130\179\227\131\188\227\131\137\227\129\171\229\159\139\227\130\130\227\130\140\227\129\159\233\149\183\227\129\132\230\153\130\233\150\147\227\129\174\227\129\130\227\129\132\227\129\160\227\130\130\227\128\129\229\163\176\227\130\146\227\129\139\227\129\145\227\129\166\227\129\143\227\130\140\227\128\129\233\163\159\228\186\139\227\129\171\233\128\163\227\130\140\229\135\186\227\129\151\227\129\166\227\129\143\227\130\140\227\128\129\229\164\156\230\155\180\227\129\139\227\129\151\227\130\132\227\131\129\227\131\163\227\131\131\227\131\136\227\130\166\227\130\163\227\131\179\227\131\137\227\130\166\227\129\174\231\139\172\231\153\189\227\129\171\228\187\152\227\129\141\229\144\136\227\129\163\227\129\166\227\129\143\227\130\140\227\129\190\227\129\151\227\129\159\227\128\130\227\129\130\227\130\138\227\129\140\227\129\168\227\129\134\227\128\130')

			imgui.Dummy({0, 12})

			imgui.Dummy({10, 0}) imgui.SameLine()
			imgui.TextWrapped('\230\156\128\229\190\140\227\129\171\231\136\182\227\129\184\227\128\130\229\174\140\230\136\144\227\129\151\227\129\159\229\167\191\227\130\146\232\166\139\227\129\155\227\130\137\227\130\140\227\129\170\227\129\139\227\129\163\227\129\159\227\129\147\227\129\168\227\129\140\229\191\131\230\174\139\227\130\138\227\129\167\227\129\153\227\128\130\227\129\132\227\129\164\227\130\130\227\129\157\227\129\134\227\129\160\227\129\163\227\129\159\227\130\136\227\129\134\227\129\171\227\128\129\229\150\156\227\130\147\227\129\167\227\128\129\232\170\135\227\130\138\227\129\171\230\128\157\227\129\163\227\129\166\227\129\143\227\130\140\227\129\159\227\129\175\227\129\154\227\129\167\227\129\153\227\128\130\228\188\154\227\129\132\227\129\159\227\129\132\227\129\167\227\129\153\227\128\130')
			imgui.PopTextWrapPos()
			
			imgui.Dummy({0, 24})
			imgui.EndChild()
			imgui.EndTabItem()
		end

		imgui.EndTabBar()
	end

	imgui.End()
	PopWindowStyle()

	-- ----------------------------------------------------------------
	-- Colorset Save / Load popups.  Centered on screen, fixed size,
	-- no title bar, opaque black background, ImGui-orange buttons.
	-- The Load popup's file list lives in a scrollable child so a
	-- long folder doesn't push the buttons off-screen.  Dismissed
	-- only via the Save / Load action, Cancel, or Escape  clicking
	-- outside is intentionally a no-op.
	-- ----------------------------------------------------------------
	local popupFlags = bit.bor(
		ImGuiWindowFlags_NoDecoration,
		ImGuiWindowFlags_NoTitleBar,
		ImGuiWindowFlags_NoMove,
		ImGuiWindowFlags_NoSavedSettings)

	-- Opaque-black bg + coral buttons (#D45447 = 0.831,0.329,0.278).
	local function pushPopupStyle()
		imgui.PushStyleColor(ImGuiCol_WindowBg,      {0,     0,     0,     1.0})
		imgui.PushStyleColor(ImGuiCol_ChildBg,       {0,     0,     0,     1.0})
		imgui.PushStyleColor(ImGuiCol_Button,        {0.831, 0.329, 0.278, 1.0})
		imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.929, 0.420, 0.353, 1.0})
		imgui.PushStyleColor(ImGuiCol_ButtonActive,  {0.700, 0.250, 0.200, 1.0})
	end
	local function popPopupStyle() imgui.PopStyleColor(5) end

	local _disp   = imgui.GetIO().DisplaySize
	local _cx, _cy = _disp.x * 0.5, _disp.y * 0.5

	if set.colorIO.exportOpen then
		imgui.SetNextWindowPos({_cx, _cy}, ImGuiCond_Always, {0.5, 0.5})
		imgui.SetNextWindowSize({440, 130}, ImGuiCond_Always)
		pushPopupStyle()
		if imgui.Begin('##fc_export', true, popupFlags) then
			imgui.Text('\227\131\149\227\130\161\227\130\164\227\131\171\229\144\141:')
			imgui.PushItemWidth(-1)                      -- fill the popup width
			imgui.InputText('##fc_export_name', set.colorIO.exportName, 64)
			imgui.PopItemWidth()
			imgui.Spacing()
			if imgui.Button('\228\191\157\229\173\152##fc_export_save', {80, 0}) then
				local skipKeys = {'combat', 'combatspell', 'cexi'}
				local payload  = {}
				for k, v in pairs(allSettings.colors) do
					if not utils.FindInStringTable(k, skipKeys, 0) then
						payload[k] = v
					end
				end
				utils.ExportColors(addon.path, set.colorIO.exportName[1], payload)
				set.colorIO.exportOpen = false
			end
			imgui.SameLine()
			if imgui.Button('\227\130\173\227\131\163\227\131\179\227\130\187\227\131\171##fc_export_cancel', {80, 0}) then
				set.colorIO.exportOpen = false
			end
			if imguiWrap.GetKeyDown(1) then     -- Escape
				set.colorIO.exportOpen = false
			end
		end
		imgui.End()
		popPopupStyle()
	end

	if set.colorIO.importOpen then
		imgui.SetNextWindowPos({_cx, _cy}, ImGuiCond_Always, {0.5, 0.5})
		imgui.SetNextWindowSize({440, 400}, ImGuiCond_Always)
		pushPopupStyle()
		if imgui.Begin('##fc_import', true, popupFlags) then
			local files = set.colorIO.importFiles
			imgui.Text('\227\130\171\227\131\169\227\131\188\227\130\187\227\131\131\227\131\136\227\131\149\227\130\161\227\130\164\227\131\171\227\130\146\233\129\184\230\138\158:')
			-- Reserve the bottom row of the popup for the buttons:
			-- list height = (whatever vertical space is left) - one row
			-- for the buttons - a small spacing gap.  Negative Y in
			-- BeginChild's size means "fill remaining minus -Y px"; we
			-- compute the explicit amount so the buttons always fit.
			local _, availY = imgui.GetContentRegionAvail()
			local listH     = math.max(80, availY - 40)  -- 40 = one button row + gap
			imguiWrap.BeginChild('##fc_import_list', {0, listH}, true)
			if #files == 0 then
				imgui.TextDisabled('\239\188\136chatcolors/ \227\129\171\227\131\149\227\130\161\227\130\164\227\131\171\227\129\140\227\129\130\227\130\138\227\129\190\227\129\155\227\130\147\239\188\137')
			else
				for i, name in ipairs(files) do
					if imgui.Selectable(name, set.colorIO.importSelected == i) then
						set.colorIO.importSelected = i
					end
				end
			end
			imgui.EndChild()
			local hasSel = set.colorIO.importSelected > 0 and #files > 0
			if not hasSel then
				imgui.PushStyleColor(ImGuiCol_Button,        {0.35, 0.35, 0.35, 0.5})
				imgui.PushStyleColor(ImGuiCol_ButtonHovered, {0.35, 0.35, 0.35, 0.5})
				imgui.PushStyleColor(ImGuiCol_ButtonActive,  {0.35, 0.35, 0.35, 0.5})
			end
			if imgui.Button('\232\170\173\232\190\188##fc_import_load', {80, 0}) and hasSel then
				local fname = files[set.colorIO.importSelected]
				allSettings.colors = utils.ImportColors(addon.path, fname, allSettings.colors)
				SaveSettings()
				set.colorIO.importOpen = false
			end
			if not hasSel then imgui.PopStyleColor(3) end
			imgui.SameLine()
			if imgui.Button('\227\130\173\227\131\163\227\131\179\227\130\187\227\131\171##fc_import_cancel', {80, 0}) then
				set.colorIO.importOpen = false
			end
			if imguiWrap.GetKeyDown(1) then     -- Escape
				set.colorIO.importOpen = false
			end
		end
		imgui.End()
		popPopupStyle()
	end
end

return M
