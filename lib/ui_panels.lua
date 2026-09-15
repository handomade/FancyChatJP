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

local function guideme_url_ok(url)
	if not url or url == '' then return false end
	if not url:match('^[a-zA-Z][a-zA-Z%d+.-]*:') then return false end
	return string.find(url, 'ffxiclopedia', 1, true)
		or string.find(url, 'bg-wiki', 1, true)
		or string.find(url, 'wiki.ffo.jp', 1, true)
end

local function parse_guideme_html(response, url)
	if url and string.find(url, 'wiki.ffo.jp', 1, true) then
		response = utils.FfoHtmlToUtf8(response)
	end
	if url and url:find('search%.cgi') then
		return utils.FormatFfoSearchPage(utils.FfoSearchQueryFromUrl(url), response)
	end
	local chunk = response:match('(<h[1-3]>.-Walkthrough.-</h[1-3]>.-<div class="printfooter">)')
	if not chunk then
		chunk = response:match('(<h[1-3]>.-Walkthrough.-</h[1-3]>.-<div class="page%-footer">)')
	end
	if not chunk then
		chunk = response:match('(>Obtained From.-</th>.-<div class="printfooter">)')
		if chunk then
			chunk = '<h2>How to Obtain</h2>\n<table style="width: 100%; max-width: 788px;" class="sortable item"><tbody><tr>'
				..chunk:gsub('>Obtained From.-</tr>', '')
		end
	end
	if not chunk then
		chunk = response:match('(>Purchased From.-</th>.-<div class="printfooter">)')
		if chunk then
			chunk = '<h2>How to Obtain</h2>\n<table style="width: 100%; max-width: 788px;" class="sortable item"><tbody><tr>'
				..chunk:gsub('>Purchased From.-</tr>', '')
		end
	end
	if not chunk then
		chunk = response:match('(<h[1-3]>.-How to Obtain.-</h[1-3]>.-<div class="page%-footer">)')
	end

	if chunk then
		local text = utils.GetWalkthrough(chunk)
		local start = string.find(text, '%[Walkthrough%]')
		if not start then start = string.find(text, '%[How to Obtain%]') end
		if start then text = string.sub(text, start) end
		if text and text:match('%S') then return text end
	end

	if string.find(url, 'wiki.ffo.jp', 1, true) then
		local text = utils.GetFfoWikiBody(response, url, http.request)
		if text then return text end
	end

	return utils.GetWikiArticleBody(response)
end

