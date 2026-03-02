--[[
    LD Combat Stats - UI.lua
    主界面
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

-- ★ 修复：补充原本缺失的颜色表，解决 RefreshHead 报错
local T = {
    dmgC   = {1.0, 0.82, 0.0},
    healC  = {0.4, 1.0, 0.4},
    takenC = {1.0, 0.3, 0.3},
    accent = {0.0, 0.65, 1.0},
}

local MODE_TO_DM = {
    damage      = Enum.DamageMeterType.DamageDone,
    healing     = Enum.DamageMeterType.HealingDone,
    damageTaken = Enum.DamageMeterType.DamageTaken,
    interrupts  = Enum.DamageMeterType.Interrupts,
    dispels     = Enum.DamageMeterType.Dispels,
    deaths      = Enum.DamageMeterType.Deaths,
}
local COUNT_MODES = { deaths=true, interrupts=true, dispels=true }

local function SafeSetMinMax(sb, mn, mx) sb:SetMinMaxValues(mn, mx) end
local function SafeSetValue(sb, val) sb:SetValue(val) end
local function SafeSetText(fs, val) fs:SetText(AbbreviateNumbers(val)) end
local function SafeSetFormattedText(fs, ps, tot) fs:SetFormattedText("%s(%s)", AbbreviateNumbers(ps), AbbreviateNumbers(tot)) end

function UI:FillBg(f, c)
    local t = f:CreateTexture(nil,"BACKGROUND"); t:SetAllPoints()
    t:SetColorTexture(unpack(c)); return t
end

function UI:FS(p, sz, fl)
    local f = p:CreateFontString(nil,"OVERLAY")
    -- ★ 修改这行：
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

-- 图标按钮：texNormal/texHover 为贴图路径（不含扩展名）
function UI:IconBtn(p, texNormal, texHover, btnW, fn)
    local iconSize = TITLE_H - 6
    local b = CreateFrame("Button", nil, p)
    b:SetSize(btnW or 20, TITLE_H)
    b:EnableMouse(true)

    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(iconSize, iconSize)
    t:SetPoint("CENTER")
    t:SetTexture(texNormal)
    t:SetVertexColor(0.65, 0.65, 0.65, 1)
    b.iconTex   = t
    b.texNormal = texNormal
    b.texHover  = texHover or texNormal

    b:SetScript("OnEnter", function()
        t:SetTexture(b.texHover)
        t:SetVertexColor(1, 1, 1, 1)
    end)
    b:SetScript("OnLeave", function()
        t:SetTexture(b.texNormal)
        t:SetVertexColor(0.65, 0.65, 0.65, 1)
    end)
    b:SetScript("OnClick", fn)
    return b
end

function UI:IsOverallColumnActive()
    if not ns.db or not ns.db.split then return false end 
    if not ns.db.split.showOverall then return false end
    local mode = ns.db.split.overallShowMode or "mplus"
    if mode == "off" then return false end
    
    if mode == "always" then return true end
    
    local ovr = ns.Segments and ns.Segments.overall
    local hasData = ovr and (ovr.totalDamage > 0 or ovr.totalHealing > 0)
    
    if mode == "mplus" then
        if ns.state.inMythicPlus then return true
        elseif ns.state.isInInstance and hasData then
            local isMplusSeg = ovr and (ovr._mythicLevel or ovr.mythicLevel or ovr._builtByMythicPlus)
            local mplusActive = ns.MythicPlus and ns.MythicPlus.IsActive and ns.MythicPlus:IsActive()
            if isMplusSeg or mplusActive then return true end
        end
        return false
    end
    if mode == "instance" then return ns.state.isInInstance end
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

    -- ★ 右侧容器背景
    if self.ovrContainer then
        local c = dbw.ovrBgColor or {0.02, 0.04, 0.08, 0.95}
        self.ovrContainer:SetBackdropColor(unpack(c))
    end
end

function UI:EnsureCreated() if self.frame then return end; self:Build() end

function UI:Build()
    local db = ns.db.window
    BAR_H = ns.db.display.barHeight or 18

    local f = CreateFrame("Frame","LDStatsFrame",UIParent,"BackdropTemplate")
    f:SetSize(db.width, db.height)
    f:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    f:SetScale(db.scale); f:SetAlpha(db.alpha)
    f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(10)
    f:SetClampedToScreen(true); f:EnableMouse(true)
    f:SetMovable(true); f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(250, 180, 1000, 900) end
    
    f:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile=nil, edgeSize=0 })
    self.frame = f

    self:BuildTitle(); self:BuildMPlusSummary(); self:BuildBody()
    self:BuildTabs(); self:BuildResize(); self:SetupDrag()
    
    self:ApplyTheme()
    f:HookScript("OnSizeChanged", function() self:OnResize() end)
    f:Show(); self:Layout()

    self._lastFontHash = nil
    self._sessionCache = {}
end

local TEX = "Interface\\AddOns\\LDCombatStats\\Textures\\"

function UI:BuildTitle()
    local b = CreateFrame("Frame", nil, self.frame)
    b:SetHeight(TITLE_H); b:SetPoint("TOPLEFT",0,0); b:SetPoint("TOPRIGHT",0,0)
    self.titleBg = self:FillBg(b, {0.08, 0.08, 0.12, 1})
    self.titleBar = b

    -- [=] 历史列表按钮（保持文字，无需图标）
    local listBtn = self:Btn(b, "[=]", 12, function()
        if ns.HistoryList then ns.HistoryList:Toggle(b) end
    end)
    listBtn:SetPoint("LEFT", 4, 0); listBtn:SetSize(22, TITLE_H)
    self.listBtn = listBtn

    -- 标题文字
    self.titleText = self:FS(b, 10, "OUTLINE")
    self.titleText:SetPoint("LEFT", listBtn, "RIGHT", 4, 0)
    self.titleText:SetPoint("RIGHT", b, "RIGHT", -72, 0)
    self.titleText:SetJustifyH("LEFT"); self.titleText:SetWordWrap(false)

    -- 标题栏整体可拖拽区域
    local titleBtn = CreateFrame("Button", nil, b)
    titleBtn:SetPoint("LEFT", listBtn, "RIGHT", 0, 0)
    titleBtn:SetPoint("RIGHT", b, "RIGHT", -72, 0)
    titleBtn:SetHeight(TITLE_H)
    titleBtn:SetScript("OnClick", function()
        if ns.HistoryList then ns.HistoryList:Toggle(b) end
    end)
    titleBtn:RegisterForDrag("LeftButton")
    titleBtn:SetScript("OnDragStart", function()
        if not ns.db.window.locked then self.frame:StartMoving() end
    end)
    titleBtn:SetScript("OnDragStop", function()
        self.frame:StopMovingOrSizing()
        local db = ns.db.window
        db.point, _, db.relPoint, db.x, db.y = self.frame:GetPoint()
    end)

    -- ★ 折叠/展开 按钮（最右侧，图标切换）
    self._collapsed = false
    local colBtn
    colBtn = self:IconBtn(b,
        TEX .. "btn_collapse",
        TEX .. "btn_collapse",
        20,
        function()
            self._collapsed = not self._collapsed
            if self._collapsed then
                -- 记录折叠前的顶部屏幕坐标，改为从 TOPLEFT 锚定，确保向上折叠
                local left = self.frame:GetLeft()
                local top  = self.frame:GetTop()
                self._savedHeight = self.frame:GetHeight()
                self._savedAnchor = { self.frame:GetPoint() }  -- 保存原始锚点

                self.frame:ClearAllPoints()
                self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

                colBtn.iconTex:SetTexture(TEX .. "btn_expand")
                colBtn.iconTex:SetVertexColor(0.65, 0.65, 0.65, 1)
                colBtn.texNormal = TEX .. "btn_expand"
                colBtn.texHover  = TEX .. "btn_expand"
                self.bodyFrame:Hide()
                self.tabBar:Hide()
                self.summaryBar:Hide()
                if self.resizeHandle then self.resizeHandle:Hide() end  -- ← 隐藏缩放手柄
                self.frame:SetHeight(TITLE_H)
            else
                -- 恢复原始锚点和高度
                self.frame:ClearAllPoints()
                if self._savedAnchor then
                    self.frame:SetPoint(unpack(self._savedAnchor))
                end
                self.frame:SetHeight(self._savedHeight or ns.db.window.height)
                self._savedHeight = nil
                self._savedAnchor = nil

                colBtn.iconTex:SetTexture(TEX .. "btn_collapse")
                colBtn.iconTex:SetVertexColor(0.65, 0.65, 0.65, 1)
                colBtn.texNormal = TEX .. "btn_collapse"
                colBtn.texHover  = TEX .. "btn_collapse"
                self.bodyFrame:Show()
                self.tabBar:Show()
                if self.resizeHandle then self.resizeHandle:Show() end  -- ← 恢复缩放手柄
                self:Layout()
            end
        end
    )

    colBtn:SetPoint("RIGHT", -4, 0)
    self.collapseBtn = colBtn

    -- ★ 设置 按钮
    local cfgBtn = self:IconBtn(b,
        TEX .. "btn_settings",
        TEX .. "btn_settings",
        20,
        function() if ns.Config then ns.Config:Toggle() end end
    )
    cfgBtn:SetPoint("RIGHT", colBtn, "LEFT", -2, 0)
    self.cfgBtn = cfgBtn

    -- ★ 清空 按钮
    local rstBtn = self:IconBtn(b,
        TEX .. "btn_reset",
        TEX .. "btn_reset",
        20,
        function() if ns.Segments then ns.Segments:ResetAll() end end
    )
    rstBtn:SetPoint("RIGHT", cfgBtn, "LEFT", -2, 0)
    self.rstBtn = rstBtn
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
    local child = CreateFrame("Frame", nil, sf)
    sf:SetScrollChild(child)

    local sb = CreateFrame("Slider", nil, sf)
    sb:SetWidth(3); sb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0); sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
    sb:SetOrientation("VERTICAL"); sb:SetMinMaxValues(0,0); sb:SetValue(0)
    
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(); track:SetColorTexture(0, 0, 0, 0.2)
    
    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = sb:GetThumbTexture()
    thumb:SetVertexColor(0.4, 0.4, 0.4, 0.8); thumb:SetSize(3, 30)

    sf:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue()
        local _, mx = sb:GetMinMaxValues()
        sb:SetValue(math.max(0, math.min(mx, cur - delta * (BAR_H * 2))))
    end)
    sb:SetScript("OnValueChanged", function(_, val) sf:SetVerticalScroll(val) end)

    return { sf = sf, child = child, sb = sb }
