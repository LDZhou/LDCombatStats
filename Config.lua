--[[
    LD Combat Stats - Config.lua
]]

local addonName, ns = ...
local L = ns.L

local SCROLL_EXTRA_PAD = 150
local Config = {}

StaticPopupDialogs["LDCS_RENAME_PROFILE"] = {
    text = L["输入新的配置名称:"],     -- <--- 加上 L[]
    button1 = L["确定"],               -- <--- 加上 L[]
    button2 = L["取消"],               -- <--- 加上 L[]
    hasEditBox = 1,
    OnAccept = function(self, data)
        local eb = self.EditBox or self.editBox or _G[self:GetName().."EditBox"]
        local newName = eb:GetText():trim()
        local oldName = data
        if newName ~= "" and newName ~= oldName then
            if LDCombatStatsGlobal.profiles[newName] then
                print(L["配置名称已存在！"])   -- <--- 加上 L[]
            else
                ns:RenameProfile(oldName, newName)
                if ns.Config then ns.Config:RefreshProfilesPage() end
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent()
        local newName = self:GetText():trim()
        local oldName = popup.data
        if newName ~= "" and newName ~= oldName then
            if LDCombatStatsGlobal.profiles[newName] then
                print(L["配置名称已存在！"])   -- <--- 加上 L[]
            else
                ns:RenameProfile(oldName, newName)
                if ns.Config then ns.Config:RefreshProfilesPage() end
                popup:Hide()
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["LDCS_CONFIRM_DELETE_PROFILE"] = {
    text = L["确定要删除配置 '%s' 吗？"],
    button1 = L["确定"],
    button2 = L["取消"],
    OnAccept = function(self, data)
        ns:DeleteProfile(data)
        if ns.Config then ns.Config:RefreshProfilesPage() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}


-- 10名玩家，数值写死，每次预览完全相同
local PREVIEW_MOCK = {
    {name="Arcsmith",    class="MAGE",        damage=14200000, dps=21300, healing= 320000, hps=  480, damageTaken=2800000, deaths=0, interrupts=8, dispels=3},
    {name="Ironhide",    class="WARRIOR",     damage=12800000, dps=19200, healing= 180000, hps=  270, damageTaken=3200000, deaths=1, interrupts=5, dispels=0},
    {name="Thornwood",   class="DRUID",       damage=11500000, dps=17250, healing=9800000, hps=14700, damageTaken=1200000, deaths=0, interrupts=2, dispels=4},
    {name="Voidweaver",  class="WARLOCK",     damage=10900000, dps=16350, healing= 420000, hps=  630, damageTaken=1900000, deaths=0, interrupts=0, dispels=1},
    {name="Swiftbolt",   class="HUNTER",      damage= 9800000, dps=14700, healing= 280000, hps=  420, damageTaken=2100000, deaths=2, interrupts=3, dispels=0},
    {name="Dawnstrike",  class="PALADIN",     damage= 8600000, dps=12900, healing=8200000, hps=12300, damageTaken=1800000, deaths=0, interrupts=6, dispels=5},
    {name="Frostmantle", class="DEATHKNIGHT", damage= 7900000, dps=11850, healing= 150000, hps=  225, damageTaken=4100000, deaths=1, interrupts=0, dispels=0},
    {name="Embercrest",  class="ROGUE",       damage= 7200000, dps=10800, healing= 200000, hps=  300, damageTaken=1600000, deaths=0, interrupts=9, dispels=0},
    {name="Silvermist",  class="PRIEST",      damage= 5100000, dps= 7650, healing=12400000,hps=18600, damageTaken= 900000, deaths=4, interrupts=1, dispels=8},
    {name="Stonehowl",   class="SHAMAN",      damage= 5800000, dps= 8700, healing=6800000, hps=10200, damageTaken=1500000, deaths=0, interrupts=4, dispels=2},
}

local PREVIEW_SCENES = {
    { id="mplus",    labelKey="大秘境",  hasSumm=true,  hasOvr=true  },
    { id="instance", labelKey="其他副本", hasSumm=false, hasOvr=true  },
    { id="outdoor",  labelKey="非副本",  hasSumm=false, hasOvr=false },
}

ns.Config = Config

local PANEL_W   = 500
local PANEL_H   = 480
local SIDEBAR_W = 110
local CAT_H     = 34

local categories = {
    {id="layout", labelKey="布局",   icon="-"},
    {id="data",   labelKey="数据",   icon="-"},
    {id="look",   labelKey="外观",   icon="-"},
    {id="perf",   labelKey="性能",   icon="-"},
    {id="profiles", labelKey="配置管理", icon="-"},
}

-- ============================================================
-- 原生颜色选择器封装
-- ============================================================
local function OpenColorPicker(r, g, b, a, onApply, onCancel)
    local prev = { r=r, g=g, b=b, a=a }

    local function Apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na         = ColorPickerFrame:GetColorAlpha()  -- 0=全透明 1=不透明
        onApply(nr, ng, nb, na)
    end

    ColorPickerFrame:SetupColorPickerAndShow({
        r           = r,
        g           = g,
        b           = b,
        opacity     = a,        -- 直接传 alpha，0=透明 1=不透明
        hasOpacity  = true,
        swatchFunc  = Apply,
        opacityFunc = Apply,
        cancelFunc  = function()
            onCancel(prev.r, prev.g, prev.b, prev.a)
        end,
    })
end

-- ============================================================
-- 工具
-- ============================================================
function Config:FillBg(f, r, g, b, a)
    local t = f:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints()
    t:SetColorTexture(r, g, b, a); return t
end

function Config:CreateBorder(f, r, g, b, a, size)
    local s = size or 1
    -- ★ 修复：将层级改为 BACKGROUND，且 sublevel 设为 -8，确保实心边框永远垫在最底层
    local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetPoint("TOPLEFT", -s, s); t:SetPoint("BOTTOMRIGHT", s, -s)
    t:SetColorTexture(r, g, b, a); return t
end

function Config:AddCheckerboard(btn, w, h)
    w = w or 48; h = h or 16
    local size = 8 -- 棋盘格方块大小(8x8像素)
    
    -- 铺一层纯白底色
    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 1)
    
    -- 铺浅灰色方块形成棋盘格交错
    for y = 0, math.ceil(h/size)-1 do
        for x = 0, math.ceil(w/size)-1 do
            if (x + y) % 2 == 1 then
                local sq = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
                sq:SetSize(size, size)
                sq:SetPoint("TOPLEFT", btn, "TOPLEFT", x*size, -y*size)
                sq:SetColorTexture(0.75, 0.75, 0.75, 1)
            end
        end
    end
end

function Config:RefreshTitle()
    if self.titleText then
        local pName = LDCombatStatsDB and LDCombatStatsDB.activeProfile or "默认"
        local displayName = (pName == "默认") and L["默认"] or pName
        self.titleText:SetText(string.format(L["|cff00ccffLD Combat Stats|r 设置 - %s"], displayName))
    end
end

function Config:Toggle()
    if not self.panel then self:Build() end
    if self.panel:IsShown() then self.panel:Hide() else self.panel:Show() end
end

function Config:BuildPreviewBtn()
    local titleFrame = self._configTitle
    if not titleFrame then return end

    local btn = CreateFrame("Button", nil, titleFrame)  -- 父级改为 title
    btn:SetSize(52, 22)
    -- X关闭按钮在 RIGHT -4，宽24；预览按钮紧靠其左侧
    btn:SetPoint("RIGHT", titleFrame, "RIGHT", -32, 0)

    self:FillBg(btn, 0.05, 0.20, 0.35, 1)
    self:CreateBorder(btn, 0.1, 0.45, 0.75, 1)

    local bt = btn:CreateFontString(nil, "OVERLAY")
    bt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    bt:SetPoint("CENTER"); bt:SetText(L["预览"]); bt:SetTextColor(0.4, 0.85, 1)

    btn:SetScript("OnClick", function() self:TogglePreview() end)
    btn:SetScript("OnEnter", function() bt:SetTextColor(1, 1, 1) end)
    btn:SetScript("OnLeave", function() bt:SetTextColor(0.4, 0.85, 1) end)

    self._previewBtn  = btn
    self._previewBtnT = bt
