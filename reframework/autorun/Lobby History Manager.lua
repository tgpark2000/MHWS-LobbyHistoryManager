local fs, imgui, io, json, log, math, os, pcall, re, sdk, string, table, thread, tonumber, tostring, type, ValueType, Vector2f, Vector3f, Vector4f, xpcall = fs, imgui, io, json, log, math, os, pcall, re, sdk, string, table, thread, tonumber, tostring, type, ValueType, Vector2f, Vector3f, Vector4f, xpcall
local MOD_TITLE     = "Lobby History Manager"
local CONFIG_FILE   = "Lobby_History_Manager.json"
local CursorHelper  = require("_lib._CursorDrawHelper")  -- Mech3님께서 만드신 'Useful Field Guide' 모드의 마우스 커서를 그리는 부분을 가져와서 모듈화했다. Original Mod: https://www.nexusmods.com/monsterhunterwilds/mods/1760
local config        = { enabled = true, cursorScale = 1.5, showHistoryMax = 5, use24Hour = true, lastJoinedLobbyId = "", lobbyHistory = {} }
local oldConfig     = nil
local HISTORY_MAX   = 20
local LOCK_MAX      = HISTORY_MAX - 1
local FONT_SIZE     = 28
local isWindowOpen  = false
local inputGuiPtr   = nil
local inputLobbyId  = ""
local UI_TEXT = {
    LOCK            = "  ",
    LOCKED_STAR     = "\u{2605}",
    UNLOCKED_STAR   = "\u{2606}",
    CLIPBOARD       = "\u{1F4CB}",
    LOBBY_ID        = "Lobby ID",
    LANGUAGE        = "Language",
    JOINED_AT       = "Joined At",
    DELETE_HEADER   = "   ",
    DELETE_BUTTON   = "\u{2715}",
    NO_RECORD       = "No lobby history found.",
    INPUT_LABEL     = "Lobby ID:", 
    BTN_ENTER       = "Enter",
    WARNING_MESSAGE = "  Character limit exceeded. Maximum is 8.  ",
    CLICK_TO_JOIN   = " Click to join. ",
    MAXIMUM_LOCK     = "  Maximum lock limit reached. Unlock another item first.",
}
local UI_TABLE_HEADERS = { UI_TEXT.LOCK, UI_TEXT.LOBBY_ID, UI_TEXT.LANGUAGE, UI_TEXT.JOINED_AT, UI_TEXT.DELETE_HEADER }
local UI_COLUMN_WIDTH  = {}

local function arrayCount(ary)
    if (type(ary) ~= "table") then return 0 end

    local count = 0
    for _ in pairs(ary) do 
        count = count + 1 
    end
    return count
end

local function arrayIsEqual(a, b)
    if (type(a) ~= "table") or (type(b) ~= "table") then return false end
    if arrayCount(a) ~= arrayCount(b)               then return false end
    for key, value in pairs(a) do
        if (type(value) == "table") then 
            if not arrayIsEqual(value, b[key]) then return false end
        elseif (b[key]  ~= value)              then return false end
    end
    for key in pairs(b) do 
        if (a[key] == nil) then return false end
    end
    return true
end

local function arrayDeepCopy(from)
    local ary = {}
    if (from == nil)           then return ary  end
    if (type(from) ~= "table") then return from end
    for key, value in pairs(from) do 
        if (type(value) == "table") then ary[key] = arrayDeepCopy(value) 
        else                             ary[key] = value                end
    end
    return ary
end

local function saveConfig(force)
    if (not force) and ((not oldConfig) or arrayIsEqual(config, oldConfig)) then return end  -- 불필요한 저장은 수행할 필요가 없으니까
    json.dump_file(CONFIG_FILE, config)
    oldConfig = arrayDeepCopy(config)
end

local function loadConfig()
    local loaded = json.load_file(CONFIG_FILE)
    if not loaded then saveConfig(true) return end

    if     type(loaded.enabled)        ~= "boolean" then loaded.enabled        = true end
    if     type(loaded.cursorScale)    ~= "number"  then loaded.cursorScale    = 1.5  end
    if     type(loaded.showHistoryMax) ~= "number"  then loaded.showHistoryMax = 5    end
    if          loaded.lobbyHistory    == nil       then loaded.lobbyHistory   = {}
    elseif type(loaded.lobbyHistory)   ~= "table"   then loaded.lobbyHistory   = {}   end

    config    = arrayDeepCopy(loaded)
    oldConfig = arrayDeepCopy(loaded)