end

function UI:BuildBody()
    self.bodyFrame = CreateFrame("Frame", nil, self.frame)
    self.bodyFrame:SetClipsChildren(true)

    self.ovrSepLine = self.bodyFrame:CreateTexture(nil, "ARTWORK")
    self.ovrSepLine:SetWidth(1)
    self.ovrSepLine:SetColorTexture(0, 0, 0, 0.8)
    self.ovrSepLine:Hide()

    -- 左侧容器
    self.leftContainer = CreateFrame("Frame", nil, self.bodyFrame)
    self.leftContainer:SetClipsChildren(true)

    -- ★ 右侧独立容器，有自己的背景
    self.ovrContainer = CreateFrame("Frame", nil, self.bodyFrame, "BackdropTemplate")
    self.ovrContainer:SetClipsChildren(true)
    self.ovrContainer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = nil, edgeSize = 0 })
    local c = ns.db.window.ovrBgColor or {0.02, 0.04, 0.08, 0.95}
    self.ovrContainer:SetBackdropColor(unpack(c))
    self.ovrContainer:Hide()

    -- 左侧：主栏 + 副栏
    self.priHead = self:MakeSectHead(self.leftContainer)
    self.priList = self:MakeScrollArea(self.leftContainer)
    self.priBars = {}
    for i = 1, MAX_BARS do self.priBars[i] = self:MakeBar(self.priList.child, "primary", i) end

    self.secHead = self:MakeSectHead(self.leftContainer)
    self.secList = self:MakeScrollArea(self.leftContainer)
    self.secBars = {}
    for i = 1, MAX_BARS do self.secBars[i] = self:MakeBar(self.secList.child, "secondary", i) end

    -- ★ 右侧：全程栏，父级改为 ovrContainer
    self.ovrPriHead = self:MakeSectHead(self.ovrContainer)
    self.ovrPriList = self:MakeScrollArea(self.ovrContainer)
    self.ovrPriBars = {}
    for i = 1, MAX_BARS do self.ovrPriBars[i] = self:MakeBar(self.ovrPriList.child, "ovrPri", i) end

    self.ovrSecHead = self:MakeSectHead(self.ovrContainer)
    self.ovrSecList = self:MakeScrollArea(self.ovrContainer)
    self.ovrSecBars = {}
    for i = 1, MAX_BARS do self.ovrSecBars[i] = self:MakeBar(self.ovrSecList.child, "ovrSec", i) end
end

function UI:MakeSectHead(parent)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(SECTH_H)
    h.bg = self:FillBg(h, {0.06, 0.06, 0.08, 0.9})
    h.label = self:FS(h, 9, "OUTLINE"); h.label:SetPoint("LEFT",6,0); h.label:SetJustifyH("LEFT")
    h.info = self:FS(h, 9, "OUTLINE"); h.info:SetJustifyH("RIGHT"); h.info:SetTextColor(0.55, 0.55, 0.55, 0.9)
    local line = h:CreateTexture(nil,"ARTWORK"); line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT",0,0); line:SetPoint("BOTTOMRIGHT",0,0); line:SetColorTexture(0.3,0.3,0.35,0.4)
    return h
end

function UI:MakeBar(parent, section, index)
    local bar = {}
    bar.frame = CreateFrame("Button", nil, parent)
    bar.frame:SetHeight(BAR_H); bar.frame:RegisterForClicks("LeftButtonUp","RightButtonUp"); bar.frame:Hide()

    bar.bg = bar.frame:CreateTexture(nil,"BACKGROUND"); bar.bg:SetAllPoints(); bar.bg:SetColorTexture(0.1, 0.1, 0.12, 0.5)
    bar.fill = bar.frame:CreateTexture(nil,"BORDER"); bar.fill:SetPoint("TOPLEFT"); bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8"); bar.fill:SetWidth(1)

    bar.statusbar = CreateFrame("StatusBar", nil, bar.frame)
    bar.statusbar:SetPoint("TOPLEFT"); bar.statusbar:SetPoint("BOTTOMRIGHT")
    bar.statusbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.statusbar:SetMinMaxValues(0, 1); bar.statusbar:Hide()

    bar.textFrame = CreateFrame("Frame", nil, bar.frame)
    bar.textFrame:SetAllPoints()
    bar.textFrame:SetFrameLevel(bar.statusbar:GetFrameLevel() + 2)

    -- ★ 新增：专精图标挂载在 frame 上，而不是 textFrame 上，这样数据条平移时它不受影响
    bar.specIcon = bar.frame:CreateTexture(nil, "OVERLAY")
    bar.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.specIcon:Hide()

    bar.rank = self:FS(bar.textFrame, 9, "OUTLINE"); bar.rank:SetPoint("LEFT",3,0)
    bar.rank:SetJustifyH("RIGHT"); bar.rank:SetTextColor(1.0, 1.0, 1.0, 0.9)
    bar.name = self:FS(bar.textFrame, 10, "OUTLINE"); bar.name:SetJustifyH("LEFT"); bar.name:SetWordWrap(false)
    bar.value = self:FS(bar.textFrame, 9, "OUTLINE"); bar.value:SetJustifyH("RIGHT")
    
    bar.hl = bar.frame:CreateTexture(nil,"HIGHLIGHT"); bar.hl:SetAllPoints(); bar.hl:SetColorTexture(1, 1, 1, 0.05)

    bar.section = section; bar.index = index

    bar.frame:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            ns.db.display.mode = ns:NextMode(ns.db.display.mode)
            if ns.UI then ns.UI:Layout() end
        else
            if not bar._guid then return end
            if bar._isDeath then
                if ns.DetailView then ns.DetailView:ShowDeathDetail(bar._data) end
            else
                if ns.DetailView then
                    if bar._data and bar._data.isAPI then
                        ns.DetailView:ShowSpellBreakdownFromAPI(bar._guid, bar._nameStr, bar._classStr, bar._mode, bar._data.sessionType)
                    else
                        local isOvr = bar.section and bar.section:sub(1, 3) == "ovr"
                        local seg = isOvr and (ns.Segments and ns.Segments:GetOverallSegment()) or nil
                        ns.DetailView:ShowSpellBreakdown(bar._guid, bar._nameStr, bar._classStr, bar._mode, seg)
                    end
                end
            end
        end
    end)
    
    bar.frame:SetScript("OnEnter", function() UI:ShowTooltip(bar, bar.section) end)
    bar.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return bar
end

function UI:BuildTabs()
    local tb = CreateFrame("Frame", nil, self.frame)
    tb:SetHeight(TAB_H); tb:SetPoint("BOTTOMLEFT",0,0); tb:SetPoint("BOTTOMRIGHT",0,0)
    self.tabBg = self:FillBg(tb, {0.05, 0.05, 0.07, 1}); self.tabBar = tb

    local st = CreateFrame("Button", nil, tb)
    st.abg = st:CreateTexture(nil,"BORDER"); st.abg:SetAllPoints(); st.abg:SetColorTexture(0,0.65,1,0.22); st.abg:Hide()
    st.text = self:FS(st, 9, "OUTLINE"); st.text:SetPoint("CENTER"); st.text:SetTextColor(0.55, 0.55, 0.55, 0.9)
    -- ★ 修复：现在点击双栏只切换模式为 split，不更改全局 enabled
    st:SetScript("OnClick", function() ns.db.display.mode = "split"; self:Layout() end)
    self.splitTab = st

    local defs = { {m="damage",l=L["伤害"]},{m="healing",l=L["治疗"]},{m="damageTaken",l=L["承伤"]}, {m="deaths",l=L["死亡"]},{m="interrupts",l=L["打断"]},{m="dispels",l=L["驱散"]} }
    self.tabs = {}
    for i, d in ipairs(defs) do
        local t = CreateFrame("Button", nil, tb)
        t.abg = t:CreateTexture(nil,"BORDER"); t.abg:SetAllPoints(); t.abg:SetColorTexture(0, 0.65, 1, 0.3); t.abg:Hide()
        t.text = self:FS(t, 9, "OUTLINE"); t.text:SetPoint("CENTER"); t.text:SetText(d.l); t.text:SetTextColor(0.55, 0.55, 0.55, 0.9)
        t.mode = d.m
        -- ★ 修复：单栏Tab点击也只切换模式，不再暴力禁用全局双栏
        t:SetScript("OnClick", function() ns.db.display.mode = d.m; self:Layout() end)
        self.tabs[i] = t
    end
end