local function load_guideme(url, push_hist)
	if not url or url == '' then
		fcw[1].ErrorMsg = '> \228\184\138\227\129\174 URL \230\172\132\227\129\171 ffxiclopedia / bg-wiki / wiki.ffo.jp \227\129\174\n  \227\131\159\227\131\131\227\130\183\227\131\167\227\131\179 / \227\130\175\227\130\168\227\130\185\227\131\136\232\167\163\232\170\172\227\131\154\227\131\188\227\130\184\227\130\146\232\178\188\227\129\163\227\129\166 [\232\170\173\232\190\188] \227\130\146\230\138\188\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132'
		return false
	end
	url = url:gsub('#.*$', '')
	if not guideme_url_ok(url) then
		fcw[1].ErrorMsg = '> URL \227\129\140\228\184\141\230\173\163\227\129\167\227\129\153\227\128\130https:// \227\129\167\229\167\139\227\129\190\227\130\139\n  ffxiclopedia / bg-wiki / wiki.ffo.jp \227\129\174\227\131\154\227\131\188\227\130\184\227\129\171\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132'
		return false
	end

	local old_url  = fcw[1].GuideMeURL[1]
	local old_body = fcw[1].GuideMeWalkthrough
	local response, status = http.request(url)

	if not response then
		fcw[1].ErrorMsg = '> \227\131\154\227\131\188\227\130\184\227\129\174\229\143\150\229\190\151\227\129\171\229\164\177\230\149\151\227\129\151\227\129\190\227\129\151\227\129\159\227\128\130\231\138\182\230\133\139:'..tostring(status or '\228\184\141\230\152\142')
		return false
	end
	if is_cloudflare_challenge(response) then
		fcw[1].ErrorMsg = '> Cloudflare \227\129\174\227\131\156\227\131\131\227\131\136\229\175\190\231\173\150\227\129\167\227\131\150\227\131\173\227\131\131\227\130\175\227\129\149\227\130\140\227\129\190\227\129\151\227\129\159\227\128\130\n  VPN \227\130\146\229\136\135\227\130\139\227\129\139\227\128\129bg-wiki.com \229\129\180\227\129\174\229\144\140\227\129\152\232\168\152\228\186\139\227\130\146\232\169\166\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132\227\128\130'
		return false
	end

	local text = parse_guideme_html(response, url)
	if not text then
		fcw[1].ErrorMsg = '> Walkthrough \227\130\187\227\130\175\227\130\183\227\131\167\227\131\179\227\129\140\232\166\139\227\129\164\227\129\139\227\130\138\227\129\190\227\129\155\227\130\147\227\128\130\n  \227\131\159\227\131\131\227\130\183\227\131\167\227\131\179 / \227\130\175\227\130\168\227\130\185\227\131\136\227\129\174\232\167\163\232\170\172\227\131\154\227\131\188\227\130\184\227\129\167\227\129\174\227\129\191\229\139\149\228\189\156\227\129\151\227\129\190\227\129\153\227\128\130'
		return false
	end

	if push_hist and old_body and old_url and old_url ~= '' and old_url ~= url then
		local hist = fcw[1].GuideMeHistory
		if not hist then
			hist = {}
			fcw[1].GuideMeHistory = hist
		end
		hist[#hist + 1] = { url = old_url, body = old_body }
		if #hist > 20 then table.remove(hist, 1) end
	end

	fcw[1].GuideMeURL[1] = url
	fcw[1].GuideMeWalkthrough = text
	fcw[1].ErrorMsg = ''
	return true
end

M.load_url = load_guideme

local LINK_COL = {0.40, 0.68, 1.00, 1.0}

-- Draw GuideMe body with in-line wiki hyperlinks.  Click loads the
-- target page inside GuideMe (see load_guideme).  Lines are not wrapped
-- so a horizontal scrollbar can show when text is wider than the panel.
local function draw_guideme_rich(body, base_url)
	local runs = utils.ParseGuideMeRuns(body)
	local at_line_start = true

	local function place()
		if not at_line_start then imgui.SameLine(0, 0) end
	end

	local function emit_plain(s)
		imgui.TextUnformatted(s, #s)
	end

	local function emit_link_chunk(label, url)
		imgui.PushStyleColor(ImGuiCol_Text, LINK_COL)
		imgui.TextUnformatted(label, #label)
		imgui.PopStyleColor()
		if imgui.IsItemHovered() then
			imgui.SetTooltip(url)
			if imgui.IsMouseClicked(0) then
				fcw[1].GuideMePendingUrl = url
			end
		end
	end

	local function emit_run(s, as_link, url)
		if not s or s == '' then return end
		place()
		if as_link then emit_link_chunk(s, url) else emit_plain(s) end
		at_line_start = false
	end

	for _, run in ipairs(runs) do
		local text = run.s or ''
		if run.t == 'link' then
			local url = utils.ResolveWikiHref(run.u, base_url)
			if url and url:find('^https?://') and guideme_url_ok(url) then
				emit_run(text, true, url)
			else
				emit_run(text, false)
			end
		else
			local start = 1
			while true do
				local nl = text:find('\n', start, true)
				local piece = nl and text:sub(start, nl - 1) or text:sub(start)
				piece = piece:gsub('\r', '')
				if piece ~= '' then emit_run(piece, false) end
				if not nl then break end
				imgui.NewLine()
				at_line_start = true
				start = nl + 1
			end
		end
	end
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
			fcw[1].ErrorMsg = '> \228\184\138\227\129\174 URL \230\172\132\227\129\171 ffxiclopedia / bg-wiki / wiki.ffo.jp \227\129\174\n  \227\131\159\227\131\131\227\130\183\227\131\167\227\131\179 / \227\130\175\227\130\168\227\130\185\227\131\136\232\167\163\232\170\172\227\131\154\227\131\188\227\130\184\227\130\146\232\178\188\227\129\163\227\129\166 [\232\170\173\232\190\188] \227\130\146\230\138\188\227\129\151\227\129\166\227\129\143\227\129\160\227\129\149\227\129\132'
		end

		if imgui.Button('\232\170\173\232\190\188', {70, 0}) then
			load_guideme(fcw[1].GuideMeURL[1], true)
		end
		imgui.SameLine()
		do
			local hist = fcw[1].GuideMeHistory
			local can_back = hist and #hist > 0
			if not can_back then imgui.PushStyleVar(ImGuiStyleVar_Alpha, 0.45) end
			local hit_back = imgui.Button('\230\136\187\227\130\139', {50, 0})
			if not can_back then imgui.PopStyleVar() end
			if hit_back and can_back then
				local prev = table.remove(hist)
				fcw[1].GuideMeURL[1] = prev.url or ''
				fcw[1].GuideMeWalkthrough = prev.body
				fcw[1].ErrorMsg = ''
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
			{imgui.GetWindowWidth() * 0.983, (imgui.GetWindowHeight() - 70) * 0.983},
			true,
			ImGuiWindowFlags_HorizontalScrollbar,
			ImGuiChildFlags_HorizontalScrollbar or 0)

		local IWwindowfontG = imguiWrap.SetWindowFontScale(allSettings.GuideMeFontScale)
		-- Negative wrap pos = do not wrap, so wide lines can h-scroll.
		imgui.PushTextWrapPos(-1)
		if fcw[1].GuideMeWalkthrough then
			if string.find(fcw[1].GuideMeWalkthrough, '\30', 1, true) then
				draw_guideme_rich(fcw[1].GuideMeWalkthrough, fcw[1].GuideMeURL[1])
			else
				imgui.TextUnformatted(fcw[1].GuideMeWalkthrough, #fcw[1].GuideMeWalkthrough)
			end
		elseif fcw[1].ErrorMsg then
			imgui.TextUnformatted(fcw[1].ErrorMsg)
		end
		imgui.PopTextWrapPos()
		if IWwindowfontG then imgui.PopFont() end
		imgui.EndChild()
		imgui.End()
	end
	if fcw[1].GuideMePendingUrl then
		local u = fcw[1].GuideMePendingUrl
		fcw[1].GuideMePendingUrl = nil
		load_guideme(u, true)
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
