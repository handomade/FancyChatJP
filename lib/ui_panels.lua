-- lib/ui_panels.lua  draw_guideme() (wiki walkthrough viewer) and
-- draw_notepad() (per-character notes, max 10).

require('common')
local imgui     = require('imgui')
local imguiWrap = require('imguiWrap')
local http      = require('socket.http')
local utils     = require('utils')
local help      = require('help')
local state     = require('lib.state')

local fcw         = state.fcw
local ro          = state.ro
local allSettings = state.allSettings

local M = {}

-- Detect Cloudflare anti-bot interstitials by ANY of several markers.
-- Each is independently sufficient, so a future change to one still
-- leaves the others tripping the check.
--   cdn-cgi/challenge   : the URL prefix Cloudflare reserves for
--                         bot-mitigation pages and scripts; not used
--   _cf_chl_ / cf-chl   : challenge-state JS variables/cookies.
--                         Present in every challenge variant
--                         regardless of which UI they show.
--   challenges.cloudflare.com : domain of the challenge iframe widget.
--   "Just a moment"     : legacy interstitial title.
--   "Checking your browser" / "Verifying you are human" :
--                         human-facing text from older / newer
--                         challenge pages.
local function is_cloudflare_challenge(body)
	return body:find('cdn-cgi/challenge',         1, true) ~= nil
		or body:find('_cf_chl_',                  1, true) ~= nil
		or body:find('cf-chl',                    1, true) ~= nil
		or body:find('challenges.cloudflare.com', 1, true) ~= nil
		or body:find('Just a moment',             1, true) ~= nil
		or body:find('Checking your browser',     1, true) ~= nil
		or body:find('Verifying you are human',   1, true) ~= nil
end

