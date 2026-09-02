-- Runtime provenance for setup/versioning.tex.
--
-- This is intentionally a Lua module rather than a large \directlua block.
-- TeX therefore cannot expand active characters in the Lua program before
-- LuaHBTeX parses it.  The interface exposed to TeX is deliberately tiny.

local existing = rawget(_G, "NTVersioning")
if existing then
  return existing
end

local versioning = {}
NTVersioning = versioning

local function sanitizeFontName(value)
  local input = tostring(value or "")
  local output = {}

  for position = 1, #input do
    local byte = string.byte(input, position)
    local safe =
      (byte >= 48 and byte <= 57) or
      (byte >= 65 and byte <= 90) or
      (byte >= 97 and byte <= 122) or
      byte == 32 or byte == 40 or byte == 41 or
      byte == 45 or byte == 46 or byte >= 128
    output[#output + 1] = safe and string.char(byte) or " "
  end

  local result = table.concat(output)
  result = result:gsub("^%s+", ""):gsub("%s+$", "")
  result = result:gsub("%s+", " ")
  return result
end

local function normalize(value)
  local input = string.lower(tostring(value or ""))
  local output = {}

  for position = 1, #input do
    local byte = string.byte(input, position)
    if (byte >= 48 and byte <= 57) or
        (byte >= 97 and byte <= 122) then
      output[#output + 1] = string.char(byte)
    end
  end

  return table.concat(output)
end

-- OpenType family metadata normally removes weight and style by itself.  Some
-- fonts, however, expose only a PostScript/full name, and a few related font
-- files use distinct subfamily records even though a reader regards them as
-- one family.  These ordered prefix rules provide stable, human-facing names
-- for the families used by this project.  Put more specific prefixes first.
local familyUmbrellas = {
  { "notosanscuneiform", "Noto Sans Cuneiform" },
  { "gfsartemisia", "GFS Artemisia" },
  { "ebgaramond", "EB Garamond" },
  { "libertinus", "Libertinus" },
  { "stixtwo", "STIX Two" },
  { "newcm", "New Computer Modern" },
  { "newcomputermodern", "New Computer Modern" },
  { "texgyrescholax", "TeX Gyre Schola X" },
  { "texgyrebonum", "TeX Gyre Bonum" },
  { "texgyreschola", "TeX Gyre Schola" },
  { "texgyretermes", "TeX Gyre Termes" },
  { "texgyrepagella", "TeX Gyre Pagella" },
  { "texgyreheros", "TeX Gyre Heros" },
  { "texgyrecursor", "TeX Gyre Cursor" },
  { "xchartermath", "X Charter" },
  { "xcharter", "X Charter" },
  { "baskervald", "Baskervald X" },
  { "kpfonts", "Kp-fonts" },
  { "kproman", "Kp-fonts" },
  { "kpmath", "Kp-fonts" },
  { "kpsans", "Kp-fonts" },
  { "kpmono", "Kp-fonts" },
  { "cmuconcrete", "CMU Concrete" },
  { "cmunorm", "CMU Concrete" },
  { "cmunoti", "CMU Concrete" },
  { "cmunobx", "CMU Concrete" },
  { "cmunobi", "CMU Concrete" },
  { "concretemath", "CMU Concrete" },
  { "ibmplex", "IBM Plex" },
  { "sourcecode", "Source Code" },
  { "sourcesans", "Source Sans" },
  { "sourceserif", "Source Serif" },
  { "alegreyasans", "Alegreya Sans" },
  { "alegreya", "Alegreya" },
  { "notosansmono", "Noto Sans Mono" },
  { "notosans", "Noto Sans" },
  { "notoserif", "Noto Serif" },
  { "inconsolatazi", "Inconsolata" },
  { "inconsolata", "Inconsolata" },
  { "garamondmath", "Garamond Math" },
  { "eulermath", "Euler Math" },
  { "asanamath", "Asana Math" },
  { "xits", "XITS" },
  { "rmlm", "Latin Modern" },
  { "lmroman", "Latin Modern" },
  { "lmsans", "Latin Modern" },
  { "lmmono", "Latin Modern" },
  { "latinmodern", "Latin Modern" },
  { "cmex", "Computer Modern" },
  { "cmmi", "Computer Modern" },
  { "cmsy", "Computer Modern" },
  { "cmr", "Computer Modern" },
  { "cmss", "Computer Modern" },
  { "cmtt", "Computer Modern" },
  { "msam", "AMS Symbols" },
  { "msbm", "AMS Symbols" },
  { "eufm", "Euler Fraktur" },
  { "eufb", "Euler Fraktur" },
  { "rsfs", "Ralph Smith's Formal Script" },
  { "wasy", "Wasy Symbols" },
  { "stmary", "St Mary's Road Symbols" },
  { "lcircle", "LaTeX picture fonts" },
  { "linew", "LaTeX picture fonts" },
  { "line", "LaTeX picture fonts" }
}

local styleSuffixes = {
  "bold italic", "bold oblique", "semibold italic", "semibold oblique",
  "demibold italic", "demibold oblique", "bolditalic", "boldoblique",
  "semibold", "demibold", "extrabold", "ultrabold", "medium",
  "regular", "roman", "book", "bold", "italic", "oblique", "slanted"
}

local function stripStyleSuffixes(name)
  local result = name:gsub("%.[Oo][Tt][Ff]$", "")
  result = result:gsub("%.[Tt][Tt][Ff]$", "")

  local changed = true
  while changed do
    changed = false
    local folded = string.lower(result)
    for _, suffix in ipairs(styleSuffixes) do
      for _, separator in ipairs({ " ", "-", "_" }) do
        local ending = separator .. suffix
        if folded:sub(-#ending) == ending then
          result = result:sub(1, #result - #ending)
          changed = true
          break
        end
      end
      if changed then
        break
      end
    end
  end

  return result
end

local function canonicalFamilyName(name)
  local stripped = stripStyleSuffixes(sanitizeFontName(name))
  local key = normalize(stripped)
  for _, rule in ipairs(familyUmbrellas) do
    if key:sub(1, #rule[1]) == rule[1] then
      return rule[2]
    end
  end
  return stripped
end

local function fontFamily(data)
  local properties = type(data.properties) == "table" and data.properties or {}
  local resources = type(data.resources) == "table" and data.resources or {}
  local resourceMetadata =
    type(resources.metadata) == "table" and resources.metadata or {}
  local shared = type(data.shared) == "table" and data.shared or {}
  local rawdata = type(shared.rawdata) == "table" and shared.rawdata or {}
  local rawMetadata =
    type(rawdata.metadata) == "table" and rawdata.metadata or {}

  local name = properties.familyname
  if not name or name == "" then
    name = data.familyname
  end
  if not name or name == "" then
    name = resourceMetadata.familyname
  end
  if not name or name == "" then
    name = rawMetadata.familyname
  end
  if not name or name == "" then
    name = properties.fullname or data.fullname
  end
  if not name or name == "" then
    name = properties.fontname or data.fontname or data.name
  end

  name = canonicalFamilyName(name)
  if name == "" then
    return nil
  end
  return name
end

local function sortedNames(collection)
  local names = {}
  for _, name in pairs(collection) do
    names[#names + 1] = name
  end

  table.sort(names, function(left, right)
    local foldedLeft = string.lower(left)
    local foldedRight = string.lower(right)
    if foldedLeft == foldedRight then
      return left < right
    end
    return foldedLeft < foldedRight
  end)

  if #names == 0 then
    return "none loaded"
  end
  return table.concat(names, ", ")
end

function versioning.writeLoadedFontManifest()
  local supporting = {}
  local profileLabel = token.get_macro("VersionFontName") or ""
  local openPosition = profileLabel:find("(", 1, true)
  local profileBase =
    openPosition and profileLabel:sub(1, openPosition - 1) or profileLabel
  local primaryFamily = normalize(canonicalFamilyName(profileBase))

  for _, data in font.each() do
    local name = fontFamily(data)
    if name then
      local key = string.lower(name)
      if normalize(name) ~= primaryFamily then
        supporting[key] = name
      end
    end
  end

  tex.sprint(
    string.char(92) .. "NTWriteFontManifestToAux{" ..
    sortedNames(supporting) .. "}"
  )
end

local banner = tostring(status.banner or "LuaHBTeX")
if banner:sub(1, 8) == "This is " then
  banner = banner:sub(9)
end

local developmentId = status.development_id
if developmentId ~= nil then
  banner = banner .. "; development id " .. tostring(developmentId)
end

token.set_macro("NTTeXEngineInformation", banner, "global")

return versioning
