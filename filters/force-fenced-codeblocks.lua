-- 给每个 CodeBlock 加一个 class，逼 writer 用 fenced
function CodeBlock(el)
  el.attr = el.attr or pandoc.Attr()
  local classes = el.attr.classes or {}
  local seen = false
  for _, c in ipairs(classes) do
    if c == "fenced" then seen = true end
  end
  if not seen then table.insert(classes, "") end
  el.attr.classes = classes
  return el
end