function M.draw_guideme()
	if not (fcw[1].GuideMeOpened[1] and not fcw[1].GuideMeClosedTmp) then
		return
	end

	if fcw[1].isHiddenGUI then utils.ImguiVis(true) end

	local GuideMeW = allSettings.UseHalfLength[1] and fcw[1].BG_W / 2 or fcw[1].BG_W
	local GuideMeH = fcw[1].BG_H + 100
	local windowFlags

	if fcw[1].GuideMeDocked then
		windowFlags = fcw[1].windowFlagsGuideMeDocked
		if allSettings.GuideMeSecondWindow[1] then
			imgui.SetNextWindowPos({ro.RectBG[2].settings.position_x, ro.RectBG[2].settings.position_y - GuideMeH})
		else
			imgui.SetNextWindowPos({ro.RectBG[1].settings.position_x, ro.RectBG[1].settings.position_y - GuideMeH})
		end
		imgui.SetNextWindowSize({GuideMeW, GuideMeH})
		imgui.SetNextWindowSizeConstraints({GuideMeW, GuideMeH}, {FLT_MAX, FLT_MAX})
	else
		imgui.SetNextWindowSizeConstraints({400, 200}, {FLT_MAX, FLT_MAX})
		windowFlags = fcw[1].windowFlagsGuideMe
	end

	PushWindowStyle()

	if imgui.Begin('FancyChat - GuideMe\239\188\136\229\174\159\233\168\147\231\154\132\239\188\137', fcw[1].GuideMeOpened, windowFlags) then
		if imguiWrap.IsWindowHovered(ImGuiHoveredFlags_RectOnly) then ResetAutoHideTimer() end

		imgui.PushItemWidth(imgui.GetWindowWidth() / 2 - 130)
		imgui.InputText('URL', fcw[1].GuideMeURL, 200,
			bit.bor(ImGuiInputTextFlags_CharsNoBlank, ImGuiInputTextFlags_AutoSelectAll))
		imgui.PopItemWidth()
		imgui.SameLine()

		if fcw[1].GuideMeURL[1] == '' then
			fcw[1].ErrorMsg = '> \228\184\138\227\129\174 URL \230\172\132\227\129\171 ffxiclopedia \227\129\190\227\129\159\227\129\175 bg-wiki \227\129\174\n  \227\131\159\227\131\131\227\130\183\227\131\167\227\131\179 / \227\130\175\227\130\168\227\130\185\227\131\136\232\167\163\232\170\172\227\131\154\227\131\188\227\130\184\227\130\146\232\178\188\227\129\163\227\129\166 [\232\170\173\232\190\188] \227\130\146\230\138\188\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132'
		end

		if imgui.Button('\232\170\173\232\190\188', {70, 0}) then
			if fcw[1].GuideMeURL[1] ~= '' then
				if fcw[1].GuideMeURL[1]:match('^[a-zA-Z][a-zA-Z%d+.-]*:')
					and (string.find(fcw[1].GuideMeURL[1], 'ffxiclopedia')
						or string.find(fcw[1].GuideMeURL[1], 'bg%-wiki')) then

					local response, status = http.request(fcw[1].GuideMeURL[1])

					if not response then
						fcw[1].ErrorMsg = '> \227\131\154\227\131\188\227\130\184\227\129\174\229\143\150\229\190\151\227\129\171\229\164\177\230\149\151\227\129\151\227\129\190\227\129\151\227\129\159\227\128\130\231\138\182\230\133\139:'..tostring(status or '\228\184\141\230\152\142')
						fcw[1].GuideMeWalkthrough = nil
					elseif is_cloudflare_challenge(response) then
						fcw[1].ErrorMsg = '> Cloudflare \227\129\174\227\131\156\227\131\131\227\131\136\229\175\190\231\173\150\227\129\167\227\131\150\227\131\173\227\131\131\227\130\175\227\129\149\227\130\140\227\129\190\227\129\151\227\129\159\227\128\130\n  VPN \227\130\146\229\136\135\227\130\139\227\129\139\227\128\129bg-wiki.com \229\129\180\227\129\174\229\144\140\227\129\152\232\168\152\228\186\139\227\130\146\232\169\166\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130'
						fcw[1].GuideMeWalkthrough = nil
					else
						fcw[1].GuideMeWalkthrough = response:match('(<h[1-3]>.-Walkthrough.-</h[1-3]>.-<div class="printfooter">)')

						if not fcw[1].GuideMeWalkthrough then
							fcw[1].GuideMeWalkthrough = response:match('(<h[1-3]>.-Walkthrough.-</h[1-3]>.-<div class="page%-footer">)')
						end

						if not fcw[1].GuideMeWalkthrough then
							fcw[1].GuideMeWalkthrough = response:match('(>Obtained From.-</th>.-<div class="printfooter">)')
							if fcw[1].GuideMeWalkthrough then
								fcw[1].GuideMeWalkthrough = '<h2>How to Obtain</h2>\n<table style="width: 100%; max-width: 788px;" class="sortable item"><tbody><tr>'
									..fcw[1].GuideMeWalkthrough:gsub('>Obtained From.-</tr>', '')
							end
						end

						if not fcw[1].GuideMeWalkthrough then
							fcw[1].GuideMeWalkthrough = response:match('(>Purchased From.-</th>.-<div class="printfooter">)')
							if fcw[1].GuideMeWalkthrough then
								fcw[1].GuideMeWalkthrough = '<h2>How to Obtain</h2>\n<table style="width: 100%; max-width: 788px;" class="sortable item"><tbody><tr>'
									..fcw[1].GuideMeWalkthrough:gsub('>Purchased From.-</tr>', '')
							end
						end

						if not fcw[1].GuideMeWalkthrough then
							fcw[1].GuideMeWalkthrough = response:match('(<h[1-3]>.-How to Obtain.-</h[1-3]>.-<div class="page%-footer">)')
						end

						if not fcw[1].GuideMeWalkthrough then
							fcw[1].ErrorMsg = '> Walkthrough \227\130\187\227\130\175\227\130\183\227\131\167\227\131\179\227\129\140\232\166\139\227\129\164\227\129\139\227\130\138\227\129\190\227\129\155\227\130\147\227\128\130\n  \227\131\159\227\131\131\227\130\183\227\131\167\227\131\179 / \227\130\175\227\130\168\227\130\185\227\131\136\227\129\174\232\167\163\232\170\172\227\131\154\227\131\188\227\130\184\227\129\167\227\129\174\227\129\191\229\139\149\228\189\156\227\129\151\227\129\190\227\129\153\227\128\130'
							fcw[1].GuideMeWalkthrough = nil
						else
							fcw[1].GuideMeWalkthrough = utils.GetWalkthrough(fcw[1].GuideMeWalkthrough)
							local start = string.find(fcw[1].GuideMeWalkthrough, '%[Walkthrough%]')
							if not start then start = string.find(fcw[1].GuideMeWalkthrough, '%[How to Obtain%]') end
							fcw[1].GuideMeWalkthrough = string.sub(fcw[1].GuideMeWalkthrough, start)
						end
					end
				else
					fcw[1].ErrorMsg = '> URL \227\129\140\228\184\141\230\173\163\227\129\167\227\129\153\227\128\130https:// \227\129\167\229\167\139\227\129\190\227\130\139\n  ffxiclopedia \227\129\190\227\129\159\227\129\175 bg-wiki \227\129\174\227\131\154\227\131\188\227\130\184\227\129\171\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132'
					fcw[1].GuideMeWalkthrough = nil
				end
			else
				fcw[1].ErrorMsg = '> \228\184\138\227\129\174 URL \230\172\132\227\129\171 ffxiclopedia \227\129\190\227\129\159\227\129\175 bg-wiki \227\129\174\n  \227\131\159\227\131\131\227\130\183\227\131\167\227\131\179 / \227\130\175\227\130\168\227\130\185\227\131\136\232\167\163\232\170\172\227\131\154\227\131\188\227\130\184\227\130\146\232\178\188\227\129\163\227\129\166 [\232\170\173\232\190\188] \227\130\146\230\138\188\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132'
				fcw[1].GuideMeWalkthrough = nil
			end
		end

		imgui.SameLine() imgui.Dummy({10, 0}) imgui.SameLine()
		imgui.Text('\230\150\135\229\173\151\227\130\181\227\130\164\227\130\186') imgui.SameLine()

		if imgui.ArrowButton('#DecreaseFontScale', ImGuiDir_Down) then
			if allSettings.GuideMeFontScale > 0.5 then
				allSettings.GuideMeFontScale = allSettings.GuideMeFontScale - 0.05
			end
		end
		imgui.SameLine()
		if imgui.ArrowButton('#IncreaseFontScale', ImGuiDir_Up) then
			if allSettings.GuideMeFontScale < 1.5 then
				allSettings.GuideMeFontScale = allSettings.GuideMeFontScale + 0.05
			end
		end

		imgui.SameLine() imgui.Text('[x'..string.format('%.2f', allSettings.GuideMeFontScale)..']')
		imgui.SameLine() imgui.Dummy({10, 0}) imgui.SameLine()

		if fcw[1].GuideMeDocked then
			if imgui.Button('\232\167\163\233\153\164', {70, 0}) then fcw[1].GuideMeDocked = false end
		else
			if imgui.Button('\229\155\186\229\174\154', {70, 0}) then fcw[1].GuideMeDocked = true end
		end

		imguiWrap.BeginChild('GuideMe child',
			{imgui.GetWindowWidth() * 0.983, (imgui.GetWindowHeight() - 70) * 0.983}, true)

		local IWwindowfontG = imguiWrap.SetWindowFontScale(allSettings.GuideMeFontScale)
		imgui.PushTextWrapPos(imgui.GetWindowWidth() * 0.96)
		if fcw[1].GuideMeWalkthrough then
			imgui.TextUnformatted(fcw[1].GuideMeWalkthrough, #fcw[1].GuideMeWalkthrough)
		elseif fcw[1].ErrorMsg then
			imgui.TextUnformatted(fcw[1].ErrorMsg)
		end
		imgui.PopTextWrapPos()
		if IWwindowfontG then imgui.PopFont() end
		imgui.EndChild()
		imgui.End()
	end
	PopWindowStyle()
	if fcw[1].isHiddenGUI then utils.ImguiVis(false) end
end

function M.draw_notepad()
	if not (fcw[1].NotepadOpened[1] and not fcw[1].NotepadClosedTmp) then
		return
	end

	if fcw[1].isHiddenGUI then utils.ImguiVis(true) end

	local GuideMeW = allSettings.UseHalfLength[1] and fcw[1].BG_W / 2 or fcw[1].BG_W
	local GuideMeH = fcw[1].BG_H + 100
	local windowFlags

	if fcw[1].NotepadDocked then
		windowFlags = fcw[1].windowFlagsGuideMeDocked
		if allSettings.GuideMeSecondWindow[1] then
			imgui.SetNextWindowPos({ro.RectBG[2].settings.position_x, ro.RectBG[2].settings.position_y - GuideMeH})
		else
			imgui.SetNextWindowPos({ro.RectBG[1].settings.position_x, ro.RectBG[1].settings.position_y - GuideMeH})
		end
		imgui.SetNextWindowSize({GuideMeW, GuideMeH})
		imgui.SetNextWindowSizeConstraints({GuideMeW, GuideMeH}, {FLT_MAX, FLT_MAX})
	else
		imgui.SetNextWindowSizeConstraints({550, 200}, {FLT_MAX, FLT_MAX})
		windowFlags = fcw[1].windowFlagsGuideMe
	end

	PushWindowStyle()

	if imgui.Begin('FancyChat - \227\131\161\227\131\162\229\184\179\239\188\136\229\174\159\233\168\147\231\154\132\239\188\137', fcw[1].NotepadOpened, windowFlags) then
		if imguiWrap.IsWindowHovered(ImGuiHoveredFlags_RectOnly) then ResetAutoHideTimer() end

		AddTooltip('\227\131\161\227\131\162\227\129\175\230\156\128\229\164\16710\228\187\182\227\129\167\227\129\153\227\128\130\n- \227\131\134\227\130\173\227\130\185\227\131\136\230\172\132\227\129\139\227\130\137\230\137\139\229\139\149\232\191\189\229\138\160\227\129\167\227\129\141\227\129\190\227\129\153\227\128\130\n- \227\131\129\227\131\163\227\131\131\227\131\136\232\161\140\227\130\146 Shift+\227\130\175\227\131\170\227\131\131\227\130\175\227\129\153\227\130\139\227\129\168\227\128\129\227\129\157\227\129\174\232\161\140\227\130\146\227\131\161\227\131\162\227\129\168\227\129\151\227\129\166\228\191\157\229\173\152\227\129\151\227\129\190\227\129\153\227\128\130', 0)
		imgui.SameLine() imgui.SetCursorPosY(imgui.GetCursorPosY() - 4)

		imgui.PushItemWidth(imgui.GetWindowWidth() - 316)
		imgui.InputText('##NoteInput', fcw[1].Note, 300, bit.bor(ImGuiInputTextFlags_AutoSelectAll))
		imgui.SameLine()

		if imgui.Button('\232\191\189\229\138\160', {100, 0}) then
			if #allSettings.Notes < 10 and #fcw[1].Note[1] > 0 then
				table.insert(allSettings.Notes, fcw[1].Note[1])
				fcw[1].Note = T{''}
				SaveSettings()
			end
		end
		imgui.SameLine()
		imgui.Text(string.format('[%02d/10]', #allSettings.Notes))
		imgui.SameLine() imgui.Dummy({0, 0}) imgui.SameLine()

		if fcw[1].NotepadDocked then
			if imgui.Button('\232\167\163\233\153\164', {70, 0}) then fcw[1].NotepadDocked = false end
		else
			if imgui.Button('\229\155\186\229\174\154', {70, 0}) then fcw[1].NotepadDocked = true end
		end

		local font = imgui.GetFont()
		local fontSize = font.FontSize or font.LegacySize
		local R = {}

		for i = 1, #allSettings.Notes do
			imguiWrap.BeginChild(
				'##Chat Window Child_'..tostring(i),
				{
					imgui.GetWindowWidth() - 110,
					fontSize + fontSize * math.floor(
						imgui.CalcTextSize(allSettings.Notes[i])
						/ (imgui.GetWindowWidth() - math.min(
							imgui.CalcTextSize(help.GetLongestWord(allSettings.Notes[i])),
							(imgui.GetWindowWidth() - 100) / 2))
					) + 16
				}, true)
			imgui.PushTextWrapPos(imgui.GetWindowWidth())
			imgui.TextWrapped(allSettings.Notes[i])
			imgui.PopTextWrapPos()
			imgui.EndChild()

			imgui.SameLine()
			if imgui.Button('X##Note'..tostring(i), {34, 34}) then
				table.insert(R, i)
			end
			imgui.SameLine()
			if imgui.Button('C##Note'..tostring(i), {34, 34}) then
				utils.SetClipboardText(allSettings.Notes[i])
			end
		end

		for R_i = 1, #R do
			table.remove(allSettings.Notes, R[R_i])
		end
		if #R > 0 then SaveSettings() end

		imgui.PopItemWidth()
		imgui.SameLine()
		imgui.End()
	end
	PopWindowStyle()
	
	if fcw[1].isHiddenGUI then utils.ImguiVis(false) end
end

return M
