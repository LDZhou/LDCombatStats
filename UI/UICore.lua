--[[
    Light Damage - UICore.lua
    主界面：框架创建、标题栏、基础结构
]]

local addonName, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local BAR_H   = 18
local BAR_GAP = 1
local TITLE_H = 22
local SUMM_H  = 16
local SECTH_H = 18
local TAB_H   = 20
local MAX_BARS = 40

-- 导出常量供其他 UI 文件使用
UI.BAR_H = BAR_H; UI.BAR_GAP = BAR_GAP; UI.TITLE_H = TITLE_H
UI.SUMM_H = SUMM_H; UI.SECTH_H = SECTH_H; UI.TAB_H = TAB_H; UI.MAX_BARS = MAX_BARS

local T = {
    dmgC   = {1.0, 0.82, 0.0},
    healC  = {0.4, 1.0, 0.4},
    takenC = {1.0, 0.3, 0.3},
    accent = {0.0, 0.65, 1.0},
}
UI.T = T

local MODE_TO_DM = {
    damage      = Enum.DamageMeterType.DamageDone,
    healing     = Enum.DamageMeterType.HealingDone,
    damageTaken = Enum.DamageMeterType.DamageTaken,
    interrupts  = Enum.DamageMeterType.Interrupts,
    dispels     = Enum.DamageMeterType.Dispels,
    deaths      = Enum.DamageMeterType.Deaths,
    enemyDamageTaken   = Enum.DamageMeterType.EnemyDamageTaken,
}
UI.MODE_TO_DM = MODE_TO_DM

local COUNT_MODES = { deaths=true, interrupts=true, dispels=true }
UI.COUNT_MODES = COUNT_MODES

local TEX = "Interface\\AddOns\\" .. addonName .. "\\Textures\\"
UI.TEX = TEX

-- ============================================================
-- 工具函数
-- ============================================================
function UI:FillBg(f, c)
    local t = f:CreateTexture(nil,"BACKGROUND"); t:SetAllPoints()
    t:SetColorTexture(unpack(c)); return t
end

function UI:FS(p, sz, fl)
    local f = p:CreateFontString(nil,"OVERLAY")
    f:SetFont(STANDARD_TEXT_FONT, sz, fl or "")
    f:SetTextColor(1, 1, 1, 0.93); return f
end

function UI:Btn(p, lbl, sz, fn)
    local b = CreateFrame("Button", nil, p); b:SetSize(18, TITLE_H)
    b.text = self:FS(b, sz, "OUTLINE"); b.text:SetPoint("CENTER")
    b.text:SetText(lbl); b.text:SetTextColor(0.55, 0.55, 0.55)
    b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function() b.text:SetTextColor(1,1,1) end)
    b:SetScript("OnLeave", function() b.text:SetTextColor(0.55,0.55,0.55) end)
    return b
end

function UI:IconBtn(p, texNormal, texHover, btnW, fn)
    local iconSize = TITLE_H - 6
    local b = CreateFrame("Button", nil, p); b:SetSize(btnW or 20, TITLE_H); b:EnableMouse(true)
    local t = b:CreateTexture(nil, "ARTWORK"); t:SetSize(iconSize, iconSize); t:SetPoint("CENTER")
    t:SetTexture(texNormal); t:SetVertexColor(0.65, 0.65, 0.65, 1)
    b.iconTex = t; b.texNormal = texNormal; b.texHover = texHover or texNormal
    b:SetScript("OnEnter", function() t:SetTexture(b.texHover); t:SetVertexColor(1, 1, 1, 1) end)
    b:SetScript("OnLeave", function() t:SetTexture(b.texNormal); t:SetVertexColor(0.65, 0.65, 0.65, 1) end)
    b:SetScript("OnClick", fn)
    return b
end