end

function Config:Build()
    local p = CreateFrame("Frame", "LDStatsConfig", UIParent, "BackdropTemplate")
    p:SetSize(PANEL_W, PANEL_H); p:SetPoint("CENTER")
    p:SetFrameStrata("DIALOG"); p:SetFrameLevel(100)
    p:SetMovable(true); p:EnableMouse(true); p:SetClampedToScreen(true)
    
    -- 极简底色
    p:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile=nil, edgeSize=0 })
    p:SetBackdropColor(0.05, 0.05, 0.06, 0.98)
    p:Hide(); self.panel = p

    -- 标题栏使用主题色
    local tc = ns.db.window.themeColor or {0.08, 0.08, 0.12, 1}
    local title = CreateFrame("Frame", nil, p)
    title:SetHeight(30); title:SetPoint("TOPLEFT", 0, 0); title:SetPoint("TOPRIGHT", 0, 0)
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() p:StartMoving() end)
    title:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    self.titleBg = self:FillBg(title, unpack(tc))
    self._configTitle = title   -- ← 新增：保存引用供预览按钮使用
    
    local tt = title:CreateFontString(nil, "OVERLAY")
    tt:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE"); tt:SetPoint("LEFT", 12, 0)
    self.titleText = tt
    self:RefreshTitle()

    local cb = CreateFrame("Button", nil, title); cb:SetSize(24, 24); cb:SetPoint("RIGHT", -4, 0)
    local ct = cb:CreateFontString(nil, "OVERLAY")
    ct:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE"); ct:SetPoint("CENTER"); ct:SetText("X"); ct:SetTextColor(0.5, 0.5, 0.5)
    cb:SetScript("OnClick", function() p:Hide() end)
    cb:SetScript("OnEnter", function() ct:SetTextColor(1, 0.2, 0.2) end)
    cb:SetScript("OnLeave", function() ct:SetTextColor(0.5, 0.5, 0.5) end)

    local sidebar = CreateFrame("Frame", nil, p)
    sidebar:SetWidth(SIDEBAR_W)
    sidebar:SetPoint("TOPLEFT", 0, -30); sidebar:SetPoint("BOTTOMLEFT", 0, 0)
    self:FillBg(sidebar, 0.03, 0.03, 0.04, 1)

    local content = CreateFrame("Frame", nil, p)
    content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
    self.contentArea = content

    self.catBtns = {}; self.pages = {}
    for i, cat in ipairs(categories) do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(SIDEBAR_W, CAT_H)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -((i-1)*CAT_H))

        btn.activeBg = btn:CreateTexture(nil, "BORDER"); btn.activeBg:SetAllPoints()
        btn.activeBg:SetColorTexture(0, 0.65, 1, 0.15); btn.activeBg:Hide()

        local icon = btn:CreateFontString(nil, "OVERLAY")
        icon:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
        icon:SetPoint("LEFT", 14, 0); icon:SetText(cat.icon); icon:SetTextColor(0.5, 0.5, 0.5)

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont(STANDARD_TEXT_FONT, 11, "")
        label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        label:SetText(L[cat.labelKey]); label:SetTextColor(0.6, 0.6, 0.6)

        btn.icon = icon; btn.label = label
        btn:SetScript("OnClick", function() self:ShowPage(cat.id) end)
        btn:SetScript("OnEnter", function() if self.activeCat ~= cat.id then label:SetTextColor(1,1,1); icon:SetTextColor(0.8,0.8,0.8) end end)
        btn:SetScript("OnLeave", function() if self.activeCat ~= cat.id then label:SetTextColor(0.6,0.6,0.6); icon:SetTextColor(0.5,0.5,0.5) end end)

        self.catBtns[cat.id] = btn

        local page = CreateFrame("ScrollFrame", nil, content)
        page:SetPoint("TOPLEFT", 12, -12)
        page:SetPoint("BOTTOMRIGHT", -8, 12)

        local inner = CreateFrame("Frame", nil, page)
        inner:SetWidth(PANEL_W - SIDEBAR_W - 30)
        inner:SetHeight(800)
        page:SetScrollChild(inner)

        -- 极简细滑动条
        local sb = CreateFrame("Slider", nil, page)
        sb:SetWidth(4)
        sb:SetPoint("TOPRIGHT",    page, "TOPRIGHT",    0,  0)
        sb:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0,  0)
        sb:SetOrientation("VERTICAL")
        sb:SetMinMaxValues(0, 0); sb:SetValue(0)
        
        local sbTrack = sb:CreateTexture(nil, "BACKGROUND")
        sbTrack:SetAllPoints(); sbTrack:SetColorTexture(0.05, 0.05, 0.06, 1)
        
        sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local sbThumb = sb:GetThumbTexture()
        sbThumb:SetVertexColor(0.3, 0.3, 0.35, 1); sbThumb:SetSize(4, 30)
        
        -- 增加悬停交互
        sb:SetScript("OnEnter", function() sbThumb:SetVertexColor(0.4, 0.4, 0.45, 1) end)
        sb:SetScript("OnLeave", function() sbThumb:SetVertexColor(0.3, 0.3, 0.35, 1) end)

        page:SetScript("OnMouseWheel", function(_, delta)
            local cur = sb:GetValue()
            local _, mx = sb:GetMinMaxValues()
            sb:SetValue(math.max(0, math.min(mx, cur - delta * 32)))
        end)
        sb:SetScript("OnValueChanged", function(_, val) page:SetVerticalScroll(val) end)

        page:Hide()
        self.pages[cat.id] = { scroll = page, inner = inner, sb = sb }
    end

    self:BuildLayoutPage(); self:BuildDataPage();
    self:BuildLookPage(); self:BuildPerfPage(); self:BuildProfilesPage()
    self:ShowPage("layout")

    -- 预览按钮 & 关闭时联动
    self:BuildPreviewBtn()
    self:BuildSceneSwitcher()
    p:HookScript("OnHide", function() self:ClosePreview() end)
    tinsert(UISpecialFrames, "LDStatsConfig")
end

function Config:ShowPage(id)
    self.activeCat = id
    for cid, btn in pairs(self.catBtns) do
        if cid == id then
            btn.activeBg:Show(); btn.icon:SetTextColor(0, 0.75, 1); btn.label:SetTextColor(1, 1, 1)
        else
            btn.activeBg:Hide(); btn.icon:SetTextColor(0.5, 0.5, 0.5); btn.label:SetTextColor(0.6, 0.6, 0.6)
        end
    end
    for pid, page in pairs(self.pages) do
        if pid == id then page.scroll:Show() else page.scroll:Hide() end
    end
    -- 新增：切到配置管理时刷新列表
    if id == "profiles" then self:RefreshProfilesPage() end
    self:UpdatePageScroll(id)
end

function Config:UpdatePageScroll(id)
    local pg = self.pages[id]
    if not pg or not pg.sb then return end
    local page = pg.scroll
    local sb   = pg.sb
    local viewH    = page:GetHeight()
    local contentH = pg.inner:GetHeight()
    local maxScroll = math.max(0, contentH + SCROLL_EXTRA_PAD - viewH)
    sb:SetMinMaxValues(0, maxScroll)
    if maxScroll > 0 then sb:Show() else sb:Hide(); sb:SetValue(0) end
end

