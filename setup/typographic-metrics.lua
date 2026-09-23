-- LuaLaTeX measurements. Only a private node attribute is written; no PDF
-- structure, visible text, or typesetting dimensions are changed.
local M = {
  active = false, excluded = 0, current = nil, chapters = {},
  lines = {}, next_line = 0, heading_pending = false,
  heading_paragraphs = 0, skipped_headings = 0,
  start_calls = 0, active_callbacks = 0, excluded_callbacks = 0,
  shipped_pages = 0,
}
local hlist, vlist, insert = node.id("hlist"), node.id("vlist"), node.id("ins")
local glyph, glue = node.id("glyph"), node.id("glue")
local mathnode, disc = node.id("math"), node.id("disc")
local attr = luatexbase.new_attribute("nt_typographic_metrics_line")

local function new_stats(label)
  return {
    label = label, lengths = {}, full_lengths = {}, page_lines = {},
    word_space = {}, paragraphs = 0, multi_paragraphs = 0,
    short_endings = 0, hyphenated = 0, runs = 0, max_run = 0,
    mixed_math = 0, spaces_stretched = 0, spaces_shrunk = 0,
    overfull_boxes = 0, max_overfull_sp = 0,
  }
end
M.all = new_stats("Entire main matter")

function M.start()
  M.active = true
  M.excluded = 0
  M.heading_pending = false
  M.body_font = font.current()
  M.start_calls = M.start_calls + 1
end
function M.stop()
  M.active = false
  M.current = nil
  M.heading_pending = false
end
function M.heading_begin()
  if M.active then
    M.heading_pending = true
    M.heading_paragraphs = 0
  end
end
function M.chapter(number)
  if not M.active then return end
  if M.current and M.current.number == number then return end
  local chapter = new_stats("Chapter " .. number)
  chapter.number = number
  chapter.index = #M.chapters + 1
  M.chapters[chapter.index] = chapter
  M.current = chapter
end
function M.exclude_begin()
  M.excluded = M.excluded + 1
end
function M.exclude_end()
  M.excluded = math.max(0, M.excluded - 1)
end

local function glyph_count(n)
  if n.components then
    local total = 0
    for component in node.traverse(n.components) do
      if component.id == glyph then
        total = total + glyph_count(component)
      end
    end
    if total > 0 then return total end
  end
  return 1
end

local function scan(head, line, result)
  if not head then return end
  local in_math = false
  for n in node.traverse(head) do
    if n.id == mathnode then
      in_math = n.subtype == 0
      result.math = true
    elseif not in_math then
      if n.id == glyph then
        local count = glyph_count(n)
        result.characters = result.characters + count
        if n.font == M.body_font then
          result.body_glyphs = result.body_glyphs + count
        end
        result.last_visible = glyph
      elseif n.id == glue and (n.subtype == 13 or n.subtype == 14) then
        result.characters = result.characters + 1
        result.space_natural = result.space_natural + n.width
        result.space_actual = result.space_actual + node.effective_glue(n, line)
      elseif n.id == disc then
        -- A broken discretionary is the final text item before rightskip.
        result.last_visible = disc
        result.last_disc_broken = n.pre == nil
      elseif n.id == hlist then
        scan(n.head, line, result)
      end
    end
  end
end