function UI:IsOverallColumnActive()
    if not ns.db or not ns.db.split then return false end
    if not ns.db.split.showOverall then return false end
    local cat = ns.state.instanceCategory or "outdoor"
    if cat == "mplus" and ns.db.split.overallShowMPlus then return true end
    if cat == "raid" and ns.db.split.overallShowRaid then return true end
    if cat == "dungeon" and ns.db.split.overallShowDungeon then return true end
    if cat == "outdoor" and ns.db.split.overallShowOutdoor then return true end
    return false
end

function UI:IsSplitActiveInCurrentScene()
    if not ns.db or not ns.db.split then return false end
    if not ns.db.split.enabled then return false end
    local cat = ns.state.instanceCategory or "outdoor"
    if cat == "mplus" and ns.db.split.splitShowMPlus then return true end
    if cat == "raid" and ns.db.split.splitShowRaid then return true end
    if cat == "dungeon" and ns.db.split.splitShowDungeon then return true end
    if cat == "outdoor" and ns.db.split.splitShowOutdoor then return true end
    return false
end

function UI:ApplyTheme()
    local dbw = ns.db.window
    local tc = dbw.themeColor or {0.08, 0.08, 0.12, 1}
    local bc = dbw.bgColor    or {0.04, 0.04, 0.05, 0.90}
    if self.frame    then self.frame:SetBackdropColor(unpack(bc)) end
    if self.titleBg  then self.titleBg:SetColorTexture(unpack(tc)) end
    if self.tabBg    then self.tabBg:SetColorTexture(unpack(tc)) end
    if self.summBg   then self.summBg:SetColorTexture(tc[1]*0.8, tc[2]*0.8, tc[3]*0.8, tc[4]) end
    local sc = {tc[1]*0.9, tc[2]*0.9, tc[3]*0.9, tc[4]}
    if self.priHead    then self.priHead.bg:SetColorTexture(unpack(sc)) end
    if self.secHead    then self.secHead.bg:SetColorTexture(unpack(sc)) end
    if self.ovrPriHead then self.ovrPriHead.bg:SetColorTexture(unpack(sc)) end
    if self.ovrSecHead then self.ovrSecHead.bg:SetColorTexture(unpack(sc)) end
    if self.ovrContainer then
        local c = dbw.ovrBgColor or {0.02, 0.04, 0.08, 0.95}
        self.ovrContainer:SetBackdropColor(unpack(c))
    end
end

function UI:GetBarConfig()
    local db = ns.db.display
    return db.barHeight or 18, db.barGap or 1, db.barAlpha or 0.85,
           db.font or STANDARD_TEXT_FONT, db.fontSizeBase or 12,
           db.fontOutline or "OUTLINE", db.fontShadow or false
end

function UI:ApplyFont(fs, font, size, outline, shadow)
    local hash = font .. "|" .. size .. "|" .. (outline or "") .. "|" .. (shadow and "1" or "0")
    if fs._fontHash == hash then return end
    fs._fontHash = hash
    fs:SetFont(font, size, outline)
    if shadow then fs:SetShadowColor(0,0,0,1); fs:SetShadowOffset(1,-1)
    else fs:SetShadowOffset(0,0) end
end

function UI:ApplyAllFontsIfNeeded()
    local db = ns.db.display
    local hash = (db.font or "") .. "|" .. (db.fontSizeBase or 10) .. "|" .. (db.fontOutline or "")
    if hash == self._lastFontHash then return end
    self._lastFontHash = hash
    self:ApplyAllFonts()
end

function UI:ApplyAllFonts()
    if not self.frame then return end
    local _, _, _, font, fSz, fOut, fShad = self:GetBarConfig()
    if self.titleText then self:ApplyFont(self.titleText, font, fSz, fOut, fShad) end
    if self.titleTime then self:ApplyFont(self.titleTime, font, fSz, fOut, fShad) end
    if self.summText then self:ApplyFont(self.summText, font, fSz - 1, fOut, fShad) end
    local function applyHead(h)
        if h then self:ApplyFont(h.label, font, fSz - 1, fOut, fShad); self:ApplyFont(h.info, font, fSz - 1, fOut, fShad) end
    end
    applyHead(self.priHead); applyHead(self.secHead); applyHead(self.ovrPriHead); applyHead(self.ovrSecHead)
    if self.tabs then for _, t in ipairs(self.tabs) do self:ApplyFont(t.text, font, fSz - 1, fOut, fShad) end end
    if self.splitTab then self:ApplyFont(self.splitTab.text, font, fSz - 1, fOut, fShad) end