end loadConfig()

local function getAccurateTextWidth(text)
    if not text then return 0 end
    local str          = tostring(text)
    local base_width   = imgui.calc_text_size(str).x
    local char_count   = string.len(str)
    local microPadding = char_count * 1.8  -- 기본 폰트의 가변 길이 때문에 계산한 결과와 실제 표시에 필요한 길이 간에 오차가 발생할 수 있다. 보정치를 적용하여 그 차이를 줄인다.
    
    return base_width + microPadding
end

local function updateColumnWidth(history)
    local col1_max = imgui.calc_text_size(UI_TEXT.LOCKED_STAR).x * 2
    local col2_max = imgui.calc_text_size(UI_TEXT.LOBBY_ID).x
    local col3_max = imgui.calc_text_size(UI_TEXT.LANGUAGE).x
    local col4_max = math.max(imgui.calc_text_size(UI_TEXT.JOINED_AT).x, config.use24Hour and getAccurateTextWidth("2222-22-22 22:22:22") or getAccurateTextWidth("2222-22-22 PM 00:22:22"))  -- 가변 길이 문제가 발생했을 때를 대비해서 충분한 너비를 미리 확보한다.
    local col5_max = imgui.calc_text_size(UI_TEXT.DELETE_HEADER).x * 4

    for _, lobby in ipairs(history) do
        col2_max = math.max(col2_max, getAccurateTextWidth(lobby.id))
        col3_max = math.max(col3_max, getAccurateTextWidth(lobby.language))
        col4_max = math.max(col4_max, getAccurateTextWidth(lobby.joinedAt))
    end

    local padding_space = 100
    UI_COLUMN_WIDTH[1]  = col1_max
    UI_COLUMN_WIDTH[2]  = col2_max + padding_space
    UI_COLUMN_WIDTH[3]  = col3_max + padding_space
    UI_COLUMN_WIDTH[4]  = col4_max + padding_space
    UI_COLUMN_WIDTH[5]  = col5_max
end

local renderedLobbyList = {}
local renderedLockCount = 0
local function prepareUiData(isOnlyData)
    renderedLobbyList = {}
    renderedLockCount = 0
    for i, lobby in ipairs(config.lobbyHistory) do
        local timeFormat     = config.use24Hour and "%Y-%m-%d %H:%M:%S" or "%Y-%m-%d %p %I:%M:%S"
        local formattedTime  = os.date(timeFormat, lobby.timestamp)
        renderedLobbyList[i] = { id = tostring(lobby.id), language = tostring(lobby.language), joinedAt = formattedTime, isLock = lobby.isLock }
        if lobby.isLock then renderedLockCount = renderedLockCount + 1 end
    end

    if not isOnlyData then updateColumnWidth(renderedLobbyList) end
end

local function openWindow()
    prepareUiData()
    isWindowOpen = true
end

local function enterLobby(lobbyId)
    if not inputGuiPtr then return end
    inputGuiPtr:onCancel()
    inputGuiPtr:onTextInputDecided(lobbyId)
    inputGuiPtr = nil
end

local function deleteLobby(lobbyId)
    for i, lobby in ipairs(config.lobbyHistory) do 
        if lobby.id == lobbyId then
            table.remove(config.lobbyHistory, i)
            local count = #config.lobbyHistory
            if i < count then
                for k = i, count - 1 do
                    config.lobbyHistory[k] = arrayDeepCopy(config.lobbyHistory[k + 1])
                end
            end
            prepareUiData(true)
            saveConfig()
            break
        end
    end
end

-- 이제 쓸 일은 없을거라고 생각하지만 패치로 인해 문제가 생겼을 경우를 대비해서 남겨둔다.
local function generateEnumReverse(typename)
    local object = sdk.find_type_definition(typename)
    if not object then return {} end

    local fields = object:get_fields()
    local enum   = {}
    for i, field in ipairs(fields) do
        if field:is_static() then
        local name      = field:get_name()
        local raw_value = field:get_data()
        enum[raw_value] = name
        end
    end
    return enum
end
local WORLD_WIDE           = sdk.find_type_definition("ace_network.EnumPlayerLanguage"):get_field("WORLDWIDE"):get_data()
local LANGUAGE             = generateEnumReverse("app.LanguageDef.LANGUAGE_APP")
      LANGUAGE[WORLD_WIDE] = "Worldwide"
