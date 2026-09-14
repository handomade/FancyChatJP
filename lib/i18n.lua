-- lib/i18n.lua  Japanese display labels for GUI.
-- Strings are UTF-8 stored as decimal byte escapes so a CP932 Lua
-- loader cannot turn them into '?'.  Rebuild with _escape_lua_utf8.py.
-- Internal tab / setting keys stay English so saved configs and
-- buffer routing keep working.  Only the visible string changes.

local M = {}

M.tab = {
	All       = '\229\133\168\227\129\166',
	AllAlt    = '\229\133\168\227\129\166',
	Combat    = '\230\136\166\233\151\152',
	Linkshell = 'LS',
	L1        = 'L1',
	L2        = 'L2',
	Party     = 'PT',
	Tell      = 'Tell',
	Shout     = '\227\130\183\227\131\163\227\130\166\227\131\136',
	Custom    = '\227\130\171\227\130\185\227\130\191\227\131\160',
}

function M.tab_label(name)
	return M.tab[name] or name
end

-- ImGui button caption + unique ID.  AllAlt used to display as "All"
-- via gsub('Alt','##Alt'); we keep a unique ##id while showing .
function M.tab_button(name)
	return M.tab_label(name)..'##'..(name or '')
end

return M