end

function UI:GetCachedSession(sessionType, dmType)
    local key = tostring(sessionType) .. "|" .. tostring(dmType)
    if not self._sessionCache[key] then
        self._sessionCache[key] = C_DamageMeter.GetCombatSessionFromType(sessionType, dmType)
    end
    return self._sessionCache[key]
end

function UI:EnsureCreated() if self.frame then return end; self:Build() end

-- ============================================================
-- Build 主框架
-- ============================================================
function UI:Build()
    local db = ns.db.window
    BAR_H = ns.db.display.barHeight or 18

    local f = CreateFrame("Frame","LightDamageFrame",UIParent,"BackdropTemplate")
    f:SetSize(db.width, db.height)
    if db.rememberSceneSize and db.sceneSizes then
        local cat = ns.state.instanceCategory or "outdoor"
        local s = db.sceneSizes[cat]
        if s then f:SetSize(s.width, s.height) end
    end
    f:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    f:SetScale(db.scale); f:SetAlpha(db.alpha)
    f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(10)
    f:SetClampedToScreen(true); f:EnableMouse(true)
    f:SetMovable(true); f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(250, 180, 1000, 900) end
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile=nil, edgeSize=0 })
    f:SetClipsChildren(true)
    self.frame = f

    self:BuildTitle(); self:BuildMPlusSummary(); self:BuildBody()
    self:BuildTabs(); self:BuildResize(); self:SetupDrag()
    self:ApplyTheme()
    f:HookScript("OnSizeChanged", function() self:OnResize() end)

    if ns.db.window.visible == false then f:Hide()
    else f:Show(); self:Layout() end

    self:CheckAutoCollapse(true)
    self._lastFontHash = nil
    self._sessionCache = {}

    -- 渐隐系统初始化
    self._faded = false; self._fadeAnimating = false; self._wasMouseOver = false
    local fadeHoverFrame = CreateFrame("Frame")
    fadeHoverFrame._timer = 0
    fadeHoverFrame:SetScript("OnUpdate", function(frame, elapsed)
        frame._timer = frame._timer + elapsed
        if frame._timer < 0.1 then return end; frame._timer = 0
        if not self._faded then return end
        if not ns.db or not ns.db.fade then return end
        if not (ns.db.fade.fadeBars or ns.db.fade.fadeBody) then return end
        if not ns.db.fade.unfadeOnHover then return end
        if not self.frame or not self.frame:IsShown() then return end
        local isOver = self.frame:IsMouseOver()
        if isOver and not self._wasMouseOver then self:ApplyFadeAlpha(false, false)
        elseif not isOver and self._wasMouseOver then self:CheckAutoFade(true) end
        self._wasMouseOver = isOver
    end)
    self._fadeHoverFrame = fadeHoverFrame
    C_Timer.After(0.5, function()
        if self.frame and self.frame:IsShown() and not ns.state.inCombat then self:CheckAutoFade(true) end
    end)
end

