local M = {
  enabled = true,
  kerns = {
    ["l"] = { ["m"] = 1, ["n"] = 1},
    ["ν"] = { ["f"] = -2, ["p"] = -2 },
    ["γ"] = { ["f"] = -2 },
    ["ω"] = { ["f"] = -2 },
    ["Φ"] = { ["c"] = -1, ["d"] = -1, ["p"] = -2 },
  },
}

local noad = node.id("noad")
local math_char = node.id("math_char")
local sub_mlist = node.id("sub_mlist")
local choice = node.id("choice")

local function key(fam, char)
  return fam .. ":" .. char
end

local function input_key(letter)
  local c = tex.getmathcode(utf8.codepoint(letter))
  return key(c[2], c[3])
end

local function single_char(s)
  if not s then return end
  if s.id == math_char then return s end
  if s.id == sub_mlist then
    local h = s.head
    if h and not h.next and h.id == noad and h.subtype == 0
        and not h.sub and not h.sup and h.nucleus
        and h.nucleus.id == math_char then
      return h.nucleus
    end
  end
end

local function prepend_kern(n, amount)
  local s = n.sub
  local k = node.new("kern", 99)
  k.kern = math.floor(amount * 65536 + 0.5)
  k.attr = s.attr
  if s.id == math_char then
    n.sub = nil
    local atom = node.new("noad", 0)
    atom.attr = s.attr
    atom.nucleus = s
    local list = node.new("sub_mlist")
    list.attr = s.attr
    list.head = atom
    n.sub = list
    s = list
  end
  s.head = node.insert_before(s.head, s.head, k)
end

local kernel_fields = { "nucleus", "sub", "sup", "num", "denom", "degree" }
local choice_fields = { "display", "text", "script", "scriptscript" }

local function walk(head, pairs)
  for n in node.traverse(head) do
    for _, field in ipairs(kernel_fields) do
      if node.has_field(n, field) then
        local s = n[field]
        if s and s.id == sub_mlist then walk(s.head, pairs) end
      end
    end
    if n.id == choice then
      for _, field in ipairs(choice_fields) do
        if n[field] then walk(n[field], pairs) end
      end
    end

    if n.id == noad and n.subtype == 0 then
      local b, s = n.nucleus, single_char(n.sub)
      if b and b.id == math_char and s then
        local row = pairs[key(b.fam, b.char)]
        local amount = row and row[key(s.fam, s.char)]
        if amount and amount ~= 0 then prepend_kern(n, amount) end
      end
    end
  end
end

luatexbase.add_to_callback("pre_mlist_to_hlist_filter", function(head)
  if M.enabled then
    local mapped_pairs = {}
    for base, row in pairs(M.kerns) do
      local mapped = {}
      for sub, amount in pairs(row) do mapped[input_key(sub)] = amount end
      mapped_pairs[input_key(base)] = mapped
    end
    walk(head, mapped_pairs)
  end
  return head
end, "math-subscript-kerns")

return M