function UI:LayoutTabs()
    if not self.tabs or not self.splitTab then return end
    local w  = self.tabBar:GetWidth(); if w <= 0 then return end
    local sp = ns.db and ns.db.split
    local visible = {}

    if sp and sp.enabled then
        local pName = L[ns.MODE_NAMES[sp.primaryMode] or sp.primaryMode]
        local sName = L[ns.MODE_NAMES[sp.secondaryMode] or sp.secondaryMode]
        self.splitTab.text:SetText(pName .. "|" .. sName)
        self.splitTab:Show()
        table.insert(visible, self.splitTab)
    else
        self.splitTab:Hide()
    end

    for _, t in ipairs(self.tabs) do
        -- ★ 双栏启用时，隐藏组成双栏的那两个 tab
        if t.mode and ns.MODE_NAMES[t.mode] then
            t.text:SetText(L[ns.MODE_NAMES[t.mode]])
        end

        if sp and sp.enabled
           and (t.mode == sp.primaryMode or t.mode == sp.secondaryMode) then
            t:Hide()
        else
            t:Show()
            table.insert(visible, t)
        end
    end

    local tw = w / #visible
    for i, t in ipairs(visible) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", self.tabBar, "TOPLEFT", (i-1)*tw, 0)
        t:SetSize(tw, TAB_H)
    end
end

function UI:BuildResize()
    local g = CreateFrame("Frame", nil, self.frame)
    self.resizeHandle = g
    g:SetSize(16,16); g:SetPoint("BOTTOMRIGHT", 0, 0)
    g:SetFrameLevel(self.frame:GetFrameLevel() + 15); g:EnableMouse(true)
    local t = g:CreateTexture(nil,"OVERLAY"); t:SetAllPoints(); t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetScript("OnMouseDown", function() if ns.db.window.locked then return end; self.frame:StartSizing("BOTTOMRIGHT"); self._resizing = true end)
    g:SetScript("OnMouseUp", function() 
        if not self._resizing then return end; self._resizing = false; self.frame:StopMovingOrSizing()
        ns.db.window.width = self.frame:GetWidth(); ns.db.window.height = self.frame:GetHeight()
        self:Layout()
    end)
end

function UI:SetupDrag()
    self.titleBar:EnableMouse(true); self.titleBar:RegisterForDrag("LeftButton")
    self.titleBar:SetScript("OnDragStart", function() if not ns.db.window.locked then self.frame:StartMoving() end end)
    self.titleBar:SetScript("OnDragStop", function() self.frame:StopMovingOrSizing(); local db = ns.db.window; db.point,_,db.relPoint,db.x,db.y = self.frame:GetPoint() end)
end

function UI:OnResize() self:LayoutTabs(); self:Layout() end

function UI:Layout()
    if not self.frame or not self.frame:IsShown() then return end

    -- ★ 防抖：如果已有一个 DoLayout 在等待执行，直接返回，不重复创建
    if self._layoutPending then return end
    self._layoutPending = true

    self:LayoutTabs()

    local showSumm = (ns.db and ns.db.mythicPlus and ns.db.mythicPlus.dualDisplay)
                     and ns.state.isInInstance
                     and self:IsOverallColumnActive() or false
    if showSumm then
        self.summaryBar:Show()
        self.bodyFrame:SetPoint("TOPLEFT", self.summaryBar, "BOTTOMLEFT", 0, 0)
    else
        self.summaryBar:Hide()
        self.bodyFrame:SetPoint("TOPLEFT", self.titleBar, "BOTTOMLEFT", 0, 0)
    end
    self.bodyFrame:SetPoint("BOTTOMRIGHT", self.tabBar, "TOPRIGHT", 0, 0)

    C_Timer.After(0, function()
        self._layoutPending = false  -- ★ 执行前解锁，允许下一次 Layout
        self:DoLayout(0)
    end)
end

-- ============================================================
-- ★ 外观与字体动态工具
-- ============================================================
function UI:GetBarConfig()
    local db = ns.db.display
    return db.barHeight or 18, db.barGap or 1, db.barAlpha or 0.85, 
           -- ★ 修改这行：
           db.font or STANDARD_TEXT_FONT, db.fontSizeBase or 12, 
           db.fontOutline or "OUTLINE", db.fontShadow or false
end

function UI:ApplyFont(fs, font, size, outline, shadow)
    fs:SetFont(font, size, outline)
    if shadow then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

-- ============================================================
-- ★ 滑动条动态排版计算
-- ============================================================
function UI:UpdateScrollState(listObj, dataCount)
    local bh, gap = self:GetBarConfig()
    local totalH = dataCount * (bh + gap)
    listObj.child:SetHeight(math.max(10, totalH))
    
    local viewH = listObj.sf:GetHeight()
    local maxScroll = math.max(0, totalH - viewH)
    listObj.sb:SetMinMaxValues(0, maxScroll)
    
    if maxScroll > 0 then
        listObj.sb:Show()
        listObj.child:SetWidth(listObj.sf:GetWidth() - 4) -- 为滚动条让路
    else
        listObj.sb:Hide()
        listObj.sb:SetValue(0)
        listObj.child:SetWidth(listObj.sf:GetWidth())
    end
end

function UI:ApplyAllFontsIfNeeded()
    local db = ns.db.display
    local hash = (db.font or "") .. "|" .. (db.fontSizeBase or 10) .. "|" .. (db.fontOutline or "")
    if hash == self._lastFontHash then return end
    self._lastFontHash = hash
    self:ApplyAllFonts()
end

function UI:DoLayout(retryCount)
    if not self.bodyFrame then return end
    retryCount = retryCount or 0
    self:ApplyAllFontsIfNeeded()

    local bodyH = self.bodyFrame:GetHeight()
    local bodyW = self.bodyFrame:GetWidth()

    if bodyW <= 0 or bodyH <= 0 then
        if retryCount < 20 then
            C_Timer.After(0.05, function() self:DoLayout(retryCount + 1) end)
        end
        return
    end

    local sp = ns.db.split
    local useOvr = self:IsOverallColumnActive()
    local isSplitView = sp.enabled and (ns.db.display.mode == "split")

    -- 1. 计算四大容器的边界 (当前 vs 总计)
    local curW, curH = bodyW, bodyH
    local ovrW, ovrH = 0, 0
    local curX, curY = 0, 0
    local ovrX, ovrY = 0, 0

    if useOvr then
        if sp.overallDir == "LR" then
            local lrRatio = sp.lrRatio or 0.5
            local w1 = bodyW * lrRatio
            local gap = 2  -- ★ 留白宽度，防止进度条贴脸
            local sepW = 1 -- ★ 分割线宽度
            local w2 = bodyW - w1 - sepW - gap 
            ovrH = bodyH  
            
            if sp.currentPos == 1 then
                curW, ovrW = w1 - gap, w2
                curX, ovrX = 0, w1 + sepW + gap
            else
                ovrW, curW = w1 - gap, w2
                ovrX, curX = 0, w1 + sepW + gap
            end
            
            self.ovrSepLine:ClearAllPoints()
            self.ovrSepLine:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", w1, 0)
            self.ovrSepLine:SetPoint("BOTTOMLEFT", self.bodyFrame, "BOTTOMLEFT", w1, 0)
            self.ovrSepLine:SetSize(sepW, bodyH)
            self.ovrSepLine:Show()
        else -- TB
            local tbRatio = sp.tbRatio or 0.5
            local h1 = bodyH * tbRatio
            local sepW = 1
            local gap = 2
            local h2 = bodyH - h1 - sepW - gap
            ovrW = bodyW  
            
            if sp.currentPos == 1 then
                curH, ovrH = h1 - gap, h2
                curY, ovrY = 0, -(h1 + sepW + gap)
            else
                ovrH, curH = h1 - gap, h2
                ovrY, curY = 0, -(h1 + sepW + gap)
            end
            
            self.ovrSepLine:ClearAllPoints()
            self.ovrSepLine:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", 0, -h1)
            self.ovrSepLine:SetPoint("TOPRIGHT", self.bodyFrame, "TOPRIGHT", 0, -h1)
            self.ovrSepLine:SetSize(bodyW, sepW)
            self.ovrSepLine:Show()
        end
        
        self.ovrContainer:ClearAllPoints()
        self.ovrContainer:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", ovrX, ovrY)
        self.ovrContainer:SetSize(ovrW, ovrH)
        self.ovrContainer:Show()
    else
        self.ovrSepLine:Hide()
        self.ovrContainer:Hide()
    end

    self.leftContainer:ClearAllPoints()
    self.leftContainer:SetPoint("TOPLEFT", self.bodyFrame, "TOPLEFT", curX, curY)
    self.leftContainer:SetSize(curW, curH)

    -- 2. 内部双数据的划分算法 (主模式 vs 副模式)
    local function LayoutInner(container, head1, list1, head2, list2, w, h, isSplit, mode1, mode2)
        if not isSplit then
            head1:Show(); head1:ClearAllPoints()
            head1:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            head1:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            
            list1.sf:Show(); list1.sf:ClearAllPoints()
            list1.sf:SetPoint("TOPLEFT", head1, "BOTTOMLEFT", 0, 0)
            list1.sf:SetPoint("TOPRIGHT", head1, "BOTTOMRIGHT", 0, 0)
            list1.sf:SetHeight(math.max(1, h - SECTH_H))
            
            head2:Hide(); list2.sf:Hide()
            return
        end

        local splitDir = sp.splitDir or "TB"
        head1:Show(); head2:Show(); list1.sf:Show(); list2.sf:Show()

        if splitDir == "TB" then
            local tbRatio = sp.tbRatio or 0.5
            local h1 = h * tbRatio
            local gap = 2
            local h2 = h - h1 - gap
            
            local topHead, bottomHead, topList, bottomList
            if sp.primaryPos == 1 then
                topHead, bottomHead = head1, head2
                topList, bottomList = list1, list2
            else
                topHead, bottomHead = head2, head1
                topList, bottomList = list2, list1
            end
            
            topHead:ClearAllPoints()
            topHead:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            topHead:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
            
            topList.sf:ClearAllPoints()
            topList.sf:SetPoint("TOPLEFT", topHead, "BOTTOMLEFT", 0, 0)
            topList.sf:SetPoint("TOPRIGHT", topHead, "BOTTOMRIGHT", 0, 0)
            topList.sf:SetHeight(math.max(1, h1 - gap - SECTH_H))

            bottomHead:ClearAllPoints()
            bottomHead:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -h1)
            bottomHead:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -h1)

            bottomList.sf:ClearAllPoints()
            bottomList.sf:SetPoint("TOPLEFT", bottomHead, "BOTTOMLEFT", 0, 0)
            bottomList.sf:SetPoint("TOPRIGHT", bottomHead, "BOTTOMRIGHT", 0, 0)
            bottomList.sf:SetHeight(math.max(1, h2 - SECTH_H))
        else -- LR
            local lrRatio = sp.lrRatio or 0.5
            local gap = 2 -- ★ 内部的双数据左右分栏留白
            local w1 = w * lrRatio
            local w2 = w - w1 - gap
            
            local leftHead, rightHead, leftList, rightList
            if sp.primaryPos == 1 then
                leftHead, rightHead = head1, head2
                leftList, rightList = list1, list2
            else
                leftHead, rightHead = head2, head1
                leftList, rightList = list2, list1
            end

            leftHead:ClearAllPoints()
            leftHead:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            leftHead:SetWidth(w1 - gap) -- ★ 减去留白宽度，收缩最右侧边缘
            
            leftList.sf:ClearAllPoints()
            leftList.sf:SetPoint("TOPLEFT", leftHead, "BOTTOMLEFT", 0, 0)
            leftList.sf:SetPoint("TOPRIGHT", leftHead, "BOTTOMRIGHT", 0, 0)
            leftList.sf:SetHeight(math.max(1, h - SECTH_H))

            rightHead:ClearAllPoints()
            rightHead:SetPoint("TOPLEFT", container, "TOPLEFT", w1, 0)
            rightHead:SetWidth(w2)

            rightList.sf:ClearAllPoints()
            rightList.sf:SetPoint("TOPLEFT", rightHead, "BOTTOMLEFT", 0, 0)
            rightList.sf:SetPoint("TOPRIGHT", rightHead, "BOTTOMRIGHT", 0, 0)
            rightList.sf:SetHeight(math.max(1, h - SECTH_H))
        end
    end

    LayoutInner(self.leftContainer, self.priHead, self.priList, self.secHead, self.secList, curW, curH, isSplitView, sp.primaryMode, sp.secondaryMode)
    
    if useOvr then
        LayoutInner(self.ovrContainer, self.ovrPriHead, self.ovrPriList, self.ovrSecHead, self.ovrSecList, ovrW, ovrH, isSplitView, sp.primaryMode, sp.secondaryMode)
        
        self.ovrPriHead.info:Hide()
        self.ovrSecHead.info:Hide()
        
        local ovrTitleWord = L["总计"]
        if ns.Segments and ns.Segments.overall and ns.Segments.overall._isMerged then
            ovrTitleWord = L["全程"]
        end
        
        if isSplitView then
            self.ovrPriHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, L[ns.MODE_NAMES[sp.primaryMode] or ""]))
            self.ovrSecHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, L[ns.MODE_NAMES[sp.secondaryMode] or ""]))
        else
            self.ovrPriHead.label:SetText(string.format(L["|cff4cb8e8[%s%s]|r"], ovrTitleWord, L[ns.MODE_NAMES[ns.db.display.mode] or ""]))
        end
    end

    self:Refresh()
