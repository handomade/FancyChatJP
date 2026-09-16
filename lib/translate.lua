-- lib/translate.lua  ASCII chat -> Japanese, with a local dictionary.
-- Network calls go through curl.exe in the background so text_in never
-- stalls.  Japanese UI strings are decimal-escaped by _escape_lua_utf8.py.

require('common')
local state = require('lib.state')

local allSettings = state.allSettings
local par         = state.par
local fcw         = state.fcw

local M = {}

local FW_OPEN  = '\239\189\155' -- fullwidth {
local FW_CLOSE = '\239\189\157' -- fullwidth }
local FW_COLON = '\239\188\154' -- fullwidth :

M.PROVIDERS = { 'MyMemory', 'DeepL', 'ChatGPT', 'Gemini' }

local dict = {}
local dict_count = 0
local dict_loaded = false
local zone_names = nil
local pending = {}
local inflight = {}
local next_id = 1
local last_err = ''
local MAX_INFLIGHT = 3
local MAX_PENDING = 40
local MAX_TRIES = 2
local PENDING_KEY = {} -- key -> job still waiting on the network
local PREFIX = '['..'\231\191\187\232\168\179'..'] ' -- [翻訳]  (defined early for waiters)

local function cfg_dir()
	return AshitaCore:GetInstallPath()..'\\config\\addons\\'..addon.name..'\\translate'
end

local function dict_path()
	return cfg_dir()..'\\dict.txt'
end

local function ensure_dir()
	os.execute('mkdir "'..cfg_dir()..'" 2>nul')
end

local function norm_key(s)
	s = tostring(s or '')
	s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	return s:lower()
end

local function is_ascii(s)
	if not s or s == '' then return false end
	for i = 1, #s do
		if s:byte(i) >= 128 then return false end
	end
	return true
end

local function strip_ffxi(s)
	s = s:gsub('\030.', '')
	s = s:gsub('\031.', '')
	s = s:gsub('\127.', '')
	s = s:gsub('\007', '')
	return s
end

local function json_escape(s)
	s = tostring(s or '')
	s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\r', '\\r'):gsub('\n', '\\n'):gsub('\t', '\\t')
	return s
end

local function utf8_cp(cp)
	cp = tonumber(cp) or 0
	if cp < 1 then return '' end
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 64), 0x80 + (cp % 64))
	elseif cp < 0x10000 then
		return string.char(
			0xE0 + math.floor(cp / 4096),
			0x80 + (math.floor(cp / 64) % 64),
			0x80 + (cp % 64))
	end
	return '?'
end