local function collect(head)
  if not M.active then return true end
  M.active_callbacks = M.active_callbacks + 1
  if M.excluded > 0 then
    M.excluded_callbacks = M.excluded_callbacks + 1
    return true
  end
  M.chapter(tex.count["c@chapter"])
  if not M.current then return true end
  local paragraph = {}
  local line_nodes = {}
  for line in node.traverse_id(hlist, head) do
    if line.subtype == 1 then
      local data = {
        chapter = M.current.index, characters = 0, math = false,
        space_natural = 0, space_actual = 0, body_glyphs = 0,
      }
      scan(line.head, line, data)
      if data.characters > 0 then
        data.hyphenated = data.last_visible == disc and data.last_disc_broken
        paragraph[#paragraph + 1] = data
        line_nodes[#line_nodes + 1] = line
      end
    end
  end
  if M.heading_pending and #paragraph > 0 then
    M.heading_paragraphs = M.heading_paragraphs + 1
    local body_glyphs = 0
    for _, data in ipairs(paragraph) do
      body_glyphs = body_glyphs + data.body_glyphs
    end
    -- Do not let a novel heading implementation suppress an entire book:
    -- at most two heading paragraphs are omitted per sectioning command.
    if body_glyphs == 0 and M.heading_paragraphs <= 2 then
      M.skipped_headings = M.skipped_headings + 1
      return true
    end
    M.heading_pending = false
  end
  for i, data in ipairs(paragraph) do
    M.next_line = M.next_line + 1
    M.lines[M.next_line] = data
    node.set_attribute(line_nodes[i], attr, M.next_line)
  end
  if #paragraph > 0 then
    local final = paragraph[#paragraph]
    final.final = true
    final.paragraph = true
    if #paragraph > 1 then
      final.multi_paragraph = true
      local full = {}
      for i = 1, #paragraph - 1 do full[i] = paragraph[i].characters end
      table.sort(full)
      local middle = math.floor((#full + 1) / 2)
      local median = #full % 2 == 1 and full[middle]
        or (full[middle] + full[middle + 1]) / 2
      final.short_ending = final.characters < 0.35 * median
    end
    local run, max_run, runs = 0, 0, 0
    for _, data in ipairs(paragraph) do
      if data.hyphenated then
        run = run + 1
        if run == 2 then runs = runs + 1 end
        max_run = math.max(max_run, run)
      else
        run = 0
      end
    end
    final.hyphen_runs = runs
    final.max_hyphen_run = max_run
  end
  return true
end

local function add_line(stats, data)
  stats.lengths[#stats.lengths + 1] = data.characters
  if data.math then stats.mixed_math = stats.mixed_math + 1 end
  if data.hyphenated then stats.hyphenated = stats.hyphenated + 1 end
  if data.paragraph then
    stats.paragraphs = stats.paragraphs + 1
    stats.runs = stats.runs + data.hyphen_runs
    stats.max_run = math.max(stats.max_run, data.max_hyphen_run)
    if data.multi_paragraph then
      stats.multi_paragraphs = stats.multi_paragraphs + 1
      if data.short_ending then stats.short_endings = stats.short_endings + 1 end
    end
  else
    stats.full_lengths[#stats.full_lengths + 1] = data.characters
    if data.space_natural > 0 then
      local ratio = 100 * (data.space_actual / data.space_natural - 1)
      stats.word_space[#stats.word_space + 1] = math.abs(ratio)
      if ratio > 0.01 then stats.spaces_stretched = stats.spaces_stretched + 1 end
      if ratio < -0.01 then stats.spaces_shrunk = stats.spaces_shrunk + 1 end
    end
  end
end

local function page_visit(head, counts)
  if not head then return end
  for n in node.traverse(head) do
    if n.id == hlist or n.id == vlist or n.id == insert then
      if n.id == hlist and n.subtype == 1 then
        local id = node.has_attribute(n, attr)
        local data = id and M.lines[id]
        if data then
          local chapter = M.chapters[data.chapter]
          add_line(chapter, data)
          add_line(M.all, data)
          counts[data.chapter] = (counts[data.chapter] or 0) + 1
          counts.all = (counts.all or 0) + 1
          M.lines[id] = nil
        end
      else
        page_visit(n.head, counts)
      end
    end
  end
end

local function shipout(box)
  if not box then return box end
  M.shipped_pages = M.shipped_pages + 1
  local counts = {}
  page_visit(box.head, counts)
  for index, count in pairs(counts) do
    local stats = index == "all" and M.all or M.chapters[index]
    stats.page_lines[#stats.page_lines + 1] = count
  end
  return box
end

-- An engine diagnostic, not an exact count of overfull prose lines: TeX also
-- packs other horizontal boxes within main matter.
local function quality(incident, detail)
  if incident == "overfull" and M.active and M.excluded == 0 then
    M.chapter(tex.count["c@chapter"])
    if not M.current then return end
    for _, stats in ipairs({M.current, M.all}) do
      stats.overfull_boxes = stats.overfull_boxes + 1
      stats.max_overfull_sp = math.max(stats.max_overfull_sp, detail)
    end
  end
end

local function quantile(sorted, fraction)
  if #sorted == 0 then return 0 end
  local pos = 1 + (#sorted - 1) * fraction
  local low, high = math.floor(pos), math.ceil(pos)
  return sorted[low] + (sorted[high] - sorted[low]) * (pos - low)
end
local function describe(values)
  if #values == 0 then return "n/a" end
  local sorted, sum = {}, 0
  for i, value in ipairs(values) do sorted[i], sum = value, sum + value end
  table.sort(sorted)
  return string.format("mean %.1f; p10 %.1f; median %.1f; p90 %.1f",
    sum / #values, quantile(sorted, 0.1), quantile(sorted, 0.5),
    quantile(sorted, 0.9))
end
local function log(message)
  texio.write_nl("log", "NT TYPOGRAPHY | " .. message)
end
local function report_one(stats)
  log(stats.label .. ": " .. #stats.lengths .. " prose-bearing lines; " ..
      stats.paragraphs .. " paragraphs; " .. #stats.page_lines .. " prose-bearing pages")
  log("  characters/line including spaces: " .. describe(stats.lengths))
  log("  non-final characters/line: " .. describe(stats.full_lengths))
  log("  hyphenated line endings: " .. stats.hyphenated ..
      "; runs of 2+: " .. stats.runs .. "; longest run: " .. stats.max_run)
  log("  short final lines (<35 percent of preceding-line median): " ..
      stats.short_endings .. "/" .. stats.multi_paragraphs .. " multiline paragraphs")
  log("  absolute word-space change on non-final lines (percent): " ..
      describe(stats.word_space) .. "; stretched: " .. stats.spaces_stretched ..
      "; shrunk: " .. stats.spaces_shrunk)
  log("  prose lines/prose-bearing page: " .. describe(stats.page_lines))
  log("  lines with inline mathematics: " .. stats.mixed_math)
  log(string.format("  overfull hbox diagnostics in main matter: %d; largest %.2f pt",
    stats.overfull_boxes, stats.max_overfull_sp / 65536))
end
function M.report()
  log("Scope: main-matter paragraphs, excluding figures, " ..
      "tables, longtables, their captions, and detected sectioning headings; " ..
      "inline mathematics excluded from " ..
      "character/space counts. Footnotes and exercises are included.")
  log("Characters approximate printed Unicode characters: ligature components " ..
      "and word spaces count; display mathematics and math-only lines do not.")
  log("p10 and p90 are interpolated percentiles. Short endings use 35 percent; " ..
      "word-space change compares set and natural interword glue.")
  log(string.format("Capture diagnostics: mainmatter starts %d; active paragraph " ..
      "callbacks %d; excluded callbacks %d; skipped heading paragraphs %d; " ..
      "shipped pages %d", M.start_calls, M.active_callbacks,
      M.excluded_callbacks, M.skipped_headings, M.shipped_pages))
  if #M.all.lengths == 0 then
    log("NO PROSE CAPTURED. Check the capture diagnostics above; this is " ..
        "not a zero-valued typographic measurement.")
  end
  report_one(M.all)
  for _, stats in ipairs(M.chapters) do report_one(stats) end
end

luatexbase.add_to_callback("post_linebreak_filter", collect, "nt_typographic_metrics_collect")
luatexbase.add_to_callback("pre_shipout_filter", shipout, "nt_typographic_metrics_shipout")
luatexbase.add_to_callback("hpack_quality", quality, "nt_typographic_metrics_quality")
return M
