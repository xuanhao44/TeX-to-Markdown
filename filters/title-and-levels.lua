-- Turn metadata.title into an H1 at the beginning,
-- and demote all original headers in the body by one level:
--   original H1 (from \section)    -> H2
--   original H2 (from \subsection) -> H3, etc.

function Pandoc(doc)
  local blocks = {}

  -- 1. If metadata.title exists, insert it as an H1 first
  local title = doc.meta.title
  if title and title ~= "" then
    table.insert(blocks, pandoc.Header(1, pandoc.utils.stringify(title)))
  end

  -- 2. Copy all original blocks; when seeing a Header, increase its level by 1
  for _, b in ipairs(doc.blocks) do
    if b.t == "Header" then
      b.level = b.level + 1
    end
    table.insert(blocks, b)
  end

  doc.blocks = blocks
  return doc
end