function Config:BuildLayoutPage()
    local inner = self.pages["layout"].inner
    
    -- 区域1：语言
    local sec1 = CreateFrame("Frame", nil, inner)
    sec1:SetWidth(PANEL_W)
    local y1 = 0
    y1 = self:H(sec1, L["界面语言"], y1)
    y1 = self:Dropdown(sec1, L["语言 (需要重载UI生效)"], y1, { {l=L["跟随客户端"], v="auto"}, {l="简体中文", v="zhCN"}, {l="繁体中文", v="zhTW"}, {l="English", v="enUS"} }, function() return ns.db.display.language or "auto" end, function(v) ns.db.display.language = v; ReloadUI() end)
    sec1:SetHeight(math.abs(y1))
    self.laySec1 = sec1

    -- 区域2：当前与总计
    local sec2 = CreateFrame("Frame", nil, inner)
    sec2:SetWidth(PANEL_W)
    local y2 = 0
    y2 = self:H(sec2, L["当前与总计窗口"], y2)
    y2 = self:Check(sec2, L["同时显示当前与总计数据"], y2, 
        function() return ns.db.split.showOverall end, 
        function(v) ns.db.split.showOverall = v; self:RefreshUI(); self:UpdateLayoutVisibility() end,
        L["OVERALL_DATA_TOOLTIP"]) -- ★ 传入翻译好的问号提示文本
        
    local sec2_sub = CreateFrame("Frame", nil, sec2)
    sec2_sub:SetWidth(PANEL_W)
    sec2_sub:SetPoint("TOPLEFT", sec2, "TOPLEFT", 0, y2)
    local y2s = 0

    local showModes = { {l=L["总是开启"], v="always"}, {l=L["所有副本开启"], v="instance"}, {l=L["只在大秘境中开启"], v="mplus"}, {l=L["永不开启"], v="off"} }
    y2s = self:Dropdown(sec2_sub, L["开启场景"], y2s, showModes, function() return ns.db.split.overallShowMode or "mplus" end, function(v) ns.db.split.overallShowMode = v; self:RefreshUI() end)
    y2s = y2s - 8
    
    -- ★ 新增：分离文字选项并前置声明变量
    local posesLR = { {l=L["左侧"], v=1}, {l=L["右侧"], v=2} }
    local posesTB = { {l=L["上方"], v=1}, {l=L["下方"], v=2} }
    local curPosBtn, priPosBtn

    local dirs = { {l=L["左右划分"], v="LR"}, {l=L["上下划分"], v="TB"} }
    y2s = self:Dropdown(sec2_sub, L["当前/总计划分方向"], y2s, dirs, function() return ns.db.split.overallDir or "LR" end, 
        function(v) 
            ns.db.split.overallDir = v
            ns.db.split.splitDir = (v == "LR") and "TB" or "LR" 
            
            -- ★ 核心联动：动态刷新位置选项的文字
            if curPosBtn then curPosBtn.UpdateOpts(v == "TB" and posesTB or posesLR) end
            if priPosBtn then priPosBtn.UpdateOpts(ns.db.split.splitDir == "TB" and posesTB or posesLR) end
            
            self:RefreshUI(); self:UpdateLayoutVisibility() 
        end)
    
    -- ★ 修改：赋予初值时自动判断当前的划分方向，并保存按钮引用
    y2s, curPosBtn = self:Dropdown(sec2_sub, L["当前数据位置"], y2s, (ns.db.split.overallDir == "TB") and posesTB or posesLR, function() return ns.db.split.currentPos or 1 end, function(v) ns.db.split.currentPos = v; self:RefreshUI() end)
    sec2_sub:SetHeight(math.abs(y2s))
    self.laySec2Sub = sec2_sub
    self.laySec2 = sec2

    -- 区域3：双数据显示
    local sec3 = CreateFrame("Frame", nil, inner)
    sec3:SetWidth(PANEL_W)
    local y3 = 0
    y3 = self:H(sec3, L["双数据显示"], y3)
    y3 = self:Check(sec3, L["开启双数据显示"], y3, 
        function() return ns.db.split.enabled end, 
        function(v) 
            ns.db.split.enabled = v; 
            if v then 
                if ns.db.display.mode ~= "split" then ns.db.display.mode = "split" end
            else 
                if ns.db.display.mode == "split" then ns.db.display.mode = ns.db.split.primaryMode or "damage" end
            end
            self:RefreshUI(); 
            self:UpdateLayoutVisibility() 
        end)

    local sec3_sub = CreateFrame("Frame", nil, sec3)
    sec3_sub:SetWidth(PANEL_W)
    sec3_sub:SetPoint("TOPLEFT", sec3, "TOPLEFT", 0, y3)
    local y3s = 0
    local allModes = { {l=L["伤害"], v="damage"}, {l=L["治疗"], v="healing"}, {l=L["承伤"], v="damageTaken"}, {l=L["死亡"], v="deaths"}, {l=L["打断"], v="interrupts"}, {l=L["驱散"], v="dispels"} }
    
    -- ★ 修改：副框数据赋予初值时也自动判断方向
    y3s, priPosBtn = self:Dropdown(sec3_sub, L["主数据位置"], y3s, (ns.db.split.splitDir == "TB") and posesTB or posesLR, function() return ns.db.split.primaryPos or 1 end, function(v) ns.db.split.primaryPos = v; self:RefreshUI() end)
    y3s = self:Dropdown(sec3_sub, L["主数据内容"], y3s, allModes, function() return ns.db.split.primaryMode end, function(v) ns.db.split.primaryMode=v; self:RefreshUI() end)
    y3s = self:Dropdown(sec3_sub, L["副数据内容"], y3s, allModes, function() return ns.db.split.secondaryMode end, function(v) ns.db.split.secondaryMode=v; self:RefreshUI() end)
    sec3_sub:SetHeight(math.abs(y3s))

    self.laySec3Sub = sec3_sub
    self.laySec3 = sec3

    -- 区域4：比例调节
    local sec4 = CreateFrame("Frame", nil, inner)
    sec4:SetWidth(PANEL_W)
    local y4 = 0
    y4 = self:H(sec4, L["自适应布局比例"], y4)
    y4 = self:Slider(sec4, L["上下分栏比例"], y4, 0.2, 0.8, 0.05, function() return ns.db.split.tbRatio or 0.5 end, function(v) ns.db.split.tbRatio = v; self:RefreshUI() end, true)
    y4 = self:Slider(sec4, L["左右分栏比例"], y4, 0.2, 0.8, 0.05, function() return ns.db.split.lrRatio or 0.5 end, function(v) ns.db.split.lrRatio = v; self:RefreshUI() end, true)
    sec4:SetHeight(math.abs(y4))
    self.laySec4 = sec4
    
    self:UpdateLayoutVisibility()
end

function Config:UpdateLayoutVisibility()
    local inner = self.pages["layout"].inner
    
    if ns.db.split.showOverall then
        self.laySec2Sub:Show()
        self.laySec2:SetHeight(48 + self.laySec2Sub:GetHeight())
    else
        self.laySec2Sub:Hide()
        self.laySec2:SetHeight(48)
    end

    if ns.db.split.enabled then
        self.laySec3Sub:Show()
        self.laySec3:SetHeight(48 + self.laySec3Sub:GetHeight())
    else
        self.laySec3Sub:Hide()
        self.laySec3:SetHeight(48)
    end

    -- 按照顺序堆叠各个区块，不再写死坐标
    self.laySec1:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
    self.laySec2:SetPoint("TOPLEFT", self.laySec1, "BOTTOMLEFT", 0, -12)
    self.laySec3:SetPoint("TOPLEFT", self.laySec2, "BOTTOMLEFT", 0, -12)
    self.laySec4:SetPoint("TOPLEFT", self.laySec3, "BOTTOMLEFT", 0, -12)

    local totalH = self.laySec1:GetHeight() + self.laySec2:GetHeight() + self.laySec3:GetHeight() + self.laySec4:GetHeight() + 48
    inner:SetHeight(totalH)
    
    self:UpdatePageScroll("layout")
end

