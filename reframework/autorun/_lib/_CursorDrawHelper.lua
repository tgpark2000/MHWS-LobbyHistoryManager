local fs, imgui, io, json, log, math, os, pcall, re, sdk, string, table, thread, tonumber, tostring, type, ValueType, Vector2f, Vector3f, Vector4f, xpcall = fs, imgui, io, json, log, math, os, pcall, re, sdk, string, table, thread, tonumber, tostring, type, ValueType, Vector2f, Vector3f, Vector4f, xpcall
-- =================================================================================
-- Module: Cursor Draw Helper (for RE-Framework Monster Hunter Wilds)
-- 
-- This module renders a custom SVG mouse cursor over the ImGui window
-- to bypass the RE Engine's mouse restriction in re.on_frame loops.
-- 
-- Credits: 
-- Logic and SVG path data adapted from the 'Useful field guide' mod.
-- Special thanks to the original author 'Mech3' for this brilliant implementation.
-- Original Mod: https://www.nexusmods.com/monsterhunterwilds/mods/1760
-- =================================================================================

local Module = {}

local function parse_svg_path_data(d)
    local commands = {}
    local i        = 1
    local len      = #d

    local function skip_space()
        while i <= len and d:sub(i,i):match("[%s,]") do
            i = i + 1
        end
    end

    local function parse_number()
        skip_space()
        local s, e = d:find("[-+]?[0-9]*%.?[0-9]+", i)
        if not s then return nil end
        local number = tonumber(d:sub(s, e))
              i      = e + 1
        return number
    end

    local function parse_coords(n)
        local coords = {}
        for _ = 1, n do
            local val = parse_number()
            if not val then break end
            table.insert(coords, val)
        end
        return coords
    end

    while i <= len do
        skip_space()
        local c = d:sub(i, i)
        if c:match("%a") then
                  i        = i + 1
            local cmd      = c
            local args     = {}
            local expected = ({M = 2, L = 2, C = 6, Z = 0, S = 4})[cmd:upper()]
            repeat
                skip_space()
                if expected > 0 then
                    local coords = parse_coords(expected)
                    if #coords == expected then table.insert(args, coords)
                    else                        break                      end
                end
            until expected == 0 or d:sub(i,i):match("%a")
            table.insert(commands, {cmd = cmd, args = args})
        else
            i = i + 1
        end
    end

    return commands
end

local cursor_path  = parse_svg_path_data("M11.4,29.4l-4.3,8.5c-0.2,0.5-0.2,0.7,0.3,1l8.3,3.4c0.6,0.2,0.8,0.2,1-0.3l0.9-1.8c0.1-0.3,0-0.4-0.5-0.6l-3.9-1.6c-0.8-0.4-1-0.9-0.7-1.7l1.2-2.3c0.4-0.8,1-0.5,1.9-0.1l6.6,2.9c1.1,0.6,1.5,1.1,0.9,2.4l-4.6,8.9c-0.2,0.3-0.3,0.4-0.9,0.1L1.1,41.6c-0.8-0.3-0.8-0.4-0.8-0.9L0,0.8c0-0.3,0.3-0.4,0.5-0.2l25.8,28.8c0.5,0.6,0.8,0.9,0.5,1.6l-1.2,2.8c-0.4,0.8-0.6,1-1.4,0.7L11.4,29.4L9,23.8l8.6,2.3L3.4,9.1l0.8,21.4L9,23.8L11.4,29.4z")
local cursor_patch = parse_svg_path_data("M4.2,30.5 9,23.8 17.6,26.1 15.9,31.2 11.4,29.4 9.4,33.3z")

local function draw_svg_path(draw_list, path_cmds, offset_x, offset_y, color, scale, outline)
  if type(path_cmds) == "String" then path_cmds = parse_svg_path_data(path_cmds) end
        outline       = outline or false
  local pos           = {x = 0, y = 0}
  local start_pos     = {x = 0, y = 0}
  local subpath_open  = false
        scale         = scale or 1.0
  local outline_scale = scale * 5

  for _, item in ipairs(path_cmds) do
      local cmd   = item.cmd
      local args  = item.args
      local upper = cmd:upper()
      local rel   = cmd:match("%l")

      if upper == 'M' then
          if subpath_open then
            if outline then draw_list:path_stroke(0x80000000, true, outline_scale) else draw_list:path_fill_concave(color) end
              subpath_open = false
          end
          for i, pair in ipairs(args) do
              local x = pair[1] * scale + (rel and pos.x or 0)
              local y = pair[2] * scale + (rel and pos.y or 0)
              if i == 1 then
                  draw_list:path_clear()
                  draw_list:path_line_to(Vector2f.new(x + offset_x, y + offset_y))
                  start_pos    = {x = x, y = y}
                  subpath_open = true
              else
                  draw_list:path_line_to(Vector2f.new(x + offset_x, y + offset_y))
              end
              pos = {x = x, y = y}
          end
      elseif upper == 'L' then
        for i, pair in ipairs(args) do
              local x = pair[1] * scale + (rel and pos.x or 0)
              local y = pair[2] * scale + (rel and pos.y or 0)
              draw_list:path_line_to(Vector2f.new(x + offset_x, y + offset_y))
              pos     = {x = x, y = y}
          end
      elseif upper == 'C' then
          for _, set in ipairs(args) do
              local cp1  = {x = set[1] * scale, y = set[2] * scale}
              local cp2  = {x = set[3] * scale, y = set[4] * scale}
              local endp = {x = set[5] * scale, y = set[6] * scale}
              if rel then
                  cp1.x  = cp1.x  + pos.x; cp1.y  = cp1.y  + pos.y
                  cp2.x  = cp2.x  + pos.x; cp2.y  = cp2.y  + pos.y
                  endp.x = endp.x + pos.x; endp.y = endp.y + pos.y
              end
              draw_list:path_bezier_cubic_curve_to(
                  Vector2f.new(cp1.x  + offset_x,  cp1.y + offset_y),
                  Vector2f.new(cp2.x  + offset_x,  cp2.y + offset_y),
                  Vector2f.new(endp.x + offset_x, endp.y + offset_y)
              )
              pos = {x = endp.x, y = endp.y}
          end
      elseif upper == 'Z' then
          draw_list:path_line_to(Vector2f.new(start_pos.x + offset_x, start_pos.y + offset_y))
          if outline then draw_list:path_stroke(0x80000000, true, outline_scale) else draw_list:path_fill_concave(color) end
          subpath_open = false
      end
  end

  if subpath_open then
      if outline then draw_list:path_stroke(0xAA000000, true, scale * 2) else draw_list:path_fill_concave(color) end
  end
end

function Module.draw_custom_cursor(scale)
    if reframework and reframework:is_drawing_ui() then return end

    local mousePos   = imgui.get_mouse()
    local windowSize = imgui.get_window_size()
    local windowPos  = imgui.get_window_pos()
    
    local isHovered = (mousePos.x >= windowPos.x) and (mousePos.x <= windowPos.x + windowSize.x) and 
                      (mousePos.y >= windowPos.y) and (mousePos.y <= windowPos.y + windowSize.y)

    if isHovered then
        pcall(function()
            local foreground = imgui.get_foreground_draw_list()
            draw_svg_path(foreground, cursor_path,  mousePos.x, mousePos.y, 0xFFC1FFFC, scale, true)
            draw_svg_path(foreground, cursor_path,  mousePos.x, mousePos.y, 0xFFC1FFFC, scale)
            draw_svg_path(foreground, cursor_patch, mousePos.x, mousePos.y, 0xFFC1FFFC, scale)
        end)
    end
end

return Module
