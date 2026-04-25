--[[
    LD Combat Stats - HistoryList.lua
    历史段落选择器
]]

local addonName, ns = ...
local L = ns.L

local HL = {}
ns.HistoryList = HL

local LIST_W   = 220
local ITEM_H   = 20
local MAX_SHOW = 12   -- 历史记录超过12条时显示滚动条

local T = {
    bg       = {0.04, 0.04, 0.07, 0.97},
    border   = {0.22, 0.22, 0.30, 0.90},
    hover    = {0.15, 0.45, 0.75, 0.30},
    active   = {0.10, 0.60, 1.00, 0.25},
    text     = {1,    1,    1,    0.90},
    dim      = {0.55, 0.55, 0.55, 0.85},
    sep      = {0.25, 0.25, 0.30, 0.60},
}

-- ============================================================
-- 创建
-- ============================================================
function HL:EnsureCreated()
    if self.frame then return end
    self:Build()
end

function HL:Build()
    local f = CreateFrame("Frame", "LightDamageHistory", UIParent, "BackdropTemplate")
    f:SetWidth(LIST_W)
    f:SetFrameStrata("HIGH"); f:SetFrameLevel(100)
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(unpack(T.bg))

    local bc = ns.db and ns.db.window and ns.db.window.borderColor or {0.2, 0.2, 0.25, 1}
    f:SetBackdropBorderColor(unpack(bc))
    f:Hide(); f:EnableMouse(true)
    f:SetScript("OnHide", function() self._open = false end)

    local clickOut = CreateFrame("Frame", nil, UIParent)
    clickOut:SetAllPoints(UIParent); clickOut:SetFrameStrata("HIGH"); clickOut:SetFrameLevel(99)
    clickOut:EnableMouse(true); clickOut:Hide()
    clickOut:SetScript("OnMouseDown", function() self:Hide() end)
    self._clickOut = clickOut

    -- 滚动框架 (用于历史段落)
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", 1, -1)
    local child = CreateFrame("Frame", nil, sf)
    child:SetWidth(LIST_W - 18)
    sf:SetScrollChild(child)

    -- 极简风格滚动条
    local sb = CreateFrame("Slider", nil, sf)
    sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 0, 0)
    sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 0, 0)
    sb:SetMinMaxValues(0, 0); sb:SetValueStep(1); sb:SetValue(0)
    sb:SetWidth(4); sb:SetOrientation("VERTICAL")
    
    local sbTrack = sb:CreateTexture(nil, "BACKGROUND")
    sbTrack:SetAllPoints()
    sbTrack:SetColorTexture(0.05, 0.05, 0.06, 1)
    
    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local sbThumb = sb:GetThumbTexture()
    sbThumb:SetVertexColor(0.3, 0.3, 0.35, 1)
    sbThumb:SetSize(4, 30)
    
    sb:SetScript("OnEnter", function() sbThumb:SetVertexColor(0.4, 0.4, 0.45, 1) end)
    sb:SetScript("OnLeave", function() sbThumb:SetVertexColor(0.3, 0.3, 0.35, 1) end)
    
    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue()
        local maxVal = select(2, sb:GetMinMaxValues())
        sb:SetValue(math.max(0, math.min(maxVal, cur - delta * ITEM_H * 2)))
    end)
    sb:SetScript("OnValueChanged", function(_, value) sf:SetVerticalScroll(value) end)

    -- 分割线与常驻容器
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1); sep:SetColorTexture(unpack(T.sep))
    local pinned = CreateFrame("Frame", nil, f)

    -- ★ 新增：清空野外记录按钮
    local clrBtn = CreateFrame("Button", nil, f)
    clrBtn:SetHeight(18)
    local cbBg = clrBtn:CreateTexture(nil, "BACKGROUND")
    cbBg:SetAllPoints(); cbBg:SetColorTexture(0.20, 0.05, 0.05, 0.8)
    local cbHl = clrBtn:CreateTexture(nil, "HIGHLIGHT")
    cbHl:SetAllPoints(); cbHl:SetColorTexture(0.40, 0.10, 0.10, 0.9)
    local cbTxt = clrBtn:CreateFontString(nil, "OVERLAY")
    cbTxt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    cbTxt:SetPoint("CENTER")
    cbTxt:SetText(L["[一键清空野外战斗]"])
    cbTxt:SetTextColor(1, 0.4, 0.4)
    
    clrBtn:SetScript("OnClick", function()
        if ns.Segments then
            local cleaned = {}
            for _, seg in ipairs(ns.Segments.history) do
                -- 判断是否保留：是大秘境、Boss战、副本融合段、或者带副本Tag的战斗
                local keep = false
                if seg.type == "mythicplus" or seg.type == "boss" then keep = true end
                if seg._isBoss or seg._isMerged or seg._instanceTag then keep = true end
                
                if keep then table.insert(cleaned, seg) end
            end
            ns.Segments.history = cleaned
            
            -- 如果删除了当前正在查看的视图，切回总计
            local viewIdx = ns.Segments.viewIndex
            if viewIdx and viewIdx > 0 and not ns.Segments.history[viewIdx] then
                ns.Segments.viewIndex = #ns.Segments.history > 0 and 1 or 0
            end
            
            -- 如果当前在野外，连带清空当前的 overall 和重置 API Baseline
            if not ns.state.isInInstance then
                if C_DamageMeter.ResetAllCombatSessions then
                    ns.CombatTracker:ClearLoadedSessionIDs()
                    ns.CombatTracker._internalReset = true
                    C_DamageMeter.ResetAllCombatSessions()
                end
                if ns.CombatTracker then 
                    ns.CombatTracker._baselineSessionCount = 0
                    ns.CombatTracker._lastProcessedCount = 0
                end
                ns.Segments.overall = ns.Segments:NewSegment("overall", L["总计"])
            end

            -- ★ 一键清空后不再显示空白页面，而是跳转到最新的段落
            if #ns.Segments.history > 0 then
                ns.Segments.viewIndex = 1
            else
                ns.Segments.viewIndex = nil -- 跳转到当前实时
            end

            if ns.UI then ns.UI:Refresh() end
        end
        self:Hide()
        print(L["|cff00ccff[Light Damage]|r 已清空所有野外历史记录，只保留副本与首领战数据。"])
    end)
    self.clearBtn = clrBtn

    self.frame = f; self.scrollFrame = sf; self.scrollChild = child
    self.scrollBar = sb; self.sep = sep; self.pinnedContainer = pinned
    self._histItems = {}; self._pinnedItems = {}; self._open = false