function Config:BuildDataPage()
    local inner = self.pages["data"].inner; local y = 0
    y = self:H(inner, L["数据显示格式"], y)
    y = self:Check(inner, L["同时显示伤害总量和DPS"], y, function() return ns.db.display.showPerSecond end, function(v) ns.db.display.showPerSecond=v; self:RefreshUI() end)
    y = self:Check(inner, L["显示排名序号"], y, function() return ns.db.display.showRank end, function(v) ns.db.display.showRank=v; self:RefreshUI() end)
    y = self:Check(inner, L["在最左侧显示专精图标"], y, function() return ns.db.display.showSpecIcon end, function(v) ns.db.display.showSpecIcon=v; self:RefreshUI() end)
    y = self:Check(inner, L["显示玩家服务器"], y, function() return ns.db.display.showRealm end, function(v) ns.db.display.showRealm=v; self:RefreshUI() end)
    -- ★ 将原MPlus页面的全局选项移至此处
    y = self:Check(inner, L["标题下方显示全程摘要行（仅在副本中生效）"], y, function() return ns.db.mythicPlus.dualDisplay end, function(v) ns.db.mythicPlus.dualDisplay=v; self:RefreshUI() end)
    y = self:Check(inner, L["离开副本后自动生成副本全程段落（地下堡不适用)"], y, function() return ns.db.mythicPlus.enabled end, function(v) ns.db.mythicPlus.enabled=v end)
    inner:SetHeight(math.abs(y) + 20)
end



function Config:BuildLookPage()
    local inner = self.pages["look"].inner; local y = 0

    -- ── 全局尺寸 ───────────────────────────────────────────────
    y = self:H(inner, L["全局尺寸"], y)
    y = self:Slider(inner, L["窗口缩放 (Scale)"], y, 0.5, 2.0, 0.05,
        function() return ns.db.window.scale end,
        function(v) ns.db.window.scale = v; if ns.UI and ns.UI.frame then ns.UI.frame:SetScale(v) end end)
    y = self:Check(inner, L["锁定窗口位置"], y,
        function() return ns.db.window.locked end,
        function(v) ns.db.window.locked=v end)

    -- ── 颜色 ──────────────────────────────────────────────────
    y = y - 12; y = self:H(inner, L["界面颜色"], y)

    -- 主题色
    y = self:ColorSwatch(inner, L["标题栏/页签主题色"], y,
        function()
            local c = ns.db.window.themeColor or {0.08, 0.08, 0.12, 1}
            return c[1], c[2], c[3], c[4]
        end,
        function(r, g, b, a)
            ns.db.window.themeColor = {r, g, b, a}
            if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end
        end)

    -- 数据背景色
    y = self:ColorSwatch(inner, L["数据区背景色"], y,
        function()
            local c = ns.db.window.bgColor or {0.04, 0.04, 0.05, 0.90}
            return c[1], c[2], c[3], c[4]
        end,
        function(r, g, b, a)
            ns.db.window.bgColor = {r, g, b, a}
            if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end
        end)

    -- 总计区域背景色
    y = self:ColorSwatch(inner, L["总计区域背景色"], y,
        function()
            local c = ns.db.window.ovrBgColor or {0.02, 0.04, 0.08, 0.95}
            return c[1], c[2], c[3], c[4]
        end,
        function(r, g, b, a)
            ns.db.window.ovrBgColor = {r, g, b, a}
            if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end
        end)

    -- ── 名称颜色 ───────────────────────────────────────────────
    y = y - 12; y = self:H(inner, L["名称颜色"], y)
    local colorModes = {
        {l=L["职业颜色"], v="class"},
        {l=L["纯白"],     v="white"},
        {l=L["自定义"],   v="custom"},
    }
    y = self:Dropdown(inner, L["名称颜色模式"], y, colorModes,
        function() return ns.db.display.textColorMode or "class" end,
        function(v)
            ns.db.display.textColorMode = v
            self:RefreshUI()
        end)

    -- 自定义文字颜色（无透明度）
    y = self:ColorSwatchNoAlpha(inner, L["自定义名称颜色"], y,
        function()
            local c = ns.db.display.textColor or {1.0, 1.0, 1.0}
            return c[1], c[2], c[3]
        end,
        function(r, g, b)
            ns.db.display.textColor = {r, g, b}
            self:RefreshUI()
        end)

    -- ── 字体设置 ───────────────────────────────────────────────
    y = y - 12; y = self:H(inner, L["字体设置"], y)
    
    -- ★ 替换开始：使用系统自带的字体选项
    local chatFont = select(1, ChatFontNormal:GetFont())
    local fonts = { 
        {l=L["系统默认"], v=STANDARD_TEXT_FONT}, 
        {l=L["伤害数字"], v=DAMAGE_TEXT_FONT},
        {l=L["聊天框字体"], v=chatFont},
        {l=L["单位名称"], v=UNIT_NAME_FONT}
    }
    y = self:Dropdown(inner, L["全局字体"], y, fonts,
        function() return ns.db.display.font or STANDARD_TEXT_FONT end,
        function(v) ns.db.display.font=v; self:RefreshUI() end)
    -- ★ 替换结束
    y = self:Slider(inner, L["字体基础大小"], y, 8, 20, 1,
        function() return ns.db.display.fontSizeBase or 10 end,
        function(v) ns.db.display.fontSizeBase=v; self:RefreshUI() end)

    local outlines = { {l=L["无"], v=""}, {l=L["发光描边 (Outline)"], v="OUTLINE"}, {l=L["加粗描边"], v="THICKOUTLINE"} }
    y = self:Dropdown(inner, L["字体描边"], y, outlines,
        function() return ns.db.display.fontOutline or "OUTLINE" end,
        function(v) ns.db.display.fontOutline=v; self:RefreshUI() end)
    y = self:Check(inner, L["开启文字阴影"], y,
        function() return ns.db.display.fontShadow end,
        function(v) ns.db.display.fontShadow=v; self:RefreshUI() end)

    -- ── 数据条外观 ─────────────────────────────────────────────
    y = y - 12; y = self:H(inner, L["数据条外观"], y)
    y = self:Slider(inner, L["排版行高 (文字/图标区域)"], y, 10, 30, 1,
        function() return ns.db.display.barHeight end,
        function(v) ns.db.display.barHeight=v; self:RefreshUI() end)
    y = self:Slider(inner, L["颜色条实际粗细"], y, 1, 30, 1,
        function() return ns.db.display.barThickness or ns.db.display.barHeight or 19 end,
        function(v) ns.db.display.barThickness=v; self:RefreshUI() end)
    y = self:Slider(inner, L["颜色条垂直偏移 (从底向上)"], y, 0, 30, 1,
        function() return ns.db.display.barVOffset or 0 end,
        function(v) ns.db.display.barVOffset=v; self:RefreshUI() end)
    y = self:Slider(inner, L["数据条间距"], y, 0, 10, 1,
        function() return ns.db.display.barGap or 1 end,
        function(v) ns.db.display.barGap=v; self:RefreshUI() end)
    y = self:Slider(inner, L["数据条透明度"], y, 0.1, 1.0, 0.05,
        function() return ns.db.display.barAlpha or 0.85 end,
        function(v) ns.db.display.barAlpha=v; self:RefreshUI() end)

    local textures = {
        {l=L["极简纯色 (Minimal Flat)"], v="Interface\\Buttons\\WHITE8X8"},
        {l=L["暴雪默认 (Blizz Default)"], v="Interface\\TargetingFrame\\UI-StatusBar"},
        {l=L["平滑渐变 (Smooth)"], v="Interface\\RaidFrame\\Raid-Bar-Hp-Fill"}
    }
    y = self:Dropdown(inner, L["数据条材质"], y, textures,
        function() return ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8" end,
        function(v) ns.db.display.barTexture=v; self:RefreshUI() end)

    inner:SetHeight(math.abs(y) + 20)
end

function Config:BuildPerfPage()
    local inner = self.pages["perf"].inner; local y = 0
    y = self:H(inner, L["智能刷新"], y)
    y = self:Slider(inner, L["战斗中刷新间隔 (秒)"], y, 0.1, 1.0, 0.1,
        function() return ns.db.smartRefresh.combatInterval end,
        function(v) ns.db.smartRefresh.combatInterval=v end)
    y = self:Slider(inner, L["脱战刷新间隔 (秒)"], y, 0.5, 5.0, 0.5,
        function() return ns.db.smartRefresh.idleInterval end,
        function(v) ns.db.smartRefresh.idleInterval=v end)
    inner:SetHeight(math.abs(y) + 20)
end