function UI:BuildTitle()
    local b = CreateFrame("Frame", nil, self.frame)
    b:SetHeight(TITLE_H); b:SetPoint("TOPLEFT",0,0); b:SetPoint("TOPRIGHT",0,0)
    self.titleBg = self:FillBg(b, {0.08, 0.08, 0.12, 1})
    self.titleBar = b

    local listBtn = self:Btn(b, "[=]", 12, function() if ns.HistoryList then ns.HistoryList:Toggle(b) end end)
    listBtn:SetPoint("LEFT", 4, 0); listBtn:SetSize(22, TITLE_H); self.listBtn = listBtn

    self.titleText = self:FS(b, 10, "OUTLINE")
    self.titleText:SetPoint("LEFT", listBtn, "RIGHT", 4, 0)
    self.titleText:SetPoint("RIGHT", b, "RIGHT", -72, 0)
    self.titleText:SetJustifyH("LEFT"); self.titleText:SetWordWrap(false)

    local titleBtn = CreateFrame("Button", nil, b)
    titleBtn:SetPoint("LEFT", listBtn, "RIGHT", 0, 0); titleBtn:SetPoint("RIGHT", b, "RIGHT", -72, 0); titleBtn:SetHeight(TITLE_H)
    titleBtn:SetScript("OnClick", function() if ns.HistoryList then ns.HistoryList:Toggle(b) end end)
    titleBtn:RegisterForDrag("LeftButton")
    titleBtn:SetScript("OnDragStart", function() if not ns.db.window.locked then self.frame:StartMoving() end end)
    titleBtn:SetScript("OnDragStop", function()
        self.frame:StopMovingOrSizing()
        local db = ns.db.window
        local point, relativeTo, relPoint, x, y = self.frame:GetPoint()
        db.point = point; db.relPoint = relPoint; db.x = x; db.y = y
        if self._collapsed then self._savedAnchor = { point, relativeTo, relPoint, x, y } end
    end)

    self._collapsed = false
    local colBtn = self:IconBtn(b, TEX.."btn_collapse", TEX.."btn_collapse", 20, function() self:ToggleCollapse(not self._collapsed) end)
    colBtn:SetPoint("RIGHT", -4, 0); self.collapseBtn = colBtn

    local cfgBtn = self:IconBtn(b, TEX.."btn_settings", TEX.."btn_settings", 20, function() if ns.Config then ns.Config:Toggle() end end)
    cfgBtn:SetPoint("RIGHT", colBtn, "LEFT", -2, 0); self.cfgBtn = cfgBtn

    local rstBtn = self:IconBtn(b, TEX.."btn_reset", TEX.."btn_reset", 20, function() if ns.Segments then ns.Segments:ResetAll() end end)
    rstBtn:SetPoint("RIGHT", cfgBtn, "LEFT", -2, 0); self.rstBtn = rstBtn

    self.titleTime = self:FS(b, 10, "OUTLINE")
    self.titleTime:SetPoint("RIGHT", rstBtn, "LEFT", -4, 0)
    self.titleTime:SetJustifyH("RIGHT"); self.titleTime:SetTextColor(0.67, 0.67, 0.67)
    self.titleText:ClearAllPoints()
    self.titleText:SetPoint("LEFT", listBtn, "RIGHT", 4, 0)
    self.titleText:SetPoint("RIGHT", self.titleTime, "LEFT", -2, 0)
end

function UI:BuildMPlusSummary()
    local b = CreateFrame("Frame", nil, self.frame)
    b:SetHeight(SUMM_H); b:SetPoint("TOPLEFT", self.titleBar,"BOTTOMLEFT", 0,0); b:SetPoint("TOPRIGHT", self.titleBar,"BOTTOMRIGHT", 0,0)
    self.summBg = self:FillBg(b, {0.06, 0.06, 0.10, 1})
    self.summText = self:FS(b, 9, "OUTLINE"); self.summText:SetPoint("LEFT",6,0); self.summText:SetPoint("RIGHT",-6,0)
    self.summText:SetJustifyH("LEFT"); self.summText:SetTextColor(0.3, 0.8, 1.0, 0.90)
    b:Hide(); self.summaryBar = b
end