end

function UI:AnchorBarTexts(bar)
    local rowH = ns.db.display.barHeight or 18
    local iconSize = rowH - 4
    
    -- 读取新的厚度和偏移量配置（如果没有设置旧配置兜底，则默认填满整行）
    local thickness = ns.db.display.barThickness or rowH
    local vOffset   = ns.db.display.barVOffset or 0

    if ns.db.display.showSpecIcon then
        bar.specIcon:SetSize(iconSize, iconSize)
        bar.specIcon:ClearAllPoints()
        bar.specIcon:SetPoint("LEFT", bar.frame, "LEFT", 2, 0)
        
        local offset = iconSize + 6
        
        -- ★ 背景、填充、状态条改为由 BOTTOMLEFT 和 SetHeight 决定，实现解绑
        bar.bg:ClearAllPoints()
        bar.bg:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset)
        bar.bg:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
        bar.bg:SetHeight(thickness)

        bar.fill:ClearAllPoints()
        bar.fill:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset)
        bar.fill:SetHeight(thickness)

        bar.statusbar:ClearAllPoints()
        bar.statusbar:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", offset, vOffset)
        bar.statusbar:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
        bar.statusbar:SetHeight(thickness)

        -- 文字框依然充满整行高度，保证文字/点击区域垂直居中不变
        bar.textFrame:ClearAllPoints()
        bar.textFrame:SetPoint("TOPLEFT", bar.frame, "TOPLEFT", offset, 0)
        bar.textFrame:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, 0)
    else
        bar.specIcon:Hide()

        bar.bg:ClearAllPoints()
        bar.bg:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, vOffset)
        bar.bg:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
        bar.bg:SetHeight(thickness)

        bar.fill:ClearAllPoints()
        bar.fill:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, vOffset)
        bar.fill:SetHeight(thickness)

        bar.statusbar:ClearAllPoints()
        bar.statusbar:SetPoint("BOTTOMLEFT", bar.frame, "BOTTOMLEFT", 0, vOffset)
        bar.statusbar:SetPoint("BOTTOMRIGHT", bar.frame, "BOTTOMRIGHT", 0, vOffset)
        bar.statusbar:SetHeight(thickness)

        -- 文字框依然充满整行高度
        bar.textFrame:ClearAllPoints()
        bar.textFrame:SetAllPoints(bar.frame)
    end

    bar.rank:ClearAllPoints()
    bar.rank:SetPoint("LEFT", bar.textFrame, "LEFT", 3, 0)

    bar.value:ClearAllPoints()
    bar.value:SetPoint("RIGHT", bar.textFrame, "RIGHT", -2, 0)
    
    bar.name:ClearAllPoints()
    bar.name:SetPoint("LEFT", bar.rank, "RIGHT", 3, 0)
    bar.name:SetPoint("RIGHT", bar.value, "LEFT", -5, 0) 
end