-- ============================================================
-- 极简风控件渲染
-- ============================================================
function Config:H(p, text, y)
    local h = p:CreateFontString(nil, "OVERLAY")
    h:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    h:SetPoint("TOPLEFT", 0, y); h:SetTextColor(0, 0.8, 1); h:SetText(text)
    return y - 24
end

function Config:Desc(p, y, text)
    local d = p:CreateFontString(nil, "OVERLAY")
    d:SetFont(STANDARD_TEXT_FONT, 10, "")
    d:SetPoint("TOPLEFT", 4, y)
    d:SetWidth(PANEL_W - SIDEBAR_W - 40)
    d:SetJustifyH("LEFT")
    d:SetTextColor(0.5, 0.5, 0.5)
    d:SetText(text)
    
    local h = d:GetStringHeight()
    if h == 0 then h = ((select(2, text:gsub("\n","\n")) + 1) * 13 + 6) end
    return y - h - 12
end

function Config:Check(p, label, y, getter, setter, tooltipText)
    local btn = CreateFrame("Button", nil, p); btn:SetSize(20, 14); btn:SetPoint("TOPLEFT", 4, y)
    self:FillBg(btn, 0.1, 0.1, 0.15, 1); self:CreateBorder(btn, 0.3, 0.3, 0.4, 1)
    
    local fill = btn:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 3, -3); fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(0, 0.75, 1, 1); fill:SetShown(getter())
    
    local hl = btn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.1)
    
    local t = btn:CreateFontString(nil, "OVERLAY"); t:SetFont(STANDARD_TEXT_FONT, 11, ""); t:SetPoint("LEFT", btn, "RIGHT", 8, 0); t:SetTextColor(0.8, 0.8, 0.8); t:SetText(label)
    btn:SetScript("OnClick", function() local nxt = not getter(); fill:SetShown(nxt); setter(nxt) end)
    
    -- ★ 新增：如果传入了 tooltipText，则在文字右侧生成问号
    if tooltipText then
        local qm = CreateFrame("Frame", nil, p)
        qm:SetSize(14, 14)
        qm:SetPoint("LEFT", t, "RIGHT", 4, 0)
        qm:EnableMouse(true)
        
        local qt = qm:CreateFontString(nil, "OVERLAY")
        qt:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        qt:SetPoint("CENTER")
        qt:SetText("?")
        qt:SetTextColor(0, 0.75, 1) -- 问号颜色
        
        qm:SetScript("OnEnter", function(self)
            qt:SetTextColor(0.2, 0.85, 1) -- 悬停高亮
            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
            -- 最后一个参数 true 表示允许文字自动换行以自适应尺寸
            GameTooltip:SetText(tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        qm:SetScript("OnLeave", function()
            qt:SetTextColor(0, 0.75, 1)
            GameTooltip:Hide()
        end)
    end
    
    return y - 24
end

function Config:Radio(p, label, y, getter, setter)
    local btn = CreateFrame("Button", nil, p); btn:SetSize(300, 16); btn:SetPoint("TOPLEFT", 4, y)
    local box = btn:CreateTexture(nil, "BACKGROUND"); box:SetSize(14, 14); box:SetPoint("LEFT", 0, 0); box:SetColorTexture(0.1, 0.1, 0.15, 1)
    -- ★ 修复：单选框的边框同样垫底
    local border = btn:CreateTexture(nil, "BACKGROUND", nil, -8); border:SetPoint("TOPLEFT", box, "TOPLEFT", -1, 1); border:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 1, -1); border:SetColorTexture(0.3, 0.3, 0.4, 1)    
    local fill = btn:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3); fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3); fill:SetColorTexture(0, 0.75, 1, 1)
    
    -- 悬停效果绑定在整行上，提升手感
    local hl = btn:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", box, "TOPLEFT"); hl:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT"); hl:SetColorTexture(1, 1, 1, 0.1)
    
    local t = btn:CreateFontString(nil, "OVERLAY"); t:SetFont(STANDARD_TEXT_FONT, 11, ""); t:SetPoint("LEFT", box, "RIGHT", 8, 0); t:SetTextColor(0.8, 0.8, 0.8); t:SetText(label)
    
    local function upd() fill:SetShown(getter()) end; upd(); btn.update = upd
    if not self.radioBtns then self.radioBtns = {} end; table.insert(self.radioBtns, btn)
    btn:SetScript("OnClick", function() setter(); for _, b in ipairs(self.radioBtns) do b.update() end end); return y - 22
end

function Config:Slider(p, label, y, mn, mx, step, getter, setter, isPercent)
    local lt = p:CreateFontString(nil, "OVERLAY"); lt:SetFont(STANDARD_TEXT_FONT, 10, ""); lt:SetPoint("TOPLEFT", 6, y); lt:SetTextColor(0.7, 0.7, 0.7); lt:SetText(label)
    local vt = p:CreateFontString(nil, "OVERLAY"); vt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); vt:SetPoint("TOPRIGHT", p, "TOPRIGHT", -20, y); vt:SetTextColor(0, 0.75, 1)
    y = y - 16
    local s = CreateFrame("Slider", nil, p); s:SetSize(280, 12); s:SetPoint("TOPLEFT", 6, y); s:SetOrientation("HORIZONTAL")
    
    -- 滑轨底色
    local track = s:CreateTexture(nil, "BACKGROUND"); track:SetHeight(2); track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetColorTexture(0.2, 0.2, 0.25, 1)
    
    -- 现代 Web 风格：滑块左侧的高亮填充轨迹
    s:SetThumbTexture("Interface\\Buttons\\WHITE8X8"); local thumb = s:GetThumbTexture(); thumb:SetSize(10, 10); thumb:SetVertexColor(0, 0.75, 1, 1)
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(2); fill:SetPoint("LEFT", track, "LEFT"); fill:SetPoint("RIGHT", thumb, "CENTER"); fill:SetColorTexture(0, 0.75, 1, 1)
    
    -- 悬停交互：滑块变亮
    s:SetScript("OnEnter", function() thumb:SetVertexColor(0.2, 0.85, 1, 1); fill:SetColorTexture(0.2, 0.85, 1, 1) end)
    s:SetScript("OnLeave", function() thumb:SetVertexColor(0, 0.75, 1, 1); fill:SetColorTexture(0, 0.75, 1, 1) end)

    s:SetMinMaxValues(mn, mx); s:SetValueStep(step); s:SetObeyStepOnDrag(true); s:SetValue(getter())
    local function upd(v) if isPercent then vt:SetText(string.format("%.0f%%", v * 100)) else vt:SetText(step < 1 and string.format("%.2f", v) or string.format("%.0f", v)) end end
    upd(getter()); s:SetScript("OnValueChanged", function(_, v) setter(v); upd(v) end); return y - 26
end