end

function HL:Toggle(anchorFrame)
    self:EnsureCreated()
    if self._open then self:Hide() else self:Show(anchorFrame) end
end

function HL:Show(anchorFrame)
    self:Rebuild()
    self.frame:ClearAllPoints()
    if anchorFrame then
        -- 向上弹出：将列表的底部对齐到锚点(标题栏)的顶部
        self.frame:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 2)
    else
        self.frame:SetPoint("CENTER", UIParent, "CENTER")
    end
    self.frame:Show(); self._clickOut:Show(); self._open = true
end

function HL:Hide()
    if self.frame then self.frame:Hide() end
    if self._clickOut then self._clickOut:Hide() end
    self._open = false
end

-- ============================================================
-- 重建列表内容
-- ============================================================
function HL:Rebuild()
    local segs = ns.Segments
    if not segs then self.frame:Hide(); return end
    local list = segs:GetHistoryList()
    if not list or #list == 0 then self.frame:Hide(); return end

    -- 分离当前 与 历史段落
    local histData = {}; local pinnedData = {}
    for _, data in ipairs(list) do
        if data.key == "current" then
            table.insert(pinnedData, data)
        elseif data.key == "history" then
            table.insert(histData, data)
        end
    end

    local curKey, curIdx = segs:GetViewKey()
    local isLocked = ns.Segments._locked

    -- 渲染历史记录
    for i, data in ipairs(histData) do
        local item = self._histItems[i]
        if not item then item = self:MakeItem(self.scrollChild); self._histItems[i] = item end
        self:SetupItem(item, data, curKey, curIdx, isLocked)
        item.frame:ClearAllPoints()
        item.frame:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -(i-1)*ITEM_H)
        item.frame:SetPoint("TOPRIGHT", self.scrollChild, "TOPRIGHT", 0, -(i-1)*ITEM_H)
        item.frame:Show()
    end
    for i = #histData + 1, #self._histItems do self._histItems[i].frame:Hide() end

    -- 渲染常驻项
    for i, data in ipairs(pinnedData) do
        local item = self._pinnedItems[i]
        if not item then item = self:MakeItem(self.pinnedContainer); self._pinnedItems[i] = item end
        self:SetupItem(item, data, curKey, curIdx, isLocked)
        item.frame:ClearAllPoints()
        item.frame:SetPoint("TOPLEFT", self.pinnedContainer, "TOPLEFT", 1, -(i-1)*ITEM_H)
        item.frame:SetPoint("TOPRIGHT", self.pinnedContainer, "TOPRIGHT", -1, -(i-1)*ITEM_H)
        item.frame:Show()
    end
    for i = #pinnedData + 1, #self._pinnedItems do self._pinnedItems[i].frame:Hide() end

    -- 高度与滚动逻辑计算
    local showHistCount = math.min(#histData, MAX_SHOW)
    local histHeight = showHistCount * ITEM_H
    local pinnedHeight = #pinnedData * ITEM_H

    self.scrollChild:SetHeight(#histData * ITEM_H)
    if #histData > MAX_SHOW then
        self.scrollFrame:SetHeight(histHeight)
        self.scrollBar:SetMinMaxValues(0, (#histData - MAX_SHOW) * ITEM_H)
        self.scrollBar:Show()
        self.scrollFrame:SetPoint("TOPRIGHT", -5, -1) -- 缩窄边距，给 4 像素宽的极简滚动条让路
    else
        self.scrollFrame:SetHeight(histHeight)
        self.scrollBar:SetMinMaxValues(0, 0)
        self.scrollBar:Hide()
        self.scrollFrame:SetPoint("TOPRIGHT", -1, -1)
    end

    -- 排版分割线与底部常驻项
    self.sep:ClearAllPoints()
    self.sep:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, -(histHeight + 2))
    self.sep:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -4, -(histHeight + 2))
    
    if #histData > 0 and #pinnedData > 0 then
        self.sep:Show()
        self.pinnedContainer:SetPoint("TOPLEFT", self.sep, "BOTTOMLEFT", -4, -2)
        self.pinnedContainer:SetPoint("TOPRIGHT", self.sep, "BOTTOMRIGHT", 4, -2)
    else
        self.sep:Hide()
        self.pinnedContainer:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, -(histHeight + 1))
        self.pinnedContainer:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", 0, -(histHeight + 1))
    end
    self.pinnedContainer:SetHeight(pinnedHeight)

    -- 排版最底部的“清空野外战斗”按钮
    self.clearBtn:ClearAllPoints()
    self.clearBtn:SetPoint("TOPLEFT", self.pinnedContainer, "BOTTOMLEFT", 1, -2)
    self.clearBtn:SetPoint("TOPRIGHT", self.pinnedContainer, "BOTTOMRIGHT", -1, -2)

    -- 计算整体大框架的高度 (历史区 + 常驻区 + 按钮区18px + 各个间距)
    local totalFrameHeight = histHeight + pinnedHeight + 18 + (#histData > 0 and #pinnedData > 0 and 5 or 2) + 2
    self.frame:SetHeight(totalFrameHeight)
    
    -- ★ 历史列表默认看最下方最新的段落
    if #histData > MAX_SHOW then
        local maxVal = (#histData - MAX_SHOW) * ITEM_H
        self.scrollBar:SetValue(maxVal)
        self.scrollFrame:SetVerticalScroll(maxVal)
    end
end

function HL:SetupItem(item, data, curKey, curIdx, isLocked)
    item.data = data; item.text:SetText(data.label)
    local isHistory = data.key == "history"
    local isActive = (data.key == curKey) and (data.key == "overall" or data.key == "current" or data.index == curIdx)

    -- 战斗中允许查看但禁止删除（防止数据竞态）
    if isHistory and not isLocked then
        item.delBtn:Show()
    else
        item.delBtn:Hide()
    end

    if isActive then
        item.activeBg:Show(); item.text:SetTextColor(1, 1, 1, 1)
    else
        item.activeBg:Hide(); item.text:SetTextColor(unpack(T.text))
    end
    item.frame:SetEnabled(true)
end

function HL:MakeItem(parent)
    local item = {}
    local f = CreateFrame("Button", nil, parent); f:SetHeight(ITEM_H)

    local activeBg = f:CreateTexture(nil, "BACKGROUND"); activeBg:SetAllPoints(); activeBg:SetColorTexture(unpack(T.active)); activeBg:Hide()
    item.activeBg = activeBg
    local hl = f:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(unpack(T.hover))

    -- ★ 新增：最右侧的独立删除按钮
    local delBtn = CreateFrame("Button", nil, f)
    delBtn:SetSize(16, 16)
    delBtn:SetPoint("RIGHT", -4, 0)
    local delTxt = delBtn:CreateFontString(nil, "OVERLAY")
    delTxt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    delTxt:SetPoint("CENTER")
    delTxt:SetText("X")
    delTxt:SetTextColor(0.6, 0.2, 0.2)
    -- 悬停高亮为亮红色
    delBtn:SetScript("OnEnter", function() delTxt:SetTextColor(1, 0.2, 0.2) end)
    delBtn:SetScript("OnLeave", function() delTxt:SetTextColor(0.6, 0.2, 0.2) end)
    item.delBtn = delBtn

    -- 标题文字（右侧锚点避开删除按钮）
    local txt = f:CreateFontString(nil, "OVERLAY"); txt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    txt:SetPoint("LEFT", 8, 0)
    txt:SetPoint("RIGHT", delBtn, "LEFT", -4, 0) -- ★ 留出删除按钮的空间
    txt:SetJustifyH("LEFT"); txt:SetWordWrap(false)
    item.text = txt

    -- ★ 核心：删除按钮的点击逻辑（无二次确认）
    delBtn:SetScript("OnClick", function()
        local data = item.data
        if not data or not ns.Segments then return end
        if ns.Segments._locked then return end -- 战斗中严格禁止删除历史记录

        if data.key == "history" and data.index then
            -- 1. 修正 viewIndex 偏移（核心保护机制，防止底层渲染空指针）
            if ns.Segments.viewIndex == data.index then
                -- 如果删的是当前正在看的，退回第一个或总计
                ns.Segments.viewIndex = #ns.Segments.history > 1 and 1 or 0
            elseif ns.Segments.viewIndex and ns.Segments.viewIndex > data.index then
                -- 如果删的是当前观看记录前方的记录，索引 -1 以维持观看当前条目
                ns.Segments.viewIndex = ns.Segments.viewIndex - 1
            end

            -- 2. 物理删除
            table.remove(ns.Segments.history, data.index)

            -- 清理数据分析缓存，强制 UI 读取扣除后的最新总伤害
            if ns.Analysis then ns.Analysis:InvalidateCache() end

            -- 3. 数据固化及 UI 刷新
            if ns.SaveSessionHistory then ns:SaveSessionHistory() end
            if ns.UI then ns.UI:Refresh() end
            
            -- 4. 重新构建当前列表（更新所有余下条目的 data.index）
            self:Rebuild()
        end
    end)

    -- 原有的行点击逻辑（切换段落）
    f:SetScript("OnClick", function()
        local data = item.data; if not data then return end
        local isLocked = ns.Segments and ns.Segments._locked
        if isLocked and data.key == "history" then return end
        if ns.Segments then ns.Segments:SetViewByKey(data.key, data.index) end
        self:Hide()
    end)
    
    item.frame = f
    return item
end

function HL:IsOpen() return self._open end