-- 统一替换 Pandoc / citeproc 常产生的“神秘空格”为普通空格
local function normalize(s)
  -- 常见不可见空白
  s = s:gsub("\u{00A0}", " ")  -- NBSP
  s = s:gsub("\u{202F}", " ")  -- Narrow NBSP
  s = s:gsub("\u{2009}", " ")  -- Thin space
  s = s:gsub("\u{200A}", " ")  -- Hair space
  return s
end

function Str(el)
  local t = el.text
  local nt = normalize(t)
  if nt ~= t then
    el.text = nt
    return el
  end
end