function UI:Refresh()
    if not self.frame or not self.frame:IsShown() then return end

    self._sessionCache = {}  -- ← 加这一行，每次刷新清空缓存

    local seg  = ns.Segments and ns.Segments:GetViewSegment()
    local dur  = ns.Analysis  and ns.Analysis:GetSegmentDuration(seg) or 0
    local sp   = ns.db.split
    local mode = ns.db.display.mode
    local useOvr = self:IsOverallColumnActive()
    
    local isSplitView = sp.enabled and (mode == "split")

    self:RefreshTitle()

    -- ============================================================
    -- Summary 栏（M+ 全程摘要）
    -- ============================================================
    if self.summaryBar:IsShown() then

        local ovrTitleWord = L["总计"]
        local ovrSeg = ns.Segments and ns.Segments.overall
        if ovrSeg and ovrSeg._isMerged then
            ovrTitleWord = L["全程"]
        end
        
        if ns.state.inCombat then
            -- 战斗中：从暴雪 Overall API 读实时数据（Secret Value，只能用 AbbreviateNumbers）
            local durSafe = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or 0

            local dmDmg  = self:GetCachedSession(Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.DamageDone)
            local dmHeal = self:GetCachedSession(Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.HealingDone)
            local ok1, ok2 = dmDmg ~= nil, dmHeal ~= nil

            local dmgStr, healStr = "0", "0"
            if ok1 and dmDmg then
                local ok3, s = pcall(AbbreviateNumbers, dmDmg.totalAmount)
                if ok3 and s then dmgStr = s end
            end
            if ok2 and dmHeal then
                local ok4, s = pcall(AbbreviateNumbers, dmHeal.totalAmount)
                if ok4 and s then healStr = s end
            end

            self.summText:SetFormattedText(
                L["全程 %s  |  Damage |cffffd100%s|r  Heal |cff66ff66%s|r"],
                ns:FormatTime(durSafe), dmgStr, healStr)
        else
            local ovrDmg  = ovrSeg and ovrSeg.totalDamage  or 0
            local ovrHeal = ovrSeg and ovrSeg.totalHealing  or 0
            local ovrDur  = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall)
                            or (ovrSeg and ovrSeg.duration or 0)
            if ovrDmg > 0 or ovrHeal > 0 then
                self.summText:SetText(string.format(
                    L["%s %s  |  Damage |cffffd100%s|r  Heal |cff66ff66%s|r"],
                    ovrTitleWord,
                    ns:FormatTime(ovrDur),
                    ns:FormatNumber(ovrDmg),
                    ns:FormatNumber(ovrHeal)))
            else
                self.summText:SetText(string.format(L["%s 0:00  |  Damage 0  Heal 0"], ovrTitleWord))
            end
        end
    end

    -- ============================================================
    -- Tab 高亮状态
    -- ============================================================
    if self.splitTab then
        if isSplitView then
            self.splitTab.abg:Show()
            self.splitTab.text:SetTextColor(0, 0.75, 1)
        else
            self.splitTab.abg:Hide()
            self.splitTab.text:SetTextColor(0.55, 0.55, 0.55)
        end
    end
    for _, t in ipairs(self.tabs) do
        local act = (mode == t.mode)
        if act then
            t.abg:Show(); t.text:SetTextColor(1, 1, 1)
        else
            t.abg:Hide(); t.text:SetTextColor(0.55, 0.55, 0.55)
        end
    end

    -- ============================================================
    -- 数据路径判断
    -- ============================================================
    local isDeathMode   = (mode == "deaths")
    local forceDataMode = isDeathMode
    local isOverall     = ns.Segments and ns.Segments.viewIndex == 0

    local showingCurrent = ns.state.inCombat
        and ns.Segments
        and not isOverall
        and not (ns.Segments.viewIndex and ns.Segments.history[ns.Segments.viewIndex])

    local showingOverallInCombat = ns.state.inCombat and isOverall

    -- ============================================================
    -- 路径一：战斗中，显示当前段实时 API 数据
    -- ============================================================
    if showingCurrent and not forceDataMode then
        local sType = Enum.DamageMeterSessionType.Current
        if isSplitView then
            self:RefreshHead(self.priHead, sp.primaryMode,   nil, 0, sType)
            self:RefreshHead(self.secHead, sp.secondaryMode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, sp.primaryMode,   sType)
            self:FillBarsFromAPI(self.secBars, self.secList, sp.secondaryMode, sType)
            if useOvr then
                self:FillOvrBars(isSplitView, sp, mode)  -- ★ 修复：不用 Overall API
            end
        else
            self:RefreshHead(self.priHead, mode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, mode, sType)
            if useOvr then
                self:FillOvrBars(isSplitView, sp, mode)  -- ★ 修复：不用 Overall API
            end
        end

    -- ============================================================
    -- 路径二：战斗中，用户切到了总计视图
    -- ============================================================
    elseif showingOverallInCombat and not forceDataMode then
        local sType = Enum.DamageMeterSessionType.Overall
        if isSplitView then
            self:RefreshHead(self.priHead, sp.primaryMode,   nil, 0, sType)
            self:RefreshHead(self.secHead, sp.secondaryMode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, sp.primaryMode,   sType)
            self:FillBarsFromAPI(self.secBars, self.secList, sp.secondaryMode, sType)
            if useOvr then
                self:FillOvrBars(isSplitView, sp, mode)  -- ★ 修复：不用 Overall API
            end
        else
            self:RefreshHead(self.priHead, mode, nil, 0, sType)
            self:FillBarsFromAPI(self.priBars, self.priList, mode, sType)
            if useOvr then
                self:FillOvrBars(isSplitView, sp, mode)  -- ★ 修复：不用 Overall API
            end
        end

    -- ============================================================
    -- 路径三：脱战后，从历史数据结构读取（不变）
    -- ============================================================
    else
        if isSplitView then
            local priMode, secMode = sp.primaryMode, sp.secondaryMode
            local priD = ns.Analysis and ns.Analysis:GetSorted(seg, priMode) or {}
            local secD = ns.Analysis and ns.Analysis:GetSorted(seg, secMode) or {}
            self:RefreshHead(self.priHead, priMode, seg, dur)
            self:RefreshHead(self.secHead, secMode, seg, dur)
            self:FillBars(self.priBars, self.priList, priD, dur, priMode)
            self:FillBars(self.secBars, self.secList, secD, dur, secMode)

            if useOvr then
                local ovrSeg  = ns.Segments and ns.Segments:GetOverallSegment()
                local ovrDur  = ovrSeg and ovrSeg.duration or 0
                local ovrPriD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, priMode) or {}
                local ovrSecD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, secMode) or {}
                self:FillBars(self.ovrPriBars, self.ovrPriList, ovrPriD, ovrDur, priMode)
                self:FillBars(self.ovrSecBars, self.ovrSecList, ovrSecD, ovrDur, secMode)
            end
        else
            self:RefreshHead(self.priHead, mode, seg, dur)
            if isDeathMode then
                self:FillDeathBars(seg)
            else
                local d = ns.Analysis and ns.Analysis:GetSorted(seg, mode) or {}
                self:FillBars(self.priBars, self.priList, d, dur, mode)
            end
            if useOvr then
                local ovrSeg = ns.Segments and ns.Segments:GetOverallSegment()
                if isDeathMode then
                    self:FillDeathBars(ovrSeg, self.ovrPriBars, self.ovrPriList)
                else
                    local ovrD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, mode) or {}
                    self:FillBars(self.ovrPriBars, self.ovrPriList, ovrD, (ovrSeg and ovrSeg.duration or 0), mode)
                end
            end
        end
    end
end


function UI:GetCachedSession(sessionType, dmType)
    local key = tostring(sessionType) .. "|" .. tostring(dmType)
    if not self._sessionCache[key] then
        self._sessionCache[key] = C_DamageMeter.GetCombatSessionFromType(sessionType, dmType)
    end
    return self._sessionCache[key]
end


function UI:FillOvrBars(isSplitView, sp, mode)
    if ns.state.inCombat then
        local ovr = ns.Segments and ns.Segments.overall
        local hasPriorData = ovr and (ovr.totalDamage > 0 or ovr.totalHealing > 0)
        local sType = hasPriorData
            and Enum.DamageMeterSessionType.Overall
            or  Enum.DamageMeterSessionType.Current
        if isSplitView then
            self:FillBarsFromAPI(self.ovrPriBars, self.ovrPriList, sp.primaryMode,   sType)
            self:FillBarsFromAPI(self.ovrSecBars, self.ovrSecList, sp.secondaryMode, sType)
        else
            self:FillBarsFromAPI(self.ovrPriBars, self.ovrPriList, mode, sType)
        end
    else
        local ovrSeg = ns.Segments and ns.Segments:GetOverallSegment()
        local ovrDur = ns.Analysis and ns.Analysis:GetSegmentDuration(ovrSeg) or 0
        if isSplitView then
            local ovrPriD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, sp.primaryMode)   or {}
            local ovrSecD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, sp.secondaryMode) or {}
            self:FillBars(self.ovrPriBars, self.ovrPriList, ovrPriD, ovrDur, sp.primaryMode)
            self:FillBars(self.ovrSecBars, self.ovrSecList, ovrSecD, ovrDur, sp.secondaryMode)
        else
            local ovrD = ns.Analysis and ns.Analysis:GetSorted(ovrSeg, mode) or {}
            self:FillBars(self.ovrPriBars, self.ovrPriList, ovrD, ovrDur, mode)
        end
    end
end

function UI:RefreshTitle()
    if not self.frame or not self.frame:IsShown() then return end
    if not self.titleText then return end

    -- 当前段标签
    local segL = ns.Segments and ns.Segments:GetViewLabel() or L["无数据"]

    -- 战斗状态点
    local dot = ns.state.inCombat and L["|cff00ff00[战]|r "] or ""

    -- 时长计算
    local dur = 0
    if ns.state.inCombat and ns.state.combatStartTime and ns.state.combatStartTime > 0 then
        local isViewingOverall = ns.Segments and ns.Segments.viewIndex == 0
        if isViewingOverall then
            dur = C_DamageMeter.GetSessionDurationSeconds(
                    Enum.DamageMeterSessionType.Overall) or 0
        else
            dur = C_DamageMeter.GetSessionDurationSeconds(
                    Enum.DamageMeterSessionType.Current) or 0
        end
    else
        local seg = ns.Segments and ns.Segments:GetViewSegment()
        -- M+ 段用钥石通关时间展示，其他段用战斗时间
        if seg and seg._keystoneTime and seg._keystoneTime > 0 then
            dur = seg._keystoneTime
        else
            dur = seg and (seg.duration or 0) or 0
        end
    end
    local tStr = dur > 0 and (" |cffaaaaaa" .. ns:FormatTime(dur) .. "|r") or ""

    -- ★ M+ 信息：格式改为 "+2 水闸行动" 紧跟段标签后面
    local mpStr = ""
    if ns.MythicPlus and ns.MythicPlus:IsActive() and ns.state.inMythicPlus then
        local info = ns.MythicPlus:GetHeaderInfo()
        if info then
            local levelStr = (info.level and info.level > 0)
                            and string.format("|cff4cb8e8+%d|r ", info.level) or ""
            local nameStr  = info.name and ("|cff4cb8e8" .. info.name .. "|r") or ""
            self.titleText:SetText(dot .. segL .. " " .. levelStr .. nameStr .. tStr)
            return
        end
    end

    -- 非 M+ 普通格式
    self.titleText:SetText(dot .. segL .. tStr)
end

-- ★ 新增：将字体设置强行应用到 UI 所有外围组件（解决你觉得实时没生效的错觉）
function UI:ApplyAllFonts()
    if not self.frame then return end
    local _, _, _, font, fSz, fOut, fShad = self:GetBarConfig()
    
    if self.titleText then self:ApplyFont(self.titleText, font, fSz, fOut, fShad) end
    if self.summText then self:ApplyFont(self.summText, font, fSz - 1, fOut, fShad) end
    
    local function applyHead(h)
        if h then
            self:ApplyFont(h.label, font, fSz - 1, fOut, fShad)
            self:ApplyFont(h.info, font, fSz - 1, fOut, fShad)
        end
    end
    applyHead(self.priHead); applyHead(self.secHead)
    applyHead(self.ovrPriHead); applyHead(self.ovrSecHead)
    
    if self.tabs then
        for _, t in ipairs(self.tabs) do
            self:ApplyFont(t.text, font, fSz - 1, fOut, fShad)
        end
    end
    if self.splitTab then self:ApplyFont(self.splitTab.text, font, fSz - 1, fOut, fShad) end
end

function UI:OnCombatStateChanged(inCombat)
    self:RefreshTitle(); self:Refresh()
end