local function extract_json_string(blob, key)
	if not blob then return nil end
	local pat = '"'..key..'"%s*:%s*"'
	local _, j = blob:find(pat)
	if not j then return nil end
	local k = j + 1
	local out = {}
	while k <= #blob do
		local c = blob:sub(k, k)
		if c == '\\' then
			local n = blob:sub(k + 1, k + 1)
			if n == 'n' then out[#out + 1] = '\n'; k = k + 2
			elseif n == 't' then out[#out + 1] = '\t'; k = k + 2
			elseif n == 'r' then out[#out + 1] = '\r'; k = k + 2
			elseif n == '"' or n == '\\' or n == '/' then out[#out + 1] = n; k = k + 2
			elseif n == 'u' then
				local hex = blob:sub(k + 2, k + 5)
				local cp = tonumber(hex, 16)
				if cp then out[#out + 1] = utf8_cp(cp) end
				k = k + 6
			else
				out[#out + 1] = n
				k = k + 2
			end
		elseif c == '"' then
			break
		else
			out[#out + 1] = c
			k = k + 1
		end
	end
	local t = table.concat(out)
	t = t:gsub('^%s+', ''):gsub('%s+$', '')
	if t == '' then return nil end
	return t
end

local function slash(path)
	return (path:gsub('\\', '/'))
end

function M.load_dict()
	dict = {}
	dict_count = 0
	dict_loaded = true
	local f = io.open(dict_path(), 'rb')
	if not f then return end
	for line in f:lines() do
		if line:sub(1, 1) ~= '#' and line:find('\t', 1, true) then
			local src, dst = line:match('^(.-)\t(.*)$')
			if src and dst and src ~= '' and dst ~= '' then
				dict[norm_key(src)] = dst
				dict_count = dict_count + 1
			end
		end
	end
	f:close()
end

local function save_entry(src, dst)
	ensure_dir()
	local key = norm_key(src)
	if dict[key] then
		if dict[key] == dst then return end
		dict[key] = dst
		local f = io.open(dict_path(), 'wb')
		if not f then return end
		f:write('# FancyChatJP translate dictionary\n')
		for k, v in pairs(dict) do
			f:write(k..'\t'..v:gsub('\t', ' ')..'\n')
		end
		f:close()
		return
	end
	dict[key] = dst
	dict_count = dict_count + 1
	local f = io.open(dict_path(), 'ab')
	if not f then return end
	f:write(key..'\t'..dst:gsub('\t', ' ')..'\n')
	f:close()
end

function M.dict_count()
	if not dict_loaded then M.load_dict() end
	return dict_count
end

function M.last_error()
	return last_err
end

function M.clear_dict()
	dict = {}
	dict_count = 0
	ensure_dir()
	local f = io.open(dict_path(), 'w')
	if f then
		f:write('# FancyChatJP translate dictionary\n')
		f:close()
	end
end

function M.open_dict_folder()
	ensure_dir()
	os.execute('start "" "'..cfg_dir()..'"')
end

local function load_zones()
	if zone_names then return zone_names end
	zone_names = {}
	local p = io.popen('dir /b /ad "'..addon.path..'\\maps" 2>nul')
	if p then
		for name in p:lines() do
			if is_ascii(name) and #name >= 4 then
				zone_names[#zone_names + 1] = name
			end
		end
		p:close()
	end
	table.sort(zone_names, function(a, b) return #a > #b end)
	return zone_names
end

local function replace_ci(s, needle, repl)
	if not needle or needle == '' then return s end
	local l = s:lower()
	local n = needle:lower()
	local nlen = #needle
	local out = {}
	local i = 1
	while true do
		local at = l:find(n, i, true)
		if not at then
			out[#out + 1] = s:sub(i)
			break
		end
		local before_ok = (at == 1) or not s:sub(at - 1, at - 1):match('[%a%d]')
		local after_i = at + nlen
		local after_ok = (after_i > #s) or not s:sub(after_i, after_i):match('[%a%d]')
		if before_ok and after_ok then
			out[#out + 1] = s:sub(i, at - 1)
			out[#out + 1] = repl
			i = after_i
		else
			out[#out + 1] = s:sub(i, at)
			i = at + 1
		end
	end
	return table.concat(out)
end

-- Placeholders that look like codes so MT engines leave them alone.
-- [[P1]] was turned into [[P 1]] / [[Z 1]] and never restored.
local function protect_names(s)
	local map = { P = {}, Z = {} }
	if not allSettings.TranslateProtectNames or not allSettings.TranslateProtectNames[1] then
		return s, map
	end
	local names = {}
	if par.party_names then
		for i = 1, #par.party_names do
			local n = par.party_names[i]
			if n and n ~= '' and is_ascii(n) and #n >= 2 then
				names[#names + 1] = n
			end
		end
	end
	local me = fcw[1] and fcw[1].PlayerName
	if me and me ~= '---' and is_ascii(me) then names[#names + 1] = me end
	table.sort(names, function(a, b) return #a > #b end)
	local seen = {}
	local idx = 0
	for i = 1, #names do
		local n = names[i]
		local nk = n:lower()
		if not seen[nk] then
			seen[nk] = true
			idx = idx + 1
			local tok = 'QQQ'..idx..'QQQ'
			local nexts = replace_ci(s, n, tok)
			if nexts ~= s then
				map.P[idx] = n
				s = nexts
			else
				idx = idx - 1
			end
		end
	end
	local zones = load_zones()
	local zidx = 0
	for i = 1, #zones do
		local z = zones[i]
		if s:lower():find(z:lower(), 1, true) then
			zidx = zidx + 1
			local tok = 'ZZZ'..zidx..'ZZZ'
			local nexts = replace_ci(s, z, tok)
			if nexts ~= s then
				map.Z[zidx] = z
				s = nexts
			else
				zidx = zidx - 1
			end
		end
	end
	return s, map
end

local function restore_kind(s, letter, names)
	if not s or not names then return s end
	local function repl(n)
		local i = tonumber(n)
		return (i and names[i]) or ''
	end
	-- [[P1]] [[P 1]] [[ P 1 ]] and the same with () [] leftover
	s = s:gsub('%[%[%s*'..letter..'%s*(%d+)%s*%]%]', repl)
	s = s:gsub('%[%s*'..letter..'%s*(%d+)%s*%]', repl)
	return s
end

local function restore_names(s, map)
	if not s then return s end
	map = map or { P = {}, Z = {}, K = {} }
	s = restore_kind(s, '[Pp]', map.P)
	s = restore_kind(s, '[Zz]', map.Z)
	if map.P then
		s = s:gsub('[Qq][Qq][Qq]%s*(%d+)%s*[Qq][Qq][Qq]', function(n)
			local i = tonumber(n)
			return (i and map.P[i]) or ''
		end)
	end
	if map.Z then
		s = s:gsub('[Zz][Zz][Zz]%s*(%d+)%s*[Zz][Zz][Zz]', function(n)
			local i = tonumber(n)
			return (i and map.Z[i]) or ''
		end)
	end
	if map.K then
		s = s:gsub('[Kk][Kk][Kk]%s*(%d+)%s*[Kk][Kk][Kk]', function(n)
			local i = tonumber(n)
			return (i and map.K[i]) or ''
		end)
	end
	-- Leftover markup the engine invented (no matching name).
	s = s:gsub('%[%[%s*[PZpz]%s*%d+%s*%]%]', '')
	s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	return s
end

-- FFXI names are 2-16 letters per word, often with 0-3 spaces.
-- Length/word count is a heuristic, not a parser.
local function looks_like_speaker(left)
	if not left or left == '' then return false end
	if #left < 2 or #left > 28 then return false end
	local low = left:lower()
	if low == 'http' or low == 'https' or low == 'ftp' then return false end
	if low:find('addon', 1, true) then return false end
	if low == 'active bonus' or low == 'universal bonus' then return false end
	if left:find('[/%?!:,%.%d]') then return false end
	if not left:find('^[%a][%a%d%s%-\']*$') then return false end
	local words = 0
	for w in left:gmatch('%S+') do
		words = words + 1
		if #w < 2 or #w > 16 then return false end
		if not w:find('^[%a][%a%d%-\']*$') then return false end
	end
	if words < 1 or words > 4 then return false end
	return true
end

-- Returns ASCII body, keep-as-is prefix, brace map.  Prefix is the
-- original `{Name}` / `Name :` text that must stay on the [翻訳] line.
function M.extract(raw)
	if type(raw) ~= 'string' or raw == '' then return nil end
	local s = strip_ffxi(raw)
	s = s:gsub('^%s+', ''):gsub('%s+$', '')
	if s == '' then return nil end

	local keep = ''
	while true do
		if s:sub(1, #FW_OPEN) == FW_OPEN then
			local c = s:find(FW_CLOSE, 1, true)
			if not c then break end
			keep = keep .. s:sub(1, c + #FW_CLOSE - 1) .. ' '
			s = s:sub(c + #FW_CLOSE):gsub('^%s+', '')
		elseif s:sub(1, 1) == '{' then
			local c = s:find('}', 1, true)
			if not c then break end
			keep = keep .. s:sub(1, c) .. ' '
			s = s:sub(c + 1):gsub('^%s+', '')
		else
			break
		end
	end

	local fw = s:find(FW_COLON, 1, true)
	if fw then
		local left = s:sub(1, fw - 1):gsub('%s+$', ''):gsub('^%s+', '')
		if looks_like_speaker(left) or (left ~= '' and not left:find('[/%?]')) then
			keep = keep .. s:sub(1, fw + #FW_COLON - 1) .. ' '
			s = s:sub(fw + #FW_COLON):gsub('^%s+', '')
		end
	elseif not s:find('^%d+:%d+') then
		local a = s:find(':', 1, true)
		if a then
			local left = s:sub(1, a - 1):gsub('%s+$', ''):gsub('^%s+', '')
			if looks_like_speaker(left) then
				keep = keep .. left .. ' : '
				s = s:sub(a + 1):gsub('^%s+', '')
			end
		end
	end

	local kmap = {}
	local kidx = 0
	s = s:gsub(FW_OPEN..'(.-)'..FW_CLOSE, function(inner)
		kidx = kidx + 1
		kmap[kidx] = FW_OPEN .. inner .. FW_CLOSE
		return 'KKK'..kidx..'KKK'
	end)
	s = s:gsub('{(.-)}', function(inner)
		kidx = kidx + 1
		kmap[kidx] = '{' .. inner .. '}'
		return 'KKK'..kidx..'KKK'
	end)

	s = s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	if s == '' or not is_ascii(s) then return nil end
	if not s:find('%a') then return nil end
	if #s < 2 then return nil end
	return s, keep, kmap
end

local SKIP_MODES = {
	[0] = true, [8] = true, [128] = true,
	[190] = true, [191] = true, [206] = true,
}

local function skip_system_text(s)
	local l = (s or ''):lower()
	if l:find('loaded addon', 1, true) or l:find('unloaded addon', 1, true) then return true end
	if l:find('%[addon%]') then return true end
	if l:find('%[partyfinder%]', 1, true) then return true end
	if l:find('^%[[%a][%a%d_%.%-]*%]') then return true end
	if l:find('fancychat', 1, true) and l:find('version', 1, true) then return true end
	if l:find('addon:', 1, true) and l:find('version', 1, true) then return true end
	if l:find('arielfy', 1, true) then return true end
	return false
end

local function chat_mode_ok(lastmode, mode)
	if SKIP_MODES[tonumber(mode) or -1] then return false end
	if not lastmode or lastmode == 'filtered' or lastmode == 'unknown' then return false end
	if lastmode:find('combat', 1, true) then return false end
	if lastmode:find('NPC', 1, true) then return false end
	if lastmode == 'echo' or lastmode == 'zone' then return false end
	if lastmode:find('^item') or lastmode == 'craft' or lastmode == 'fishing' then return false end
	if lastmode == 'trade' then return false end
	if lastmode:find('^error') or lastmode == 'clock' or lastmode == 'equipset' then return false end
	if lastmode:find('_?', 1, true) then return false end
	return lastmode:find('^local')
		or lastmode:find('^shout')
		or lastmode:find('^tell')
		or lastmode:find('^party')
		or lastmode:find('^linkshell')
		or lastmode:find('^emote')
		or lastmode:find('^unity')
		or lastmode:find('^assist')
		or lastmode:find('^system')
		or lastmode == 'mog'
		or lastmode == 'servermsg'
		or lastmode == 'cfh'
		or lastmode == 'searchcomment'
end

local function provider()
	return allSettings.TranslateProvider or 'MyMemory'
end

local function api_key()
	local k = allSettings.TranslateApiKey
	if type(k) == 'table' then k = k[1] end
	return tostring(k or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function build_request(src)
	local p = provider()
	local key = api_key()
	local prompt = 'Translate the following English FFXI chat into natural Japanese. '
		..'Keep tokens like QQQ1QQQ, ZZZ1ZZZ, and KKK1KKK exactly, including digits, with no spaces. '
		..'Return only the translation.\n'..src

	if p == 'ChatGPT' then
		if key == '' then return nil, 'ChatGPT needs an API key' end
		return {
			url = 'https://api.openai.com/v1/chat/completions',
			headers = {
				'Content-Type: application/json',
				'Authorization: Bearer '..key,
			},
			body = '{"model":"gpt-4o-mini","temperature":0.2,"messages":['
				..'{"role":"system","content":"You translate English FFXI chat to Japanese. Return only the translation."},'
				..'{"role":"user","content":"'..json_escape(prompt)..'"}]}',
			parse = function(blob)
				return extract_json_string(blob, 'content')
			end,
		}
	end

	if p == 'Gemini' then
		if key == '' then return nil, 'Gemini needs an API key' end
		return {
			url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key='..key,
			headers = { 'Content-Type: application/json' },
			body = '{"contents":[{"parts":[{"text":"'..json_escape(prompt)..'"}]}]}',
			parse = function(blob)
				return extract_json_string(blob, 'text')
			end,
		}
	end

	if p == 'DeepL' then
		if key == '' then return nil, 'DeepL needs an API key' end
		local url = key:find(':fx', 1, true)
			and 'https://api-free.deepl.com/v2/translate'
			or 'https://api.deepl.com/v2/translate'
		return {
			url = url,
			headers = {
				'Content-Type: application/x-www-form-urlencoded',
				'Authorization: DeepL-Auth-Key '..key,
			},
			form = true,
			text = src,
			parse = function(blob)
				return extract_json_string(blob, 'text')
			end,
		}
	end

	-- MyMemory: free, no key.
	local q = src
	if #q > 400 then q = q:sub(1, 400) end
	local enc = {}
	for i = 1, #q do
		local b = q:byte(i)
		if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
			or b == 45 or b == 46 or b == 95 or b == 126 then
			enc[#enc + 1] = string.char(b)
		elseif b == 32 then
			enc[#enc + 1] = '+'
		else
			enc[#enc + 1] = string.format('%%%02X', b)
		end
	end
	return {
		url = 'https://api.mymemory.translated.net/get?q='..table.concat(enc)..'&langpair=en|ja',
		headers = {},
		parse = function(blob)
			return extract_json_string(blob, 'translatedText')
		end,
	}
end

-- DeepL form body after build_request (needs percent-encode).
local function deepl_form(src)
	local enc = {}
	for i = 1, #src do
		local b = src:byte(i)
		if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
			or b == 45 or b == 46 or b == 95 or b == 126 then
			enc[#enc + 1] = string.char(b)
		elseif b == 32 then
			enc[#enc + 1] = '+'
		else
			enc[#enc + 1] = string.format('%%%02X', b)
		end
	end
	return 'text='..table.concat(enc)..'&target_lang=JA&source_lang=EN'
end

local function write_cfg(job, req)
	ensure_dir()
	local id = job.id
	local out = cfg_dir()..'\\req_'..id..'.out'
	local cfgp = cfg_dir()..'\\req_'..id..'.cfg'
	local bodyp = cfg_dir()..'\\req_'..id..'.body'
	job.out = out
	job.cfg = cfgp
	job.body = bodyp

	local lines = {
		'url = "'..req.url:gsub('"', '\\"')..'"',
		'silent',
		'show-error',
		'max-time = 20',
		'output = "'..slash(out)..'"',
	}
	if req.body or req.form then
		lines[#lines + 1] = 'request = "POST"'
		local body = req.form and deepl_form(req.text) or req.body
		local bf = io.open(bodyp, 'wb')
		if not bf then return false end
		bf:write(body)
		bf:close()
		lines[#lines + 1] = 'data-binary = "@'..slash(bodyp)..'"'
	end
	for i = 1, #(req.headers or {}) do
		lines[#lines + 1] = 'header = "'..req.headers[i]:gsub('"', '\\"')..'"'
	end
	local f = io.open(cfgp, 'wb')
	if not f then return false end
	f:write(table.concat(lines, '\n')..'\n')
	f:close()
	return true
end

local function curl_bin()
	local cands = {
		'C:\\Windows\\Sysnative\\curl.exe',
		'C:\\Windows\\System32\\curl.exe',
		'curl.exe',
	}
	for i = 1, #cands do
		if cands[i] == 'curl.exe' then return cands[i] end
		local f = io.open(cands[i], 'rb')
		if f then f:close(); return cands[i] end
	end
	return 'curl.exe'
end

local function spawn_curl(job)
	os.remove(job.done)
	os.remove(job.out)
	local bf = io.open(job.bat, 'wb')
	if not bf then return false end
	bf:write('@echo off\r\n')
	bf:write('"'..curl_bin()..'" --config "'..job.cfg..'"\r\n')
	bf:write('echo done>"'..job.done..'"\r\n')
	bf:close()
	os.execute('start "" /b cmd /c call "'..job.bat..'"')
	job.t0 = os.clock()
	return true
end

local function cleanup_job(job)
	if job.out then os.remove(job.out) end
	if job.cfg then os.remove(job.cfg) end
	if job.body then os.remove(job.body) end
	if job.bat then os.remove(job.bat) end
	if job.done then os.remove(job.done) end
end

local emit_q = {}

local function queue_emit(mode, text, map, keep)
	text = restore_names(text, map)
	if not text or text == '' then return end
	if is_ascii(text) then return end
	keep = keep or ''
	if keep ~= '' then
		text = keep .. text
	end
	emit_q[#emit_q + 1] = { mode = mode or 1, text = PREFIX..text }
end

local function flush_emits()
	if #emit_q == 0 then return end
	local q = emit_q
	emit_q = {}
	for i = 1, #q do
		par.skipTranslate = true
		parseThis({ mode = q[i].mode, message = q[i].text, blocked = false }, q[i].text)
		par.skipTranslate = false
	end
end

local function emit_job(job, jp)
	local waiters = job.waiters or { { mode = job.mode, map = job.map, keep = job.keep } }
	for i = 1, #waiters do
		local w = waiters[i]
		queue_emit(w.mode, jp, w.map, w.keep)
	end
end

local function finish_ok(job, jp)
	if not jp then
		last_err = 'empty translation'
		return
	end
	jp = jp:gsub('&quot;', '"'):gsub('&amp;', '&'):gsub('&#(%d+);', function(n)
		return utf8_cp(tonumber(n) or 0)
	end)
	save_entry(job.key, jp)
	emit_job(job, jp)
end

local function find_job_by_key(key)
	return PENDING_KEY[key]
end

local function start_next()
	while #inflight < MAX_INFLIGHT and #pending > 0 do
		local job = table.remove(pending, 1)
		local req, err = build_request(job.src)
		if not req then
			last_err = err or 'bad provider'
			PENDING_KEY[job.key] = nil
		else
			job.parse = req.parse
			job.id = next_id
			next_id = next_id + 1
			job.tries = (job.tries or 0) + 1
			if not write_cfg(job, req) then
				last_err = 'could not write curl config'
				PENDING_KEY[job.key] = nil
			else
				job.bat = cfg_dir()..'\\req_'..job.id..'.bat'
				job.done = cfg_dir()..'\\req_'..job.id..'.done'
				if spawn_curl(job) then
					inflight[#inflight + 1] = job
				else
					last_err = 'could not start curl'
					PENDING_KEY[job.key] = nil
					cleanup_job(job)
				end
			end
		end
	end
end

local function requeue_or_drop(job, err)
	cleanup_job(job)
	if (job.tries or 1) < MAX_TRIES then
		pending[#pending + 1] = job
		PENDING_KEY[job.key] = job
	else
		last_err = err or last_err
		PENDING_KEY[job.key] = nil
	end
end

function M.consider(e, raw, mode, lastmode)
	if not allSettings.TranslateEnabled or not allSettings.TranslateEnabled[1] then return end
	if par.skipTranslate or par.dumping then return end
	if not chat_mode_ok(lastmode, mode) then return end
	if skip_system_text(raw) then return end
	if not dict_loaded then M.load_dict() end

	local body, keep, kmap = M.extract(raw)
	if not body then return end
	if skip_system_text(body) then return end

	local protected, map = protect_names(body)
	map.K = kmap or {}
	protected = protected:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
	if protected == '' or not protected:find('%a') then return end

	local key = norm_key(protected)
	local hit = dict[key]
	if hit then
		queue_emit(mode, hit, map, keep)
		flush_emits()
		return
	end

	local existing = find_job_by_key(key)
	if existing then
		existing.waiters = existing.waiters or {
			{ mode = existing.mode, map = existing.map, keep = existing.keep },
		}
		existing.waiters[#existing.waiters + 1] = { mode = mode, map = map, keep = keep }
		return
	end

	local p = provider()
	if (p == 'ChatGPT' or p == 'Gemini' or p == 'DeepL') and api_key() == '' then
		last_err = p..' needs an API key'
		return
	end

	while #pending >= MAX_PENDING do
		local drop = table.remove(pending, 1)
		if drop then PENDING_KEY[drop.key] = nil end
		last_err = 'translation queue full'
	end

	local job = {
		key = key,
		src = protected,
		map = map,
		keep = keep,
		mode = mode or 1,
		waiters = { { mode = mode or 1, map = map, keep = keep } },
		tries = 0,
	}
	pending[#pending + 1] = job
	PENDING_KEY[key] = job
	start_next()
end

local function file_exists(path)
	if not path then return false end
	local f = io.open(path, 'rb')
	if not f then return false end
	f:close()
	return true
end

function M.poll()
	flush_emits()
	local i = 1
	while i <= #inflight do
		local job = inflight[i]
		if file_exists(job.done) then
			local f = io.open(job.out, 'rb')
			local body = nil
			if f then
				body = f:read('*a')
				f:close()
			end
			table.remove(inflight, i)
			local jp = body and job.parse and job.parse(body)
			if jp then
				last_err = ''
				PENDING_KEY[job.key] = nil
				cleanup_job(job)
				finish_ok(job, jp)
				flush_emits()
			else
				if body and body:find('"error"', 1, true) then
					last_err = extract_json_string(body, 'message') or 'could not parse translation'
				else
					last_err = 'could not parse translation'
				end
				requeue_or_drop(job, last_err)
			end
		elseif os.clock() - (job.t0 or 0) > 25 then
			table.remove(inflight, i)
			last_err = 'translation timed out'
			requeue_or_drop(job, last_err)
		else
			i = i + 1
		end
	end
	start_next()
	flush_emits()
end

return M