function Config:Dropdown(p, label, y, opts, getter, setter)
    local lt = p:CreateFontString(nil, "OVERLAY"); lt:SetFont(STANDARD_TEXT_FONT, 10, ""); lt:SetPoint("TOPLEFT", 6, y); lt:SetTextColor(0.7, 0.7, 0.7); lt:SetText(label)
    y = y - 16
    local btn = CreateFrame("Button", nil, p); btn:SetSize(220, 20); btn:SetPoint("TOPLEFT", 6, y); self:FillBg(btn, 0.1, 0.1, 0.15, 1); self:CreateBorder(btn, 0.3, 0.3, 0.4, 1)
    
    local bt = btn:CreateFontString(nil, "OVERLAY"); bt:SetFont(STANDARD_TEXT_FONT, 11, ""); bt:SetPoint("LEFT", 6, 0); bt:SetTextColor(0.9, 0.9, 0.9)
    -- 使用几何倒三角替换原本的英文字母 "v"
    local arrow = btn:CreateFontString(nil, "OVERLAY"); arrow:SetFont(STANDARD_TEXT_FONT, 9, ""); arrow:SetPoint("RIGHT", -8, 0); arrow:SetTextColor(0.5, 0.5, 0.5); arrow:SetText("▼")
    
    local hlBtn = btn:CreateTexture(nil, "HIGHLIGHT"); hlBtn:SetAllPoints(); hlBtn:SetColorTexture(1, 1, 1, 0.05)
    
    local function refreshText() local cur = getter(); for _, o in ipairs(opts) do if o.v == cur then bt:SetText(o.l); return end end; bt:SetText(opts[1].l) end; refreshText()
    
    local blocker = CreateFrame("Button", nil, p); blocker:SetAllPoints(UIParent); blocker:SetFrameStrata("TOOLTIP"); blocker:SetFrameLevel(90); blocker:Hide(); blocker:SetScript("OnClick", function() blocker:Hide() end)
    local list = CreateFrame("Frame", nil, blocker); list:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2); list:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2); list:SetHeight(#opts * 20 + 4); list:SetFrameLevel(95); self:FillBg(list, 0.08, 0.08, 0.1, 1); self:CreateBorder(list, 0.3, 0.3, 0.4, 1)
    
    btn.items = {}
    -- 下拉列表内选项增加悬停高亮
    for i, o in ipairs(opts) do
        local item = CreateFrame("Button", nil, list); item:SetHeight(20); item:SetPoint("TOPLEFT", list, "TOPLEFT", 2, -((i-1)*20 + 2)); item:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -((i-1)*20 + 2))
        local hl = item:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(0, 0.75, 1, 0.2)
        local itx = item:CreateFontString(nil, "OVERLAY"); itx:SetFont(STANDARD_TEXT_FONT, 11, ""); itx:SetPoint("LEFT", 6, 0); itx:SetTextColor(0.8, 0.8, 0.8); itx:SetText(o.l)
        item:SetScript("OnClick", function() setter(o.v); bt:SetText(o.l); blocker:Hide() end)
        table.insert(btn.items, {btn = item, txt = itx})
    end

    -- ★ 新增：允许动态更新菜单内的文字选项
    btn.UpdateOpts = function(newOpts)
        opts = newOpts
        for i, o in ipairs(opts) do
            local row = btn.items[i]
            if row then
                row.txt:SetText(o.l)
                row.btn:SetScript("OnClick", function() setter(o.v); bt:SetText(o.l); blocker:Hide() end)
            end
        end
        refreshText()
    end
    
    btn:SetScript("OnClick", function() if blocker:IsShown() then blocker:Hide() else blocker:Show() end end); 
    
    -- ★ 修改：同时返回新的 y 坐标 和 按钮本体
    return y - 28, btn
end

-- ============================================================
-- 颜色色块按钮（带透明度）
-- ============================================================
-- getter() → r, g, b, a
-- setter(r, g, b, a)
function Config:ColorSwatch(p, label, y, getter, setter)
    -- 标签文字
    local lt = p:CreateFontString(nil, "OVERLAY")
    lt:SetFont(STANDARD_TEXT_FONT, 10, "")
    lt:SetPoint("TOPLEFT", 6, y)
    lt:SetTextColor(0.7, 0.7, 0.7)
    lt:SetText(label)

    -- 色块按钮
    local btn = CreateFrame("Button", nil, p)
    btn:SetSize(48, 16)
    btn:SetPoint("TOPLEFT", 6, y - 18)

    -- 棋盘格背景（象征透明度）
    self:AddCheckerboard(btn, 48, 16)

    -- 颜色预览层
    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetAllPoints()
    swatch:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- 细边框
    self:CreateBorder(btn, 0.4, 0.4, 0.5, 1)

    -- 悬停高亮
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)

    -- 初始化色块颜色
    local function UpdateSwatch()
        local r, g, b, a = getter()
        swatch:SetVertexColor(r, g, b, a)
    end
    UpdateSwatch()
    if not self.colorSwatches then self.colorSwatches = {} end
    table.insert(self.colorSwatches, UpdateSwatch)

    btn:SetScript("OnClick", function()
        local r, g, b, a = getter()
        OpenColorPicker(r, g, b, a,
            function(nr, ng, nb, na)
                setter(nr, ng, nb, na)
                swatch:SetVertexColor(nr, ng, nb, na)
            end,
            function(pr, pg, pb, pa)
                setter(pr, pg, pb, pa)
                swatch:SetVertexColor(pr, pg, pb, pa)
            end
        )
    end)

    return y - 42
end

-- ============================================================
-- 颜色色块按钮（不带透明度）
-- ============================================================
-- getter() → r, g, b
-- setter(r, g, b)
function Config:ColorSwatchNoAlpha(p, label, y, getter, setter)
    local lt = p:CreateFontString(nil, "OVERLAY")
    lt:SetFont(STANDARD_TEXT_FONT, 10, "")
    lt:SetPoint("TOPLEFT", 6, y)
    lt:SetTextColor(0.7, 0.7, 0.7)
    lt:SetText(label)

    local btn = CreateFrame("Button", nil, p)
    btn:SetSize(48, 16)
    btn:SetPoint("TOPLEFT", 6, y - 18)

    self:AddCheckerboard(btn, 48, 16)

    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetAllPoints()
    swatch:SetTexture("Interface\\Buttons\\WHITE8X8")

    self:CreateBorder(btn, 0.4, 0.4, 0.5, 1)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)

    local function UpdateSwatch()
        local r, g, b = getter()
        swatch:SetVertexColor(r, g, b, 1)
    end
    UpdateSwatch()
    if not self.colorSwatches then self.colorSwatches = {} end
    table.insert(self.colorSwatches, UpdateSwatch)

    btn:SetScript("OnClick", function()
        local r, g, b = getter()
        -- 无透明度版本：hasOpacity = false
        ColorPickerFrame:SetupColorPickerAndShow({
            r          = r,
            g          = g,
            b          = b,
            hasOpacity = false,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                setter(nr, ng, nb)
                swatch:SetVertexColor(nr, ng, nb, 1)
            end,
            cancelFunc = function()
                setter(r, g, b)
                swatch:SetVertexColor(r, g, b, 1)
            end,
        })
    end)

    return y - 42
end

-- ============================================================

function Config:RefreshUI() 

    
    -- 刷新所有已注册的颜色方块显示
    if self.colorSwatches then
        for _, updateFn in ipairs(self.colorSwatches) do updateFn() end
    end
    
    if ns.UI and ns.UI.frame and ns.UI.frame:IsShown() then ns.UI:Layout() end
    -- 预览窗口同步刷新
    if self._previewFrame and self._previewFrame:IsShown() then
        self:RefreshPreviewTheme()
        self:UpdatePreviewScene(self._previewSceneId or "mplus")
    end
end

function Config:BuildProfilesPage()
    -- 只建容器，内容由 RefreshProfilesPage 动态填充
    local inner = self.pages["profiles"].inner
    self._profileInner = inner
end