for index, name in pairs(LANGUAGE) do  -- app.LanguageDef.LANGUAGE_APP Enum 자체에 오타가 발견되어 수정한다.
    if     name == "TRANSITIONAL_CHINESE" then LANGUAGE[index] = "TRADITIONAL CHINESE" 
    elseif name == "SIMPLELIFIED_CHINESE" then LANGUAGE[index] = "SIMPLIFIED CHINESE"  
    else                                       LANGUAGE[index] = LANGUAGE[index]:gsub("_", " ") end
end

local getLanguageTextGuid = sdk.find_type_definition("app.CircleUtil"):get_method("getLanguageText(app.LanguageDef.LANGUAGE_APP)")
local getGuidToText       = sdk.find_type_definition("app.MessageUtil"):get_method("getText(System.Guid, System.Int32)")
sdk.hook(sdk.find_type_definition("app.net_lobby_session.cLobbySession"):get_method("websocketReceiveWelcome(app.Net_CloudSessionRequest.cWelcomePacket)"), function(args)
    local storage      = thread.get_hook_storage()
    storage["thisPtr"] = sdk.to_managed_object(args[2])
    isWindowOpen       = false
return sdk.PreHookResult.CALL_ORIGINAL end, function(retval)
    local storage            = thread.get_hook_storage()
    local thisPtr            = storage["thisPtr"]
    local settings           = thisPtr:get_Settings()
    local lobbyId            = settings:get_ShortId()        
    config.lastJoinedLobbyId = lobbyId

    local isLocked = false
    for i, lobby in ipairs(config.lobbyHistory) do 
        if lobby.id == lobbyId then 
            isLocked = lobby.isLock
            table.remove(config.lobbyHistory, i)
            break
        end
    end

    local removeCount = (#config.lobbyHistory >= HISTORY_MAX) and (#config.lobbyHistory - HISTORY_MAX + 1) or 0
    if removeCount > 0 then
        for i = #config.lobbyHistory, 1, -1 do
            local lobby = config.lobbyHistory[i]
            if (removeCount > 0) and not lobby.isLock then 
                removeCount = removeCount - 1
                table.remove(config.lobbyHistory, i)
            end
        end
    end

    local language
    local langId = settings:get_Language()
    local state, guid = pcall(function() return getLanguageTextGuid:call(nil, (langId ~= WORLD_WIDE) and langId or (-1)) end)
    if state     then state, language = pcall(function() return getGuidToText:call(nil, guid, 0) end) end
    if not state then        language = LANGUAGE[langId] or "Unknown"                                 end  -- 혹시나 해서 남겨둔다. 이상하게 표시되는 것보단 나을테니까.

    table.insert(config.lobbyHistory, 1, { id = lobbyId, language = language, timestamp = os.time(), isLock = isLocked })
    saveConfig()
return retval end)

sdk.hook(sdk.find_type_definition("app.GUI000016"):get_method("onOpen()"), function(args)
    inputGuiPtr = sdk.to_managed_object(args[2])
return sdk.PreHookResult.CALL_ORIGINAL end)

sdk.hook(sdk.find_type_definition("app.GUI000016"):get_method("onTextInputDecided(System.String)"), function(args)
    isWindowOpen = false
return sdk.PreHookResult.CALL_ORIGINAL end)

sdk.hook(sdk.find_type_definition("app.GUI000016"):get_method("onTextInputCanceled()"), function(args)
    isWindowOpen = false
return sdk.PreHookResult.CALL_ORIGINAL end)

local isCalledLobbyIdInputForm = false
sdk.hook(sdk.find_type_definition("app.cGUICommonMenu_Lobby09"):get_method("<execute>b__0_0(System.Int32)"), function(args)
    isCalledLobbyIdInputForm = true
return sdk.PreHookResult.CALL_ORIGINAL end)

sdk.hook(sdk.find_type_definition("app.GUIFlowTextInputForm.cContext"):get_method("onStartFlow(ace.IGUIFlowHandle)"), function(args)
    if not isCalledLobbyIdInputForm then return sdk.PreHookResult.CALL_ORIGINAL end
    local currentContext        = sdk.to_managed_object(args[2])
    isCalledLobbyIdInputForm    = false
    currentContext._DefaultText = config.lastJoinedLobbyId
    inputLobbyId                = config.lastJoinedLobbyId
    openWindow()
return sdk.PreHookResult.CALL_ORIGINAL end)
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
re.on_config_save(saveConfig)
local ImGuiCol = {
    WindowBg      = 4,
    Border        = 5, 
    Button        = 21,
    ButtonHovered = 22,
    ButtonActive  = 23,
}
local tooltipState = { shouldShow = false, x = 0, y = 0, message = "", color = 0xFF000000 }
local popupState   = { shouldOpenPopup = false, x = 0, y = 0, message = "", color = 0xFF4B4BFF, needCancelBtn = false, callbackOkFunc = nil, arg = nil }

local function drawInputSection()
    imgui.text(UI_TEXT.INPUT_LABEL)
    imgui.same_line()
    
    local changed, value = imgui.input_text("##LobbyIdInputForm", inputLobbyId, 16)
    if changed then
        if string.len(value) > 8 then 
            popupState.shouldOpenPopup = true
            local pos                  = imgui.get_mouse()
            popupState.message         = UI_TEXT.WARNING_MESSAGE
            popupState.x               = pos.x - math.floor(getAccurateTextWidth(popupState.message) * 0.45)
            popupState.y               = pos.y - (FONT_SIZE * 3)
            popupState.color           = 0xFF4B4BFF
            popupState.needCancelBtn   = false
            popupState.callbackOkFunc  = nil
            if string.len(inputLobbyId) < 8 then inputLobbyId = string.sub(value, 1, 8) end  -- 이미 8글자 채운 상태라면 저장 할 필요가 없다.
        else
            inputLobbyId = value
        end
    end

    imgui.same_line()
    imgui.push_style_color(ImGuiCol.Button,        0xFF2D5A27)
    imgui.push_style_color(ImGuiCol.ButtonHovered, 0xFF3D7A35)
    imgui.push_style_color(ImGuiCol.ButtonActive,  0xFF1B3817)
    imgui.push_style_var(imgui.ImGuiStyleVar.FrameRounding, 4.0)
    if imgui.button(UI_TEXT.BTN_ENTER, { FONT_SIZE * 4, FONT_SIZE + 6 }) and inputLobbyId then enterLobby(inputLobbyId) end    
    imgui.pop_style_color(3)
    imgui.pop_style_var(1)
end

local function drawWarningPopup()
    if popupState.shouldOpenPopup then
        imgui.open_popup("##ModalWarningPopup", 64)  -- 64:AlwaysAutoResize
        popupState.shouldOpenPopup = false 
    end

    imgui.set_next_window_pos({ popupState.x, popupState.y }, 0) 
    if imgui.begin_popup("##ModalWarningPopup", 64) then -- 64:AlwaysAutoResize
        imgui.spacing(); imgui.spacing(); imgui.spacing()
        imgui.text_colored(popupState.message, popupState.color) 
        imgui.spacing(); imgui.separator(); imgui.spacing()
        
        local windowWidth = imgui.get_window_size().x

        if not popupState.needCancelBtn then
            local buttonWidth   = FONT_SIZE * 3
            local buttonPadding = (windowWidth - buttonWidth) * 0.5
            if buttonPadding > 0 then
                local curPos = imgui.get_cursor_pos()
                curPos.x     = buttonPadding
                imgui.set_cursor_pos(curPos)
            end
            
            if imgui.button("  OK  ", { buttonWidth, FONT_SIZE + 6 }) then imgui.close_current_popup() end
        else
            local buttonWidth   = FONT_SIZE * 4
            local buttonPadding = (windowWidth + 20) * 0.5 - buttonWidth
            if buttonPadding > 0 then
                local curPos = imgui.get_cursor_pos()
                curPos.x     = buttonPadding
                imgui.set_cursor_pos(curPos)
            end
            
            if imgui.button(" Cancel ", { buttonWidth, FONT_SIZE + 6 }) then 
                imgui.close_current_popup() 
            end
            imgui.same_line()
            if imgui.button("   OK   ", { buttonWidth, FONT_SIZE + 6 }) then
                if popupState.callbackOkFunc then 
                    if type(popupState.arg) == "table" then
                        local unpackFunc = table.unpack or _G.unpack
                        popupState.callbackOkFunc(unpackFunc(popupState.arg))
                    else
                        popupState.callbackOkFunc(popupState.arg) 
                    end
                end
                imgui.close_current_popup() 
            end
        end
        imgui.spacing(); imgui.spacing()
        imgui.end_popup()
    end
end

local function drawLobbyTable() 
    if not imgui.begin_table("##LobbyIDListTable", 5, imgui.TableFlags.BordersInnerH, { 0, 0 }) then return end

    imgui.table_setup_column(UI_TEXT.LOCK,          imgui.ColumnFlags.WidthFixed, UI_COLUMN_WIDTH[1])
    imgui.table_setup_column(UI_TEXT.LOBBY_ID,      imgui.ColumnFlags.WidthFixed, UI_COLUMN_WIDTH[2])
    imgui.table_setup_column(UI_TEXT.LANGUAGE,      imgui.ColumnFlags.WidthFixed, UI_COLUMN_WIDTH[3])
    imgui.table_setup_column(UI_TEXT.JOINED_AT,     imgui.ColumnFlags.WidthFixed, UI_COLUMN_WIDTH[4])
    imgui.table_setup_column(UI_TEXT.DELETE_HEADER, imgui.ColumnFlags.WidthFixed, UI_COLUMN_WIDTH[5])
    imgui.table_next_row()
    imgui.table_set_bg_color(1, 0xFF282828, -1) 
    
    for i, headerText in ipairs(UI_TABLE_HEADERS) do 
        imgui.table_set_column_index(i - 1)
        local textWidth = imgui.calc_text_size(headerText).x
        local padding   = (UI_COLUMN_WIDTH[i] - textWidth) * 0.5
        if padding > 0 then 
            local cursorPos = imgui.get_cursor_pos()
            cursorPos.x     = cursorPos.x + padding
            imgui.set_cursor_pos(cursorPos)
        end
        imgui.text_colored(headerText, 0xFFC2D1E8)
    end
    
    for i, lobby in ipairs(renderedLobbyList) do 
        if i > config.showHistoryMax then break end 
        imgui.table_next_row()
        
        imgui.push_id(i)
        imgui.table_set_column_index(0)
        imgui.push_style_color(ImGuiCol.Button,        0x00000000)
        imgui.push_style_color(ImGuiCol.ButtonHovered, 0x00000000)
        imgui.push_style_color(ImGuiCol.ButtonActive,  0x00000000)
        if imgui.button(lobby.isLock and UI_TEXT.LOCKED_STAR or UI_TEXT.UNLOCKED_STAR) then
            local isLock = not lobby.isLock
            if not (isLock and renderedLockCount >= LOCK_MAX) then
                lobby.isLock                  = isLock
                config.lobbyHistory[i].isLock = isLock
                renderedLockCount             = renderedLockCount + (isLock and 1 or -1)
                saveConfig()
            end
        end
        imgui.pop_style_color(3)
        if imgui.is_item_hovered() then
            if not lobby.isLock and (renderedLockCount >= LOCK_MAX) then
                local mousePos          = imgui.get_mouse()
                tooltipState.shouldShow = true
                tooltipState.x          = mousePos.x
                tooltipState.y          = mousePos.y - FONT_SIZE
                tooltipState.message    = UI_TEXT.MAXIMUM_LOCK
                tooltipState.color      = 0xFF0000FF
            end
        end

        imgui.table_set_column_index(1)
        imgui.push_style_color(ImGuiCol.Button,        0xFF4A3B32)
        imgui.push_style_color(ImGuiCol.ButtonHovered, 0xFF6E594B)
        imgui.push_style_color(ImGuiCol.ButtonActive,  0xFF2D231E)
        imgui.push_style_color(ImGuiCol.Border,        0xFF9E8472)
        imgui.push_style_var(imgui.ImGuiStyleVar.FrameRounding,   4.0)
        imgui.push_style_var(imgui.ImGuiStyleVar.FrameBorderSize, 1.0)
        
        if imgui.button(lobby.id, { UI_COLUMN_WIDTH[2], FONT_SIZE + 4 }) then enterLobby(lobby.id) end
        if imgui.is_item_hovered() then
            local mousePos          = imgui.get_mouse()
            tooltipState.shouldShow = true
            tooltipState.x          = mousePos.x
            tooltipState.y          = mousePos.y - FONT_SIZE
            tooltipState.message    = UI_TEXT.CLICK_TO_JOIN
            tooltipState.color      = 0xFF1FFFFF
        end
        
        imgui.pop_style_color(4) 
        imgui.pop_style_var(2)

        imgui.table_set_column_index(2)
        local textWidth = imgui.calc_text_size(lobby.language).x
        local padding   = (UI_COLUMN_WIDTH[3] - textWidth) * 0.5
        if padding > 0 then 
            local cursorPos = imgui.get_cursor_pos()
            cursorPos.x     = cursorPos.x + padding
            imgui.set_cursor_pos(cursorPos)
        end
        imgui.text(lobby.language)

        imgui.table_set_column_index(3)
        local textWidth = imgui.calc_text_size(lobby.joinedAt).x
        local padding   = (UI_COLUMN_WIDTH[4] - textWidth) * 0.5
        if padding > 0 then 
            local cursorPos = imgui.get_cursor_pos()
            cursorPos.x     = cursorPos.x + padding
            imgui.set_cursor_pos(cursorPos)
        end
        imgui.text(lobby.joinedAt)

        imgui.table_set_column_index(4)
        imgui.push_style_color(ImGuiCol.Button,        lobby.isLock and 0x00000000 or 0xFF4A3B32)
        imgui.push_style_color(ImGuiCol.ButtonHovered, lobby.isLock and 0x00000000 or 0xFF6E594B)
        imgui.push_style_color(ImGuiCol.ButtonActive,  lobby.isLock and 0x00000000 or 0xFF2D231E)
        imgui.push_style_color(ImGuiCol.Border,        lobby.isLock and 0x309E8472 or 0xFF9E8472)
        imgui.push_style_var(imgui.ImGuiStyleVar.FrameRounding,   4.0)
        imgui.push_style_var(imgui.ImGuiStyleVar.FrameBorderSize, 1.0)
        if imgui.button(UI_TEXT.DELETE_BUTTON) then
            if not lobby.isLock then 
                popupState.shouldOpenPopup = true
                local pos                  = imgui.get_mouse()
                popupState.message         = "  Are you sure you want to delete \'" .. lobby.id ..  "\'?  "
                popupState.x               = pos.x - math.floor(getAccurateTextWidth(popupState.message) * 0.8)
                popupState.y               = pos.y - (FONT_SIZE * 3)
                popupState.color           = 0xFF4B4BFF
                popupState.needCancelBtn   = true
                popupState.callbackOkFunc  = deleteLobby
                popupState.arg             = lobby.id
                prepareUiData(true)
            end
        end
        imgui.pop_style_color(4)
        imgui.pop_style_var(2)

        imgui.pop_id()
    end  -- for i, lobby in ipairs(renderedLobbyList) do 
    imgui.end_table()
end

local function drawCustomTooltip() 
    if tooltipState.shouldShow then
        imgui.set_next_window_pos({tooltipState.x, tooltipState.y}, 0)
        imgui.push_style_color(ImGuiCol.WindowBg, 0xB0000000)
        imgui.push_style_color(ImGuiCol.Boder,    0x00000000)
        imgui.begin_tooltip() 
        imgui.text_colored(tooltipState.message, tooltipState.color)
        imgui.end_tooltip()
        imgui.pop_style_color(2)
        tooltipState.shouldShow = false 
    end
end

re.on_frame(function() 
    if not isWindowOpen then return end
    if not imgui.begin_window(MOD_TITLE, nil, 120) then return end  -- 8:NoScrollBar, 16:NoScrollWithMouse, 32:NoCollapse, 64:AlwaysAutoResize
    imgui.spacing(); imgui.spacing()
    imgui.push_font_size(FONT_SIZE)
    
    drawInputSection()
    imgui.spacing(); imgui.separator(); imgui.spacing()
    
    if next(renderedLobbyList) then drawLobbyTable()
    else                            imgui.spacing(); imgui.text(UI_TEXT.NO_RECORD); imgui.spacing() end

    drawWarningPopup()
    drawCustomTooltip()
    CursorHelper.draw_custom_cursor(config.cursorScale)
    imgui.pop_font_size()
    imgui.end_window() 
end)


re.on_draw_ui(function() if not imgui.tree_node(MOD_TITLE) then return end
    imgui.spacing()
    imgui.text("Cursor scale:")
    local changed, value = imgui.slider_float("##CursorScale", config.cursorScale, 0.5, 3, "%.1f")
    if changed then config.cursorScale = math.floor((value + 0.05) * 10) / 10 end

    imgui.spacing()
    imgui.text("Show History Maximum:")
    changed, config.showHistoryMax = imgui.slider_int("##ShowHistoryMax", config.showHistoryMax, 1, 20, "%d")

    imgui.spacing()
    changed, config.use24Hour = imgui.checkbox("Use 24-Hour Time Format", config.use24Hour)
    if changed then prepareUiData() end

    imgui.spacing()
imgui.tree_pop() end)