function UI:MakeScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf); sf:SetScrollChild(child)
    local sb = CreateFrame("Slider", nil, sf)
    sb:SetWidth(3); sb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0); sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    sb:SetOrientation("VERTICAL"); sb:SetMinMaxValues(0,0); sb:SetValue(0)
    local track = sb:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.2)
    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = sb:GetThumbTexture(); thumb:SetVertexColor(0.4, 0.4, 0.4, 0.8); thumb:SetSize(3, 30)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue(); local _, mx = sb:GetMinMaxValues()
        sb:SetValue(math.max(0, math.min(mx, cur - delta * (BAR_H * 2))))
    end)
    sb:SetScript("OnValueChanged", function(_, val) sf:SetVerticalScroll(val) end)
    return { sf = sf, child = child, sb = sb }
end

function UI:MakeSectHead(parent)
    local h = CreateFrame("Frame", nil, parent); h:SetHeight(SECTH_H)
    h.bg = self:FillBg(h, {0.06, 0.06, 0.08, 0.9})
    h.label = self:FS(h, 9, "OUTLINE"); h.label:SetPoint("LEFT",6,0); h.label:SetJustifyH("LEFT")
    h.info = self:FS(h, 9, "OUTLINE"); h.info:SetJustifyH("RIGHT"); h.info:SetTextColor(0.55, 0.55, 0.55, 0.9)
    local line = h:CreateTexture(nil,"ARTWORK"); line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT",0,0); line:SetPoint("BOTTOMRIGHT",0,0); line:SetColorTexture(0.3,0.3,0.35,0.4)

    -- 承伤子视图切换：友方(绿) + 敌方(红) 双按钮
    local dtFriendly = CreateFrame("Button", nil, h)
    dtFriendly:SetSize(32, SECTH_H - 4); dtFriendly:SetPoint("LEFT", h, "LEFT", 60, 0)
    local dtFriendlyText = self:FS(dtFriendly, 8, "OUTLINE"); dtFriendlyText:SetPoint("CENTER")
    dtFriendly:SetScript("OnClick", function()
        ns.state.damageTakenView = "friendly"
        if ns.db and ns.db.display then ns.db.display.damageTakenView = "friendly" end
        if ns.Analysis then ns.Analysis:InvalidateCache() end
        if ns.UI then ns.UI:Refresh() end
    end)
    dtFriendly:Hide()

    local dtEnemy = CreateFrame("Button", nil, h)
    dtEnemy:SetSize(32, SECTH_H - 4); dtEnemy:SetPoint("LEFT", dtFriendly, "RIGHT", 2, 0)
    local dtEnemyText = self:FS(dtEnemy, 8, "OUTLINE"); dtEnemyText:SetPoint("CENTER")
    dtEnemy:SetScript("OnClick", function()
        ns.state.damageTakenView = "enemy"
        if ns.db and ns.db.display then ns.db.display.damageTakenView = "enemy" end
        if ns.Analysis then ns.Analysis:InvalidateCache() end
        if ns.UI then ns.UI:Refresh() end
    end)
    dtEnemy:Hide()

    h.dtFriendly = dtFriendly; h.dtFriendlyText = dtFriendlyText
    h.dtEnemy = dtEnemy; h.dtEnemyText = dtEnemyText

    return h
end

