local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

local function basename_no_ext(path)
  local name = path:gsub("^.*/", "")
  return name:gsub("%.[^%.]+$", "")
end

local function strip_tags(s)
  return (s
    :gsub("<[^>]+>", "")
    :gsub("&nbsp;", " ")
    :gsub("&amp;", "&")
    :gsub("&lt;", "<")
    :gsub("&gt;", ">")
    :gsub("^%s+", "")
    :gsub("%s+$", ""))
end

local function extract_attr(tag, attr)
  local pat = attr .. '%s*=%s*"([^"]+)"'
  return tag:match(pat)
end

local function pick_replacement_for_pdf(src)
  local base = src:gsub("%.pdf$", "")
  local exts = { "svg", "png", "jpg", "jpeg" }
  for _, ext in ipairs(exts) do
    local cand = base .. "." .. ext
    if file_exists(cand) then return cand end
  end
  return nil
end

local function wrap_with_id(block, id)
  return { block }
end

function RawBlock(el)
  if el.format ~= "html" then return nil end
  local t = el.text

  if not t:match("^%s*<figure") then return nil end
  if not t:match("</figure>%s*$") then return nil end

  local fig_open = t:match("(<figure[^>]*>)")
  local fig_id = fig_open and (extract_attr(fig_open, "id") or "") or ""

  local embed_tag = t:match("(<embed[^>]*>)")
  local img_tag   = t:match("(<img[^>]*>)")

  local src = ""
  if embed_tag then src = extract_attr(embed_tag, "src") or "" end
  if src == "" and img_tag then src = extract_attr(img_tag, "src") or "" end
  if src == "" then return nil end

  local cap = t:match("<figcaption>(.-)</figcaption>")
  cap = cap and strip_tags(cap) or ""
  if cap == "" then cap = basename_no_ext(src) end
  local cap_inlines = pandoc.Inlines{ pandoc.Str(cap) }

  -- 生成一个“纯 Markdown 友好”的块（Para(Image) 或 Para(Link)）
  local para

  if src:match("%.pdf$") then
    local repl = pick_replacement_for_pdf(src)
    if repl then
      local img = pandoc.Image(cap_inlines, repl)
      img.title = basename_no_ext(repl)
      para = pandoc.Para({ img })
    else
      local link = pandoc.Link(cap_inlines, src)
      para = pandoc.Para({ link })
    end
  else
    local img = pandoc.Image(cap_inlines, src)
    img.title = basename_no_ext(src)
    para = pandoc.Para({ img })
  end

  return wrap_with_id(para, fig_id)
end