function Config:RefreshProfilesPage()
    local inner = self._profileInner
    if not inner then return end

    for _, child in ipairs({inner:GetChildren()}) do child:Hide() end
    for _, region in ipairs({inner:GetRegions()}) do region:Hide() end

    local y = 0
    local curName = LDCombatStatsDB.activeProfile or "默认"
    local displayCurName = (curName == "默认") and L["默认"] or curName
    y = self:H(inner, L["当前配置"] .. ": " .. displayCurName, y)

    -- 创建新配置 UI (继承主面板极简风)
    local input = CreateFrame("EditBox", nil, inner)
    input:SetSize(180, 20); input:SetPoint("TOPLEFT", 6, y)
    input:SetAutoFocus(false); input:SetFontObject(ChatFontNormal)
    self:FillBg(input, 0.1, 0.1, 0.15, 1); self:CreateBorder(input, 0.3, 0.3, 0.4, 1)
    input:SetTextInsets(5, 5, 0, 0)

    local createBtn = CreateFrame("Button", nil, inner)
    createBtn:SetSize(80, 20); createBtn:SetPoint("LEFT", input, "RIGHT", 10, 0)
    self:FillBg(createBtn, 0.05, 0.20, 0.35, 1); self:CreateBorder(createBtn, 0.1, 0.45, 0.75, 1)
    local ct = createBtn:CreateFontString(nil, "OVERLAY")
    ct:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); ct:SetPoint("CENTER"); ct:SetText(L["创建新配置"]); ct:SetTextColor(0.4, 0.85, 1)
    createBtn:SetScript("OnEnter", function() ct:SetTextColor(1, 1, 1) end)
    createBtn:SetScript("OnLeave", function() ct:SetTextColor(0.4, 0.85, 1) end)
    createBtn:SetScript("OnClick", function()
        local txt = input:GetText():trim()
        if txt ~= "" and not LDCombatStatsGlobal.profiles[txt] then
            ns:CreateProfile(txt)
            self:RefreshProfilesPage()
        else
            print(L["配置名称不能为空或已存在"])
        end
    end)
    
    y = y - 35
    y = self:H(inner, L["已存配置"], y)

    for pName, _ in pairs(LDCombatStatsGlobal.profiles) do
        local isSelf = (pName == curName)
        local displayName = (pName == "默认") and L["默认"] or pName
        local txt = inner:CreateFontString(nil, "OVERLAY")
        txt:SetFont(STANDARD_TEXT_FONT, 11, isSelf and "OUTLINE" or "")
        txt:SetPoint("TOPLEFT", 6, y)
        txt:SetTextColor(isSelf and 0.5 or 0.85, isSelf and 0.8 or 0.85, isSelf and 1.0 or 0.85)
        txt:SetText(displayName .. (isSelf and (" |cff888888["..L["当前"].."]|r") or ""))
        
        local lastBtn = nil

        -- 1. “应用”按钮：只有【非当前配置】才显示
        if not isSelf then
            local applyBtn = CreateFrame("Button", nil, inner)
            applyBtn:SetSize(50, 18); applyBtn:SetPoint("TOPLEFT", 180, y)
            self:FillBg(applyBtn, 0.05, 0.18, 0.30, 1); self:CreateBorder(applyBtn, 0.1, 0.4, 0.7, 1)
            local at = applyBtn:CreateFontString(nil, "OVERLAY")
            at:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); at:SetPoint("CENTER"); at:SetText(L["应用"]); at:SetTextColor(0.4, 0.85, 1)
            applyBtn:SetScript("OnEnter", function() at:SetTextColor(1, 1, 1) end)
            applyBtn:SetScript("OnLeave", function() at:SetTextColor(0.4, 0.85, 1) end)
            applyBtn:SetScript("OnClick", function() ns:SwitchProfile(pName); self:RefreshProfilesPage() end)
            lastBtn = applyBtn
        end

        -- 只要不是“默认”配置，就可以操作（改名/删除）
        if pName ~= "默认" then
            -- 2. “改名”按钮：【当前配置】和【非当前配置】都显示
            local renBtn = CreateFrame("Button", nil, inner)
            renBtn:SetSize(50, 18)
            if lastBtn then
                renBtn:SetPoint("LEFT", lastBtn, "RIGHT", 8, 0) -- 跟着上一个按钮
            else
                renBtn:SetPoint("TOPLEFT", 180, y) -- 当前配置没有“应用”按钮，所以它排在最前面
            end
            self:FillBg(renBtn, 0.2, 0.2, 0.25, 1); self:CreateBorder(renBtn, 0.4, 0.4, 0.5, 1)
            local rt = renBtn:CreateFontString(nil, "OVERLAY")
            rt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); rt:SetPoint("CENTER"); rt:SetText(L["改名"]); rt:SetTextColor(0.8, 0.8, 0.8)
            renBtn:SetScript("OnEnter", function() rt:SetTextColor(1, 1, 1) end)
            renBtn:SetScript("OnLeave", function() rt:SetTextColor(0.8, 0.8, 0.8) end)
            renBtn:SetScript("OnClick", function()
                -- 每次呼出前，动态赋予最新的翻译文本
                StaticPopupDialogs["LDCS_RENAME_PROFILE"].text = L["输入新的配置名称:"]
                StaticPopupDialogs["LDCS_RENAME_PROFILE"].button1 = L["确定"]
                StaticPopupDialogs["LDCS_RENAME_PROFILE"].button2 = L["取消"]

                local dialog = StaticPopup_Show("LDCS_RENAME_PROFILE")
                if dialog then
                    dialog.data = pName
                    local eb = dialog.EditBox or dialog.editBox or _G[dialog:GetName().."EditBox"]
                    if eb then
                        eb:SetText(pName)
                        eb:HighlightText() 
                    end
                end
            end)
            lastBtn = renBtn

            -- 3. “删除”按钮：只有【非当前配置】才显示（防止玩家删掉正在用的配置）
            if not isSelf then
                local delBtn = CreateFrame("Button", nil, inner)
                delBtn:SetSize(50, 18); delBtn:SetPoint("LEFT", lastBtn, "RIGHT", 8, 0)
                self:FillBg(delBtn, 0.3, 0.05, 0.05, 1); self:CreateBorder(delBtn, 0.7, 0.1, 0.1, 1)
                local dt = delBtn:CreateFontString(nil, "OVERLAY")
                dt:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE"); dt:SetPoint("CENTER"); dt:SetText(L["删除"]); dt:SetTextColor(1, 0.4, 0.4)
                delBtn:SetScript("OnEnter", function() dt:SetTextColor(1, 1, 1) end)
                delBtn:SetScript("OnLeave", function() dt:SetTextColor(1, 0.4, 0.4) end)
                delBtn:SetScript("OnClick", function() 
                    -- 每次呼出前，动态赋予最新的翻译文本
                    StaticPopupDialogs["LDCS_CONFIRM_DELETE_PROFILE"].text = L["确定要删除配置 '%s' 吗？"]
                    StaticPopupDialogs["LDCS_CONFIRM_DELETE_PROFILE"].button1 = L["确定"]
                    StaticPopupDialogs["LDCS_CONFIRM_DELETE_PROFILE"].button2 = L["取消"]

                    local dialog = StaticPopup_Show("LDCS_CONFIRM_DELETE_PROFILE", pName)
                    if dialog then dialog.data = pName end
                end)
            end
        end

        y = y - 26
    end

    inner:SetHeight(math.abs(y) + 20)
end

-- ============================================================
-- 预览窗口
-- ============================================================
function Config:TogglePreview()
    if self._previewFrame and self._previewFrame:IsShown() then
        self:ClosePreview()
    else
        self:OpenPreview()
    end
end

function Config:ClosePreview()
    if self._previewFrame then self._previewFrame:Hide() end
    if self._previewBtnT  then self._previewBtnT:SetText(L["预览"]) end
end

function Config:OpenPreview()
    self:BuildPreviewWindow()
    self._previewFrame:Show()
    if self._previewBtnT then self._previewBtnT:SetText(L["取消预览"]) end
    self:UpdatePreviewScene(self._previewSceneId or "mplus")
end

-- ============================================================
-- 预览系统 — 直接使用真实 ns.UI，只注入假数据
-- ============================================================