function UI:BuildBody()
    self.bodyFrame = CreateFrame("Frame", nil, self.frame); self.bodyFrame:SetClipsChildren(true)
    self.ovrSepLine = self.bodyFrame:CreateTexture(nil, "ARTWORK"); self.ovrSepLine:SetWidth(1); self.ovrSepLine:SetColorTexture(0, 0, 0, 0.8); self.ovrSepLine:Hide()

    self.leftContainer = CreateFrame("Frame", nil, self.bodyFrame); self.leftContainer:SetClipsChildren(true)
    self.ovrContainer = CreateFrame("Frame", nil, self.bodyFrame, "BackdropTemplate"); self.ovrContainer:SetClipsChildren(true)
    self.ovrContainer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = nil, edgeSize = 0 })
    local c = ns.db.window.ovrBgColor or {0.02, 0.04, 0.08, 0.95}; self.ovrContainer:SetBackdropColor(unpack(c)); self.ovrContainer:Hide()

    self.priHead = self:MakeSectHead(self.leftContainer)
    self.priList = self:MakeScrollArea(self.leftContainer)
    self.priBars = {}; for i = 1, MAX_BARS do self.priBars[i] = self:MakeBar(self.priList.child, "primary", i) end

    self.secHead = self:MakeSectHead(self.leftContainer)
    self.secList = self:MakeScrollArea(self.leftContainer)
    self.secBars = {}; for i = 1, MAX_BARS do self.secBars[i] = self:MakeBar(self.secList.child, "secondary", i) end

    self.ovrPriHead = self:MakeSectHead(self.ovrContainer)
    self.ovrPriList = self:MakeScrollArea(self.ovrContainer)
    self.ovrPriBars = {}; for i = 1, MAX_BARS do self.ovrPriBars[i] = self:MakeBar(self.ovrPriList.child, "ovrPri", i) end

    self.ovrSecHead = self:MakeSectHead(self.ovrContainer)
    self.ovrSecList = self:MakeScrollArea(self.ovrContainer)
    self.ovrSecBars = {}; for i = 1, MAX_BARS do self.ovrSecBars[i] = self:MakeBar(self.ovrSecList.child, "ovrSec", i) end

    self._pinnedSelf = {
        pri    = self:MakePinnedSelfBar(self.leftContainer, self.priList.sf,    "primary"),
        sec    = self:MakePinnedSelfBar(self.leftContainer, self.secList.sf,    "secondary"),
        ovrPri = self:MakePinnedSelfBar(self.ovrContainer,  self.ovrPriList.sf, "ovrPri"),
        ovrSec = self:MakePinnedSelfBar(self.ovrContainer,  self.ovrSecList.sf, "ovrSec"),
    }

    local function hookScroll(listObj, listKey)
        local origOnWheel = listObj.sf:GetScript("OnMouseWheel")
        listObj.sf:SetScript("OnMouseWheel", function(frame, delta)
            if origOnWheel then origOnWheel(frame, delta) end
            if self._pinnedSelfCache and self._pinnedSelfCache[listKey] then
                local args = self._pinnedSelfCache[listKey]
                if args.type == "bars" then self:CheckPinnedSelfForBars(listKey, listObj, args.data, args.dur, args.mode, args.count)
                elseif args.type == "api" then self:CheckPinnedSelfForAPI(listKey, listObj, args.sources, args.mode, args.maxAmt, args.sType) end
            end
        end)
    end
    hookScroll(self.priList, "pri"); hookScroll(self.secList, "sec")
    hookScroll(self.ovrPriList, "ovrPri"); hookScroll(self.ovrSecList, "ovrSec")
end

function UI:BuildResize()
    local g = CreateFrame("Frame", nil, self.frame); self.resizeHandle = g
    g:SetSize(16,16); g:SetPoint("BOTTOMRIGHT", 0, 0)
    g:SetFrameLevel(self.frame:GetFrameLevel() + 15); g:EnableMouse(true)
    local t = g:CreateTexture(nil,"OVERLAY"); t:SetAllPoints(); t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetScript("OnMouseDown", function() if ns.db.window.locked then return end; self.frame:StartSizing("BOTTOMRIGHT"); self._resizing = true end)
    g:SetScript("OnMouseUp", function()
        if not self._resizing then return end; self._resizing = false; self.frame:StopMovingOrSizing()
        local w, h = self.frame:GetWidth(), self.frame:GetHeight()
        ns.db.window.width = w; ns.db.window.height = h
        if ns.db.window.rememberSceneSize then
            local cat = ns.state.instanceCategory or "outdoor"
            if not ns.db.window.sceneSizes then ns.db.window.sceneSizes = {} end
            ns.db.window.sceneSizes[cat] = { width = w, height = h }
        end
        self:Layout()
    end)
end