function UI:RefreshHead(h, mode, seg, dur, apiSessionType)
    if not h:IsShown() then return end
    local mn   = L[ns.MODE_NAMES[mode] or mode]
    local ac   = mode=="damage" and T.dmgC or mode=="healing" and T.healC or mode=="damageTaken" and T.takenC or T.accent
    h.label:SetText(string.format("|cff%02x%02x%02x%s|r", ac[1]*255, ac[2]*255, ac[3]*255, mn))

    local total = 0
    if seg then
        if COUNT_MODES[mode] then
            for _, p in pairs(seg.players) do total = total + (p[mode] or 0) end
        else
            total = mode=="damage" and seg.totalDamage or mode=="healing" and seg.totalHealing or mode=="damageTaken" and seg.totalDamageTaken or 0
        end
        -- 替换：AbbreviateNumbers 改为 ns:FormatNumber
        local valStr = COUNT_MODES[mode] and (ns:FormatNumber(total)..L["次"]) or ns:FormatNumber(total)
        h.info:SetText(string.format(L["团队总%s: %s"], mn, valStr))
    elseif apiSessionType then
        local dmType = MODE_TO_DM[mode]
        if dmType then
            local session = self:GetCachedSession(apiSessionType, dmType)
            if session and session.totalAmount then
                total = session.totalAmount
                -- ★ 改用 SetFormattedText 把秘密数值直接扔给底层处理，避免 Lua 报错
                if COUNT_MODES[mode] then
                    h.info:SetFormattedText(L["团队总%s: %s次"], mn, AbbreviateNumbers(total))
                else
                    h.info:SetFormattedText(L["团队总%s: %s"], mn, AbbreviateNumbers(total))
                end
            else h.info:SetText("") end
        else h.info:SetText("") end
    else h.info:SetText("") end
end

-- ============================================================
-- 滑动条动态排版与填充逻辑 (适配更新后的交互数据)
-- ============================================================
function UI:FillBars(bars, listObj, data, dur, mode)
    local count = math.min(#data, MAX_BARS)
    self:UpdateScrollState(listObj, count)
    local maxV = data[1] and data[1].value or 0
    local barMode, textMode, texPath = ns.db.display.barColorMode or "class", ns.db.display.textColorMode or "class", ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    
    -- ★ 兜底：暴雪自带的各职业图标材质ID
    local CLASS_ICONS = { WARRIOR = 132355, PALADIN = 135490, HUNTER = 132222, ROGUE = 132320, PRIEST = 135940, DEATHKNIGHT = 135771, SHAMAN = 135962, MAGE = 135932, WARLOCK = 136145, MONK = 608951, DRUID = 132115, DEMONHUNTER = 1260827, EVOKER = 4567212 }

    for i, bar in ipairs(bars) do
        if i <= count then
            bar.frame:SetHeight(bh); bar.frame:ClearAllPoints()
            bar.frame:SetPoint("TOPLEFT", listObj.child, "TOPLEFT", 0, -((i-1)*(bh+gap)))
            bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, -((i-1)*(bh+gap)))
            self:AnchorBarTexts(bar)
            self:ApplyFont(bar.rank, font, fSz - 1, fOut, fShad)
            self:ApplyFont(bar.name, font, fSz, fOut, fShad)
            self:ApplyFont(bar.value, font, fSz - 1, fOut, fShad)

            local d = data[i]
            bar._data = d; bar._mode = mode; bar._isDeath = false
            bar._guid = d.guid; bar._nameStr = d.name; bar._classStr = d.class

            bar.statusbar:Hide(); bar.fill:Show()
            local cc = ns:GetClassColor(d.class) or {0.5, 0.5, 0.5}
            
            local offset = ns.db.display.showSpecIcon and ((bh - 4) + 6) or 0
            local maxBarWidth = math.max(1, listObj.child:GetWidth() - offset)
            bar.fill:SetWidth(math.max(1, maxBarWidth * (maxV > 0 and (d.value / maxV) or 0)))
            
            bar.statusbar:SetStatusBarTexture(texPath); bar.fill:SetTexture(texPath)

            if barMode == "class" then bar.statusbar:SetStatusBarColor(cc[1], cc[2], cc[3], alpha); bar.fill:SetVertexColor(cc[1], cc[2], cc[3], alpha)
            elseif barMode == "cyan" then bar.statusbar:SetStatusBarColor(0, 0.65, 1, alpha); bar.fill:SetVertexColor(0, 0.65, 1, alpha)
            else bar.statusbar:SetStatusBarColor(0.4, 0.4, 0.45, alpha); bar.fill:SetVertexColor(0.4, 0.4, 0.45, alpha) end

            bar.rank:SetText(ns.db.display.showRank and (i..".") or "")
            bar.name:SetText(ns:DisplayName(d.name))
            do
                local nr, ng, nb
                if textMode == "white" then
                    nr, ng, nb = 1, 1, 1
                elseif textMode == "custom" then
                    local c = ns.db.display.textColor or {1, 1, 1}
                    nr, ng, nb = c[1], c[2], c[3]
                else
                    nr, ng, nb = cc[1], cc[2], cc[3]
                end
                bar.name:SetTextColor(nr, ng, nb)
            end
            
            if bar.specIcon then
                local guid = bar._guid
                local specID = d and d.specID
                
                local seg = ns.Segments and ns.Segments:GetViewSegment()
                if seg and seg.isActive then
                    if guid == ns.state.playerGUID then
                        local specIdx = GetSpecialization()
                        if specIdx then specID = GetSpecializationInfo(specIdx) end
                    else
                        local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
                        specID = specID or cache.specID
                    end
                    if d and specID then d.specID = specID end
                end

                local icon = nil
                -- ★ 如果有专精，读专精图标；如果没有，读职业图标兜底
                if specID then _, _, _, icon = GetSpecializationInfoByID(specID) end
                if not icon and bar._classStr then icon = CLASS_ICONS[bar._classStr] end

                if ns.db.display.showSpecIcon and icon then
                    bar.specIcon:SetTexture(icon)
                    bar.specIcon:Show()
                else
                    bar.specIcon:Hide()
                end
            end
            
            bar.value:SetText(self:MakeValueStr(d.value, dur, mode, d.perSec))
            bar.frame:Show()
        else
            if bar.specIcon then bar.specIcon:Hide() end
            bar.frame:Hide(); bar._data = nil
        end
    end
end

function UI:FillBarsFromAPI(bars, listObj, mode, sessionType)
    local dmType = MODE_TO_DM[mode]
    if not dmType then
        self:UpdateScrollState(listObj, 0)
        for _, bar in ipairs(bars) do bar.frame:Hide() end
        return
    end

    local sType = sessionType or Enum.DamageMeterSessionType.Current
    local session = self:GetCachedSession(sType, dmType)
    if not session or not session.combatSources then
        self:UpdateScrollState(listObj, 0)
        for _, bar in ipairs(bars) do bar.frame:Hide() end
        return
    end

    local sources, maxAmt = session.combatSources, session.maxAmount
    local count = math.min(#sources, MAX_BARS)
    self:UpdateScrollState(listObj, count)

    local barMode  = ns.db.display.barColorMode  or "class"
    local textMode = ns.db.display.textColorMode or "class"
    local texPath  = ns.db.display.barTexture    or "Interface\\Buttons\\WHITE8X8"
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    
    local CLASS_ICONS = { WARRIOR = 132355, PALADIN = 135490, HUNTER = 132222, ROGUE = 132320, PRIEST = 135940, DEATHKNIGHT = 135771, SHAMAN = 135962, MAGE = 135932, WARLOCK = 136145, MONK = 608951, DRUID = 132115, DEMONHUNTER = 1260827, EVOKER = 4567212 }

    for i, bar in ipairs(bars) do
        if i <= count then
            local src = sources[i]
            bar.frame:SetHeight(bh)
            bar.frame:ClearAllPoints()
            bar.frame:SetPoint("TOPLEFT",  listObj.child, "TOPLEFT",  0, -((i-1)*(bh+gap)))
            bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, -((i-1)*(bh+gap)))
            self:AnchorBarTexts(bar)
            self:ApplyFont(bar.rank,  font, fSz - 1, fOut, fShad)
            self:ApplyFont(bar.name,  font, fSz,     fOut, fShad)
            self:ApplyFont(bar.value, font, fSz - 1, fOut, fShad)

            bar.fill:Hide()
            bar.statusbar:Show()

            local cls = src.classFilename or "WARRIOR"
            local cc  = ns:GetClassColor(cls) or {0.5, 0.5, 0.5}

            bar.statusbar:SetStatusBarTexture(texPath)
            bar.fill:SetTexture(texPath)

            local r, g, b = cc[1], cc[2], cc[3]
            if barMode == "cyan" then
                r, g, b = 0, 0.65, 1
            elseif barMode == "dark" then
                r, g, b = 0.4, 0.4, 0.45
            end
            bar.statusbar:SetStatusBarColor(r, g, b, alpha)
            local tex = bar.statusbar:GetStatusBarTexture()
            if tex then tex:SetVertexColor(r, g, b, alpha) end
            bar.fill:SetVertexColor(r, g, b, alpha)

            pcall(function()
                bar.statusbar:SetMinMaxValues(0, maxAmt or 1)
                bar.statusbar:SetValue(src.totalAmount)
            end)

            bar.rank:SetText(ns.db.display.showRank and (i .. ".") or "")
            local nameStr = ""
            pcall(function() nameStr = tostring(src.name or "") end)
            bar.name:SetText(ns:DisplayName(nameStr))
            bar._nameStr = nameStr

            do
                local nr, ng, nb
                if textMode == "white" then
                    nr, ng, nb = 1, 1, 1
                elseif textMode == "custom" then
                    local c = ns.db.display.textColor or {1, 1, 1}
                    nr, ng, nb = c[1], c[2], c[3]
                else
                    nr, ng, nb = cc[1], cc[2], cc[3]
                end
                bar.name:SetTextColor(nr, ng, nb)
            end

            -- ★ 直接使用暴雪的 SetFormattedText，彻底禁止在 Lua 中使用 string.format 和 ..
            if COUNT_MODES[mode] then
                bar.value:SetFormattedText("%s" .. L["次"], AbbreviateNumbers(src.totalAmount))
            else
                if ns.db.display.showPerSecond then
                    bar.value:SetFormattedText("%s(%s)", AbbreviateNumbers(src.totalAmount), AbbreviateNumbers(src.amountPerSecond))
                else
                    bar.value:SetText(AbbreviateNumbers(src.totalAmount))
                end
            end

            if not bar._apiData then bar._apiData = {} end
            bar._apiData.isAPI           = true
            bar._apiData.totalAmount     = src.totalAmount
            bar._apiData.amountPerSecond = src.amountPerSecond
            bar._apiData.sessionType     = sType

            bar._data = bar._apiData
            bar._mode     = mode
            bar._isDeath  = false

            local guid = src.sourceGUID
            bar._guid     = guid
            bar._nameStr  = src.name
            bar._classStr = cls
            
            -- ★ 修复：利用 API 提供的 isLocalPlayer 规避 Secret String 比较报错
            local specID = nil
            local ilvl   = 0
            local score  = 0
            
            -- 检查 guid 是否处于加密状态
            local isSecret = issecretvalue and issecretvalue(guid)

            if src.isLocalPlayer then
                -- 如果是自己：安全地获取自己的实时数据
                local specIdx = GetSpecialization()
                if specIdx then specID = GetSpecializationInfo(specIdx) end
                
                local _, equipped = GetAverageItemLevel()
                ilvl = math.floor(equipped or 0)
                
                -- 自己可以用本地未加密的 GUID 查表拿大秘境分数
                local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[ns.state.playerGUID] or {}
                score = cache.score or 0

            elseif not isSecret then
                -- 如果是队友且不在加密状态（如刚脱战/开放世界），正常查表
                local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
                specID = cache.specID
                ilvl   = cache.ilvl or 0
                score  = cache.score or 0
            end
            
            bar._apiData.specID = specID
            bar._apiData.ilvl   = ilvl
            bar._apiData.score  = score

            if bar.specIcon then
                local icon = nil
                -- 优先用我们查到的准确专精
                if specID then 
                    _, _, _, icon = GetSpecializationInfoByID(specID) 
                end
                
                -- 战斗中加密状态下拿不到队友专精，退而求其次用暴雪 API 永远不加密的 specIconID
                if not icon then icon = src.specIconID end
                -- 如果暴雪也没给，用职业图标兜底
                if not icon and cls then icon = CLASS_ICONS[cls] end

                if ns.db.display.showSpecIcon and icon then
                    bar.specIcon:SetTexture(icon)
                    bar.specIcon:Show()
                else
                    bar.specIcon:Hide()
                end
            end

            bar.frame:Show()
        else
            if bars[i].specIcon then bars[i].specIcon:Hide() end
            bar.statusbar:Hide()
            bar.fill:Show()
            bar.frame:Hide()
        end
    end