-- 构建场景切换条（只建一次，轻量）
-- ============================================================
-- 构建场景切换条（独立悬浮窗版本）
-- ============================================================
function Config:BuildSceneSwitcher()
    if self._pvSwitcher then return end

    -- 创建独立的悬浮窗口，层级设为 DIALOG，确保在最上层
    local sw = CreateFrame("Frame", "LDStatsPreviewSwitcher", UIParent, "BackdropTemplate")
    sw:SetSize(320, 36)
    sw:SetFrameStrata("DIALOG")
    sw:SetFrameLevel(110)
    
    -- 应用与设置主面板完全一致的极简底色
    sw:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile=nil, edgeSize=0 })
    sw:SetBackdropColor(0.05, 0.05, 0.06, 0.98)
    self:CreateBorder(sw, 0.15, 0.15, 0.2, 1) -- 加上细边框增加精致感
    
    sw:Hide()
    self._pvSwitcher = sw

    -- 左侧说明文字
    local hint = sw:CreateFontString(nil, "OVERLAY")
    hint:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    hint:SetPoint("LEFT", 14, 0)
    hint:SetText(L["|cff00ccff预览场景:|r"])

    -- 按钮布局配置
    local btnW  = 76
    local btnGap = 6
    local rightOffset = -12

    self._pvSceneBtns = {}
    for i = #PREVIEW_SCENES, 1, -1 do
        local sc  = PREVIEW_SCENES[i]
        local btn = CreateFrame("Button", nil, sw)
        btn:SetSize(btnW, 22)
        btn:SetPoint("RIGHT", sw, "RIGHT", rightOffset - (btnW + btnGap) * (#PREVIEW_SCENES - i), 0)

        -- 按钮底色和边框（与设置里的 Dropdown 风格一致）
        self:FillBg(btn, 0.1, 0.1, 0.15, 1)
        self:CreateBorder(btn, 0.3, 0.3, 0.4, 1)

        local bt = btn:CreateFontString(nil, "OVERLAY")
        bt:SetFont(STANDARD_TEXT_FONT, 10, "")
        bt:SetPoint("CENTER")
        bt:SetText(L[sc.labelKey])
        bt:SetTextColor(0.6, 0.6, 0.6)
        
        btn._label   = bt
        btn._sceneId = sc.id

        btn:SetScript("OnClick", function()
            self:ApplyPreviewScene(sc.id)
        end)
        btn:SetScript("OnEnter", function()
            if self._previewSceneId ~= sc.id then bt:SetTextColor(1, 1, 1) end
        end)
        btn:SetScript("OnLeave", function()
            if self._previewSceneId ~= sc.id then bt:SetTextColor(0.6, 0.6, 0.6) end
        end)

        self._pvSceneBtns[i]     = btn
        self._pvSceneBtns[sc.id] = btn
    end
end

function Config:TogglePreview()
    if self._previewActive then
        self:ClosePreview()
    else
        self:OpenPreview()
    end
end

function Config:OpenPreview()
    if not ns.UI or not ns.Segments then return end
    ns.UI:EnsureCreated()

    -- 保存真实状态
    self._pvSave = {
        inCombat     = ns.state.inCombat,
        isInInstance = ns.state.isInInstance,
        inMythicPlus = ns.state.inMythicPlus,
        viewIndex    = ns.Segments.viewIndex,
        current      = ns.Segments.current,
        overall      = ns.Segments.overall,
        history      = ns.Segments.history,
        locked       = ns.Segments._locked,
        uiPoint      = ns.db.window.point,
        uiRelPoint   = ns.db.window.relPoint,
        uiX          = ns.db.window.x,
        uiY          = ns.db.window.y,
    }

    self._pvRefreshBlocked = true
    ns.Segments._locked    = false
    self._previewActive    = true
    self._previewSceneId   = "mplus"

    if self._previewBtnT then self._previewBtnT:SetText(L["取消预览"]) end

    -- 预览窗口（纯粹的真实 UI）对齐到配置面板右侧
    ns.UI.frame:ClearAllPoints()
    ns.UI.frame:SetPoint("TOPLEFT", self.panel, "TOPRIGHT", 8, 0)
    ns.UI.frame:Show()

    -- ★ 显示独立场景切换窗，并吸附在预览窗口的正上方间距 8px 处
    if self._pvSwitcher then 
        self._pvSwitcher:ClearAllPoints()
        self._pvSwitcher:SetPoint("BOTTOM", ns.UI.frame, "TOP", 0, 8)
        self._pvSwitcher:Show() 
    end

    self:ApplyPreviewScene("mplus")
end

function Config:ClosePreview()
    if not self._pvSave then return end

    ns.state.inCombat     = self._pvSave.inCombat
    ns.state.isInInstance = self._pvSave.isInInstance
    ns.state.inMythicPlus = self._pvSave.inMythicPlus
    ns.Segments.viewIndex = self._pvSave.viewIndex
    ns.Segments.current   = self._pvSave.current
    ns.Segments.overall   = self._pvSave.overall
    ns.Segments.history   = self._pvSave.history
    ns.Segments._locked   = self._pvSave.locked

    ns.UI.frame:ClearAllPoints()
    ns.UI.frame:SetPoint(
        self._pvSave.uiPoint, UIParent, self._pvSave.uiRelPoint,
        self._pvSave.uiX, self._pvSave.uiY)

    -- ★ 隐藏独立场景切换窗
    if self._pvSwitcher then self._pvSwitcher:Hide() end

    self._pvSave           = nil
    self._previewActive    = false
    self._pvRefreshBlocked = false

    if self._previewBtnT then self._previewBtnT:SetText(L["预览"]) end

    if ns.Analysis then ns.Analysis:InvalidateCache() end
    ns.UI:Layout()
end



-- 切换场景：注入假数据 → 刷新真实 UI
function Config:ApplyPreviewScene(sceneId)
    if not self._previewActive then return end
    self._previewSceneId = sceneId

    local scene
    for _, sc in ipairs(PREVIEW_SCENES) do
        if sc.id == sceneId then scene = sc; break end
    end
    if not scene then return end

    -- 场景按钮高亮
    for id, btn in pairs(self._pvSceneBtns) do
        if type(id) == "string" then
            local active = (id == sceneId)
            btn._label:SetTextColor(active and 0 or 0.6, active and 0.75 or 0.6, active and 1 or 0.6)
        end
    end

    -- 注入假的全局状态
    ns.state.inCombat     = false
    ns.state.isInInstance = (sceneId ~= "outdoor")
    ns.state.inMythicPlus = (sceneId == "mplus")

    -- 构造假段落
    local mockCurrent = self:BuildMockSegment(false)   -- 当前段（普通时长）
    local mockOverall = self:BuildMockSegment(true)    -- 全程（更长时长）

    ns.Segments.current   = nil
    ns.Segments.history   = { mockCurrent }
    ns.Segments.viewIndex = 1
    ns.Segments.overall   = mockOverall

    if ns.Analysis then ns.Analysis:InvalidateCache() end

    -- 用真实 UI 渲染，什么参数都不改，和正常脱战后完全一样
    ns.UI:Layout()
end

-- 构造一个完全符合 Analysis:GetSorted 期望的假段落
function Config:BuildMockSegment(isOverall)
    local seg = ns.Segments:NewSegment("history", isOverall and L["模拟全程"] or L["模拟战斗"])
    seg.isActive  = false
    seg.duration  = isOverall and 330 or 225   -- 5:30 / 3:45

    local totalDmg, totalHeal, totalTaken = 0, 0, 0

    for i, mock in ipairs(PREVIEW_MOCK) do
        local guid = "pvGUID_" .. i
        local pd   = ns.Segments:NewPlayerData(guid, mock.name, mock.class)
        pd.damage         = isOverall and math.floor(mock.damage  * 1.45) or mock.damage
        pd.healing        = isOverall and math.floor(mock.healing * 1.45) or mock.healing
        pd.damageTaken    = mock.damageTaken
        pd.deaths         = mock.deaths
        pd.interrupts     = mock.interrupts
        pd.dispels        = mock.dispels
        pd.damagePerSec   = mock.dps
        pd.healingPerSec  = mock.hps
        pd.damageTakenPerSec = 0
        pd.pets           = {}
        seg.players[guid] = pd
        totalDmg   = totalDmg   + pd.damage
        totalHeal  = totalHeal  + pd.healing
        totalTaken = totalTaken + pd.damageTaken
    end

    seg.totalDamage      = totalDmg
    seg.totalHealing     = totalHeal
    seg.totalDamageTaken = totalTaken

    -- 简单死亡日志，供死亡模式展示
    seg.deathLog = {
        { playerName="Ironhide", playerGUID="pvGUID_2", playerClass="WARRIOR",
          isSelf=false, killingAbility="Shadow Bolt", killerName="Big Boss",
          events={}, totalDamageTaken=450000, totalHealingReceived=0,
          timeSpan=3.2, timestamp=time(), gameTime=GetTime() },
        { playerName="Frostmantle", playerGUID="pvGUID_7", playerClass="DEATHKNIGHT",
          isSelf=false, killingAbility="Cleave", killerName="Big Boss",
          events={}, totalDamageTaken=380000, totalHealingReceived=0,
          timeSpan=2.1, timestamp=time(), gameTime=GetTime() },
    }

    return seg
end