function UI:SetupDrag()
    self.titleBar:EnableMouse(true); self.titleBar:RegisterForDrag("LeftButton")
    self.titleBar:SetScript("OnDragStart", function() if not ns.db.window.locked then self.frame:StartMoving() end end)
    self.titleBar:SetScript("OnDragStop", function() self.frame:StopMovingOrSizing(); local db = ns.db.window; db.point,_,db.relPoint,db.x,db.y = self.frame:GetPoint() end)
end

function UI:OnResize() self:LayoutTabs(); self:Layout() end

function UI:OnCombatStateChanged(inCombat)
    self:RefreshTitle(); self:Refresh()
    if inCombat then self:CheckAutoCollapse(); self:CheckAutoFade(true)
    else
        local collapseDelay = ns.db.collapse.delay or 1.5
        if collapseDelay <= 0 then self:CheckAutoCollapse() else C_Timer.After(collapseDelay, function() self:CheckAutoCollapse() end) end
        local fadeDelay = (ns.db.fade and ns.db.fade.delay) or 1.5
        if fadeDelay <= 0 then self:CheckAutoFade(true) else C_Timer.After(fadeDelay, function() self:CheckAutoFade(true) end) end
    end
end

function UI:Toggle()
    self:EnsureCreated()
    if self.frame:IsShown() then self.frame:Hide(); ns.db.window.visible = false
    else self.frame:Show(); ns.db.window.visible = true; self:Layout()
        C_Timer.After(0.1, function() self:CheckAutoFade(true) end)
    end
end
function UI:IsVisible() return self.frame and self.frame:IsShown() end
function UI:UpdateLock() end
function UI:UpdateLockState()
    if not self.resizeHandle then return end
    if ns.db.window.locked then self.resizeHandle:Hide() else self.resizeHandle:Show() end
end

function UI:UpdateScrollState(listObj, dataCount)
    local bh, gap = self:GetBarConfig()
    local totalH = dataCount * (bh + gap); listObj.child:SetHeight(math.max(10, totalH))
    local viewH = listObj.sf:GetHeight(); local maxScroll = math.max(0, totalH - viewH)
    listObj.sb:SetMinMaxValues(0, maxScroll)
    if maxScroll > 0 then listObj.sb:Show(); listObj.child:SetWidth(listObj.sf:GetWidth() - 4)
    else listObj.sb:Hide(); listObj.sb:SetValue(0); listObj.child:SetWidth(listObj.sf:GetWidth()) end
end

function UI:ApplySceneSize(cat)
    if not self.frame or not self.frame:IsShown() then return end
    if not ns.db.window.rememberSceneSize then return end
    local sizes = ns.db.window.sceneSizes
    if not sizes or not sizes[cat] then return end
    local s = sizes[cat]
    local anchor = ns.db.window.sceneAnchor or "TOPLEFT"

    local left, bottom = self.frame:GetLeft(), self.frame:GetBottom()
    local oldW, oldH = self.frame:GetWidth(), self.frame:GetHeight()
    if not left or not bottom then return end

    local ax, ay
    if anchor:find("LEFT") then ax = left
    elseif anchor:find("RIGHT") then ax = left + oldW
    else ax = left + oldW / 2 end
    if anchor:find("TOP") then ay = bottom + oldH
    elseif anchor:find("BOTTOM") then ay = bottom
    else ay = bottom + oldH / 2 end

    self.frame:SetSize(s.width, s.height)

    local newLeft, newBottom
    if anchor:find("LEFT") then newLeft = ax
    elseif anchor:find("RIGHT") then newLeft = ax - s.width
    else newLeft = ax - s.width / 2 end
    if anchor:find("TOP") then newBottom = ay - s.height
    elseif anchor:find("BOTTOM") then newBottom = ay
    else newBottom = ay - s.height / 2 end

    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newLeft, newBottom)
    local point, _, relPoint, x, y = self.frame:GetPoint()
    ns.db.window.point = point; ns.db.window.relPoint = relPoint; ns.db.window.x = x; ns.db.window.y = y
    self:Layout()
end