end


function UI:MakeValueStr(value, dur, mode, perSec)
    local vStr = ""
    if COUNT_MODES[mode] then
        -- 替换：AbbreviateNumbers 改为 ns:FormatNumber
        vStr = ns:FormatNumber(value) .. L["次"]
    else
        if ns.db.display.showPerSecond then

            local ps = (perSec and perSec > 0) and perSec
                       or (dur and dur > 0 and (value / dur) or nil)
            if ps then
                -- 替换：AbbreviateNumbers 改为 ns:FormatNumber
                vStr = string.format("%s(%s)", ns:FormatNumber(value), ns:FormatNumber(ps))
            else
                vStr = ns:FormatNumber(value)
            end
        else
            -- 替换：AbbreviateNumbers 改为 ns:FormatNumber
            vStr = ns:FormatNumber(value)
        end
    end
    return vStr
end

function UI:FillDeathBars(seg, bars, listObj)
    -- ★ 允许外部传入 bars 和 listObj，不传则默认用主列
    bars    = bars    or self.priBars
    listObj = listObj or self.priList

    local dl = ns.DeathTracker and ns.DeathTracker:GetDeathLog(seg) or {}
    local selfDeaths, otherDeaths = {}, {}
    for _, d in ipairs(dl) do
        if d.isSelf then table.insert(selfDeaths, d)
        else table.insert(otherDeaths, d) end
    end

    local items = {}
    if #selfDeaths > 0 then
        table.insert(items, { isSeparator=true, label=L["|cffff8888[自己的死亡]|r"], count=#selfDeaths })
        for _, d in ipairs(selfDeaths) do table.insert(items, { isSeparator=false, d=d }) end
    end
    if #otherDeaths > 0 then
        table.insert(items, { isSeparator=true, label=L["|cffaaaaaa[队友死亡]|r"], count=#otherDeaths })
        for _, d in ipairs(otherDeaths) do table.insert(items, { isSeparator=false, d=d }) end
    end

    local count = math.max(1, math.min(#items, MAX_BARS))
    self:UpdateScrollState(listObj, count)
    local cw = listObj.child:GetWidth()
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    
    -- ★ 新增：暴雪官方的职业图标兜底表
    local CLASS_ICONS = { WARRIOR = 132355, PALADIN = 135490, HUNTER = 132222, ROGUE = 132320, PRIEST = 135940, DEATHKNIGHT = 135771, SHAMAN = 135962, MAGE = 135932, WARLOCK = 136145, MONK = 608951, DRUID = 132115, DEMONHUNTER = 1260827, EVOKER = 4567212 }

    if #items == 0 then
        for _, bar in ipairs(bars) do bar.frame:Hide() end
        local bar = bars[1]; if not bar then return end
        bar.frame:SetHeight(bh)
        bar.frame:ClearAllPoints()
        bar.frame:SetPoint("TOPLEFT",  listObj.child, "TOPLEFT",  0, 0)
        bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, 0)
        self:AnchorBarTexts(bar)
        self:ApplyFont(bar.rank,  font, fSz - 1, fOut, fShad)
        self:ApplyFont(bar.name,  font, fSz,     fOut, fShad)
        self:ApplyFont(bar.value, font, fSz - 1, fOut, fShad)
        bar._data = nil; bar._isDeath = false; bar._guid = nil
        bar.statusbar:Hide()
        bar.fill:Show()
        bar.fill:SetWidth(1)
        bar.fill:SetVertexColor(0, 0, 0, 0)
        bar.rank:SetText("")
        bar.name:SetText(L["|cff555555本段暂无死亡记录|r"])
        bar.name:SetTextColor(1, 1, 1)
        bar.value:SetText("")
        if bar.specIcon then bar.specIcon:Hide() end -- ★ 修复：空数据时隐藏残留图标
        bar.frame:Show()
        return
    end

    for i = 1, MAX_BARS do
        local bar = bars[i]
        if i <= count then
            local item = items[i]
            bar.frame:SetHeight(bh)
            bar.frame:ClearAllPoints()
            bar.frame:SetPoint("TOPLEFT",  listObj.child, "TOPLEFT",  0, -((i-1)*(bh+gap)))
            bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, -((i-1)*(bh+gap)))
            self:AnchorBarTexts(bar)
            self:ApplyFont(bar.rank,  font, fSz - 1, fOut, fShad)
            self:ApplyFont(bar.name,  font, fSz,     fOut, fShad)
            self:ApplyFont(bar.value, font, fSz - 1, fOut, fShad)
            bar.statusbar:Hide()
            bar.fill:Show()

            if item.isSeparator then
                bar._data = nil; bar._isDeath = false; bar._guid = nil
                bar.fill:SetWidth(cw)
                bar.fill:SetVertexColor(0.06, 0.06, 0.08, 0.95)
                bar.rank:SetText("")
                bar.name:SetText(item.label .. string.format(" |cff666666(%d)|r", item.count))
                bar.name:SetTextColor(1, 1, 1)
                bar.value:SetText("")
                if bar.specIcon then bar.specIcon:Hide() end -- ★ 修复：分割线隐藏残留图标
            else
                local d = item.d
                bar._data     = d
                bar._mode     = "deaths"
                bar._isDeath  = true
                bar._guid     = d.playerGUID
                bar.fill:SetVertexColor(d.isSelf and 0.45 or 0.30, 0.05, 0.05, alpha)
                bar.fill:SetWidth(cw)
                bar.rank:SetText("|cff888888" .. (d.timestamp and date("%H:%M", d.timestamp) or "--:--") .. "|r")
                local cc = ns:GetClassColor(d.playerClass)
                bar.name:SetText(ns:DisplayName(d.playerName or "?"))
                bar.name:SetTextColor(cc[1], cc[2], cc[3])
                local killStr = "|cffff5555" .. (d.killingAbility or "?") .. "|r"
                if d.killerName and d.killerName ~= "" and d.killerName ~= "?" then
                    killStr = killStr .. " |cff888888by |r|cffcccccc" .. ns:DisplayName(d.killerName) .. "|r"
                end
                bar.value:SetText(killStr)
                
                -- ★ 修复：为死亡玩家匹配正确的专精图标
                if bar.specIcon then
                    local icon = nil
                    local guid = d.playerGUID
                    local specID = nil
                    
                    -- 1. 从缓存中获取队友的专精
                    local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
                    specID = cache.specID
                    
                    -- 2. 如果死的是自己，实时获取最新专精
                    if guid == ns.state.playerGUID then
                        local specIdx = GetSpecialization()
                        if specIdx then specID = GetSpecializationInfo(specIdx) end
                    end
                    
                    -- 3. 获取图标ID
                    if specID then 
                        _, _, _, icon = GetSpecializationInfoByID(specID) 
                    end
                    
                    -- 4. 兜底逻辑：如果在战斗中等情况没扫到专精，用基础职业图标代替
                    if not icon and d.playerClass then 
                        icon = CLASS_ICONS[d.playerClass] 
                    end

                    if ns.db.display.showSpecIcon and icon then
                        bar.specIcon:SetTexture(icon)
                        bar.specIcon:Show()
                    else
                        bar.specIcon:Hide()
                    end
                end
            end
            bar.frame:Show()
        else
            bars[i].frame:Hide()
        end
    end
end

-- ============================================================
-- ★ 修复：完美兼容战斗 API 安全提示框
-- ============================================================
function UI:ShowTooltip(bar, section)
    local d = bar._data; if not d then return end
    GameTooltip:SetOwner(bar.frame, "ANCHOR_LEFT")

    local guid = bar._guid
    local seg  = ns.Segments and ns.Segments:GetViewSegment()
    local specID, ilvl, score
    
    -- ★ 工具提示数据获取逻辑精简：API模式下绝对不要再去查 guid，直接读存好的数据
    if d and d.isAPI then
        specID = d.specID
        ilvl   = d.ilvl or 0
        score  = d.score or 0
    elseif seg and seg.isActive then
        local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
        specID = (d and d.specID) or cache.specID
        ilvl   = (d and d.ilvl)   or cache.ilvl or 0
        score  = (d and d.score)  or cache.score or 0
        
        if guid == ns.state.playerGUID then
            local specIdx = GetSpecialization()
            if specIdx then specID = GetSpecializationInfo(specIdx) end
        end
        
        if d then
            d.specID = specID
            d.ilvl   = ilvl
            d.score  = score
        end
    else
        specID = d and d.specID
        ilvl   = d and d.ilvl or 0
        score  = d and d.score or 0
    end

    local specName = ""
    if specID then
        local _, name = GetSpecializationInfoByID(specID)
        if name then specName = name end
    end

    local function AddPlayerInfoLines()
        -- ★ 核心修改：只有大于 0 或不为空时，才会添加这些行，否则直接跳过
        if specName ~= "" or (ilvl and ilvl > 0) or (score and score > 0) then
            GameTooltip:AddLine(" ")
            if specName ~= "" then
                GameTooltip:AddDoubleLine(L["专精"], specName, 0.7,0.7,0.7, 1,1,1)
            end
            if ilvl and ilvl > 0 then
                GameTooltip:AddDoubleLine(L["平均装等"], tostring(ilvl), 0.7,0.7,0.7, 1,0.85,0)
            end
            if score and score > 0 then
                -- ★ 修复：改用获取赛季总分颜色的 API
                local color = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
                if color then
                    GameTooltip:AddDoubleLine(L["大秘境评分"], color:WrapTextInColorCode(tostring(score)), 0.7,0.7,0.7, 1,1,1)
                else
                    GameTooltip:AddDoubleLine(L["大秘境评分"], tostring(score), 0.7,0.7,0.7, 1,0.5,0)
                end
            end
        end
    end

    if bar._isDeath then
        GameTooltip:AddLine(ns:GetClassHex(d.playerClass)..ns:DisplayName(d.playerName)..L["|r [死亡]"])
        AddPlayerInfoLines()
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["致命技能"], d.killingAbility or "?", 0.7,0.7,0.7, 1,0.3,0.3)
        GameTooltip:AddDoubleLine(L["击杀者"],   ns:DisplayName(d.killerName) or "?", 0.7,0.7,0.7, 1,1,1)
        GameTooltip:AddDoubleLine(L["死前受伤"], ns:FormatNumber(d.totalDamageTaken or 0),     0.7,0.7,0.7, 1,0.5,0.5)
        GameTooltip:AddDoubleLine(L["死前受治"], ns:FormatNumber(d.totalHealingReceived or 0), 0.7,0.7,0.7, 0.5,1,0.5)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["|cff00ccff点击查看完整死亡日志|r"], 0.4,0.4,0.4)
        GameTooltip:Show(); return
    end

    if d.isAPI then
        GameTooltip:AddLine(ns:GetClassHex(bar._classStr)..ns:DisplayName(bar._nameStr or "?").."|r")
        AddPlayerInfoLines()
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["|cffaaaaaa— 战斗中 (实时) —|r"])
        
        -- ★ 分开传递秘密数值给 GameTooltip
        if COUNT_MODES[bar._mode] then
            GameTooltip:AddDoubleLine((L[ns.MODE_NAMES[bar._mode] or bar._mode]) .. L["次"], AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
        elseif ns.db.display.showPerSecond then
            GameTooltip:AddDoubleLine(ns.MODE_NAMES[bar._mode] or bar._mode, AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
            GameTooltip:AddDoubleLine(L["每秒"], AbbreviateNumbers(d.amountPerSecond), 0.7,0.7,0.7, 1,0.85,0)
        else
            GameTooltip:AddDoubleLine(ns.MODE_NAMES[bar._mode] or bar._mode, AbbreviateNumbers(d.totalAmount), 0.7,0.7,0.7, 1,1,1)
        end
        
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["|cff00ccff左键: 技能细分  右键: 切换模式|r"], 0.4,0.4,0.4)
        GameTooltip:Show()
        return
    end

    local mode = bar._mode or ns.db.display.mode
    local dur  = ns.Analysis  and ns.Analysis:GetSegmentDuration(seg) or 0
    local mn   = L[ns.MODE_NAMES[mode] or mode]

    GameTooltip:AddLine(ns:GetClassHex(d.class)..ns:DisplayName(d.name or "?").."|r")
    AddPlayerInfoLines()
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["|cffaaaaaa— 本段 —|r"])
    GameTooltip:AddDoubleLine(mn, ns:FormatNumber(d.value), 0.7,0.7,0.7, 1,1,1)
    if dur > 0 and ns.MODE_UNITS[mode] then
        GameTooltip:AddDoubleLine(ns.MODE_UNITS[mode], string.format("%.1f", d.value/dur), 0.7,0.7,0.7, 1,0.85,0)
    end
    GameTooltip:AddDoubleLine(L["占比"], string.format("%.1f%%", d.percent or 0), 0.7,0.7,0.7, 1,1,1)
    if d.petDamage and d.petDamage > 0 and mode == "damage" then
        GameTooltip:AddDoubleLine(L["含宠物"], ns:FormatNumber(d.petDamage), 0.5,0.5,0.5, 0.7,0.7,0.7)
    end

    if ns.db.split.enabled and seg then
        local other = (section=="primary") and ns.db.split.secondaryMode or ns.db.split.primaryMode
        if other ~= mode and seg.players[d.guid] then
            local ov = ns.Analysis and ns.Analysis:GetPlayerValue(seg.players[d.guid], other, seg)
            if ov and ov > 0 then
                GameTooltip:AddLine(" ")
                local on2 = L[ns.MODE_NAMES[other] or other]
                GameTooltip:AddDoubleLine(on2, ns:FormatNumber(ov), 0.7,0.7,0.7, 1,1,1)
                if dur > 0 then GameTooltip:AddDoubleLine(ns.MODE_UNITS[other] or "", string.format("%.1f",ov/dur), 0.7,0.7,0.7, 1,0.85,0) end
            end
        end
    end

    if self:IsOverallColumnActive() then
        local ovd = ns.Analysis and ns.Analysis:GetOverallPlayerData(d.guid, mode)
        if ovd then
            local ac = T.accent or {0.0, 0.65, 1.0}
            GameTooltip:AddLine(" ")

            local ovrTitleWord = L["总计"]
            if ns.Segments and ns.Segments.overall and ns.Segments.overall._isMerged then
                ovrTitleWord = L["全程"]
            end
            
            GameTooltip:AddLine(string.format(L["|cff%02x%02x%02x— %s —|r"], ac[1]*255, ac[2]*255, ac[3]*255, ovrTitleWord))
            
            GameTooltip:AddDoubleLine(string.format(L["%s%s"], ovrTitleWord, mn), ns:FormatNumber(ovd.value), 0.7,0.7,0.7, 1,1,1)
            
            if ovd.dur > 0 and ns.MODE_UNITS[mode] then 
                GameTooltip:AddDoubleLine(string.format(L["%s%s"], ovrTitleWord, ns.MODE_UNITS[mode]), string.format("%.1f",ovd.perSec), 0.7,0.7,0.7, 1,0.85,0) 
            end
            
            GameTooltip:AddDoubleLine(string.format(L["%s占比"], ovrTitleWord), string.format("%.1f%%", ovd.percent), 0.7,0.7,0.7, ac[1],ac[2],ac[3])
        end
    end

    GameTooltip:AddLine(" ")
    if d.deaths and d.deaths > 0 then GameTooltip:AddDoubleLine(L["死亡"], d.deaths, 0.7,0.7,0.7, 1,0.3,0.3) end
    if d.interrupts and d.interrupts > 0 then GameTooltip:AddDoubleLine(L["打断"], d.interrupts, 0.7,0.7,0.7, 0.3,1,0.3) end
    if d.dispels and d.dispels > 0 then GameTooltip:AddDoubleLine(L["驱散"], d.dispels, 0.7,0.7,0.7, 0.3,0.8,1) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["|cff00ccff左键: 技能细分  右键: 切换模式|r"], 0.4,0.4,0.4)
    GameTooltip:Show()
end

function UI:Toggle()
    self:EnsureCreated()
    if self.frame:IsShown() then self.frame:Hide()
    else self.frame:Show(); self:Layout() end
end

function UI:IsVisible()
    return self.frame and self.frame:IsShown()
end

function UI:UpdateLock() end