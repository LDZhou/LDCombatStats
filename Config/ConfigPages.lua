--[[
    Light Damage - ConfigPages.lua
    设置页面：Layout, Data, Look, Perf
    注意：所有方法挂载到 ns.Config 上（ConfigCore.lua 已创建）
]]
local addonName, ns = ...
local L = ns.L
local Config = ns.Config

local PANEL_W   = 500
local SIDEBAR_W = 110

-- ============================================================
-- Layout 页
-- ============================================================
function Config:BuildLayoutPage()
    local inner = self.pages["layout"].inner


    local sec1 = CreateFrame("Frame", nil, inner); sec1:SetWidth(inner:GetWidth()); local y1 = 0
    y1 = self:H(sec1, L["界面语言"], y1)
    y1 = self:Dropdown(sec1, L["语言 (需要重载UI生效)"], y1, { {l=L["跟随客户端"], v="auto"}, {l="简体中文", v="zhCN"}, {l="繁体中文", v="zhTW"}, {l="English", v="enUS"}, {l="Русский", v="ruRU"} }, function() return ns.db.display.language or "auto" end, function(v) ns.db.display.language = v; ReloadUI() end)
    sec1:SetHeight(math.abs(y1)); self.laySec1 = sec1

    local posesLR = { {l=L["左侧"], v=1}, {l=L["右侧"], v=2} }; local posesTB = { {l=L["上方"], v=1}, {l=L["下方"], v=2} }
    local dirs = { {l=L["左右划分"], v="LR"}, {l=L["上下划分"], v="TB"} }
    local allModes = { {l=L["伤害"], v="damage"}, {l=L["治疗"], v="healing"}, {l=L["承伤"], v="damageTaken"}, {l=L["死亡"], v="deaths"}, {l=L["打断"], v="interrupts"}, {l=L["驱散"], v="dispels"} }

    local sec2 = CreateFrame("Frame", nil, inner); sec2:SetWidth(inner:GetWidth()); local y2 = 0
    y2 = self:H(sec2, L["当前与总计窗口"], y2)
    y2 = self:Check(sec2, L["同时显示当前与总计数据"], y2, function() return ns.db.split.showOverall end, function(v) ns.db.split.showOverall = v; self:RefreshUI(); self:UpdateLayoutVisibility() end, L["OVERALL_DATA_TOOLTIP"])
    local sec2_sub = CreateFrame("Frame", nil, sec2); sec2_sub:SetWidth(inner:GetWidth() - 16); sec2_sub:SetPoint("TOPLEFT", sec2, "TOPLEFT", 16, y2); local y2s = 0
    y2s = self:Desc(sec2_sub, y2s, L["生效场景："])
    y2s = self:Check(sec2_sub, L["大秘境"], y2s, function() return ns.db.split.overallShowMPlus end, function(v) ns.db.split.overallShowMPlus=v; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s = self:Check(sec2_sub, L["团队副本"], y2s, function() return ns.db.split.overallShowRaid end, function(v) ns.db.split.overallShowRaid=v; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s = self:Check(sec2_sub, L["其他副本 (含地下堡/战场/竞技场)"], y2s, function() return ns.db.split.overallShowDungeon end, function(v) ns.db.split.overallShowDungeon=v; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s = self:Check(sec2_sub, L["非副本 (开放世界)"], y2s, function() return ns.db.split.overallShowOutdoor end, function(v) ns.db.split.overallShowOutdoor=v; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s = y2s - 8
    local curPosBtn
    y2s, self.ovrDirBtn = self:Dropdown(sec2_sub, L["当前/总计划分方向"], y2s, dirs, function() return ns.db.split.overallDir or "LR" end, function(v) ns.db.split.overallDir = v; ns.db.split.splitDir = (v == "LR") and "TB" or "LR"; if curPosBtn then curPosBtn.UpdateOpts(v == "TB" and posesTB or posesLR) end; if self.priPosBtn then self.priPosBtn.UpdateOpts(ns.db.split.splitDir == "TB" and posesTB or posesLR) end; if self.splitDirBtn then self.splitDirBtn.UpdateOpts(dirs) end; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y2s, curPosBtn = self:Dropdown(sec2_sub, L["当前数据位置"], y2s, (ns.db.split.overallDir == "TB") and posesTB or posesLR, function() return ns.db.split.currentPos or 1 end, function(v) ns.db.split.currentPos = v; self:RefreshUI() end)
    sec2_sub:SetHeight(math.abs(y2s)); self.laySec2Sub = sec2_sub; self.laySec2 = sec2

    local sec3 = CreateFrame("Frame", nil, inner); sec3:SetWidth(inner:GetWidth()); local y3 = 0
    y3 = self:H(sec3, L["双数据显示"], y3)
    y3 = self:Check(sec3, L["开启双数据显示"], y3, function() return ns.db.split.enabled end, function(v) ns.db.split.enabled = v; if v then if ns.db.display.mode ~= "split" then ns.db.display.mode = "split" end else if ns.db.display.mode == "split" then ns.db.display.mode = ns.db.split.primaryMode or "damage" end end; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    local sec3_sub = CreateFrame("Frame", nil, sec3); sec3_sub:SetWidth(inner:GetWidth() - 16); sec3_sub:SetPoint("TOPLEFT", sec3, "TOPLEFT", 16, y3); local y3s = 0
    y3s = self:Desc(sec3_sub, y3s, L["生效场景："])
    y3s = self:Check(sec3_sub, L["大秘境"], y3s, function() return ns.db.split.splitShowMPlus end, function(v) ns.db.split.splitShowMPlus=v; if v and ns.db.split.enabled and ns.state.instanceCategory == "mplus" then ns.db.display.mode = "split" end; self:RefreshUI() end)
    y3s = self:Check(sec3_sub, L["团队副本"], y3s, function() return ns.db.split.splitShowRaid end, function(v) ns.db.split.splitShowRaid=v; if v and ns.db.split.enabled and ns.state.instanceCategory == "raid" then ns.db.display.mode = "split" end; self:RefreshUI() end)
    y3s = self:Check(sec3_sub, L["其他副本 (含地下堡/战场/竞技场)"], y3s, function() return ns.db.split.splitShowDungeon end, function(v) ns.db.split.splitShowDungeon=v; if v and ns.db.split.enabled and ns.state.instanceCategory == "dungeon" then ns.db.display.mode = "split" end; self:RefreshUI() end)
    y3s = self:Check(sec3_sub, L["非副本 (开放世界)"], y3s, function() return ns.db.split.splitShowOutdoor end, function(v) ns.db.split.splitShowOutdoor=v; if v and ns.db.split.enabled and ns.state.instanceCategory == "outdoor" then ns.db.display.mode = "split" end; self:RefreshUI() end)
    y3s = y3s - 8
    y3s, self.splitDirBtn = self:Dropdown(sec3_sub, L["双数据划分方向"], y3s, dirs, function() return ns.db.split.splitDir or "TB" end, function(v) ns.db.split.splitDir = v; ns.db.split.overallDir = (v == "LR") and "TB" or "LR"; if self.priPosBtn then self.priPosBtn.UpdateOpts(v == "TB" and posesTB or posesLR) end; if curPosBtn then curPosBtn.UpdateOpts(ns.db.split.overallDir == "TB" and posesTB or posesLR) end; if self.ovrDirBtn then self.ovrDirBtn.UpdateOpts(dirs) end; self:RefreshUI(); self:UpdateLayoutVisibility() end)
    y3s, self.priPosBtn = self:Dropdown(sec3_sub, L["主数据位置"], y3s, (ns.db.split.splitDir == "TB") and posesTB or posesLR, function() return ns.db.split.primaryPos or 1 end, function(v) ns.db.split.primaryPos = v; self:RefreshUI() end)
    y3s = self:Dropdown(sec3_sub, L["主数据内容"], y3s, allModes, function() return ns.db.split.primaryMode end, function(v) ns.db.split.primaryMode=v; self:RefreshUI() end)
    y3s = self:Dropdown(sec3_sub, L["副数据内容"], y3s, allModes, function() return ns.db.split.secondaryMode end, function(v) ns.db.split.secondaryMode=v; self:RefreshUI() end)
    sec3_sub:SetHeight(math.abs(y3s)); self.laySec3Sub = sec3_sub; self.laySec3 = sec3

    local sec4 = CreateFrame("Frame", nil, inner); sec4:SetWidth(inner:GetWidth()); local y4 = 0
    y4 = self:H(sec4, L["自适应布局比例"], y4)
    y4 = self:Slider(sec4, L["上下分栏比例"], y4, 0.2, 0.8, 0.01, function() return ns.db.split.tbRatio or 0.5 end, function(v) ns.db.split.tbRatio = v; self:RefreshUI() end, true)
    y4 = self:Slider(sec4, L["左右分栏比例"], y4, 0.2, 0.8, 0.01, function() return ns.db.split.lrRatio or 0.5 end, function(v) ns.db.split.lrRatio = v; self:RefreshUI() end, true)
    sec4:SetHeight(math.abs(y4)); self.laySec4 = sec4

    local sec5 = CreateFrame("Frame", nil, inner); sec5:SetWidth(inner:GetWidth()); local y5 = 0
    y5 = self:H(sec5, L["按场景记忆窗口大小"], y5)
    y5 = self:Check(sec5, L["按场景记忆窗口大小"], y5,
        function() return ns.db.window.rememberSceneSize end,
        function(v)
            ns.db.window.rememberSceneSize = v
            if v then
                local cat = ns.state.instanceCategory or "outdoor"
                if not ns.db.window.sceneSizes then ns.db.window.sceneSizes = {} end
                if not ns.db.window.sceneSizes[cat] then
                    ns.db.window.sceneSizes[cat] = { width = ns.db.window.width, height = ns.db.window.height }
                end
            end
            self:UpdateLayoutVisibility()
        end)
    y5 = self:Desc(sec5, y5, L["SCENE_SIZE_DESC"])
    self._laySec5BaseH = math.abs(y5)

    local sec5_sub = CreateFrame("Frame", nil, sec5); sec5_sub:SetWidth(inner:GetWidth() - 16); sec5_sub:SetPoint("TOPLEFT", sec5, "TOPLEFT", 16, y5); local y5s = 0
    local anchorOpts = {
        {l=L["左上"], v="TOPLEFT"}, {l=L["上方"], v="TOP"}, {l=L["右上"], v="TOPRIGHT"},
        {l=L["左侧"], v="LEFT"}, {l=L["中心"], v="CENTER"}, {l=L["右侧"], v="RIGHT"},
        {l=L["左下"], v="BOTTOMLEFT"}, {l=L["下方"], v="BOTTOM"}, {l=L["右下"], v="BOTTOMRIGHT"},
    }
    y5s = self:Dropdown(sec5_sub, L["缩放锚点"], y5s, anchorOpts,
        function() return ns.db.window.sceneAnchor or "TOPLEFT" end,
        function(v) ns.db.window.sceneAnchor = v end)
    y5s = self:Desc(sec5_sub, y5s, L["SCENE_ANCHOR_DESC"])
    sec5_sub:SetHeight(math.abs(y5s)); self.laySec5Sub = sec5_sub; self.laySec5 = sec5

    self:UpdateLayoutVisibility()
end

function Config:UpdateLayoutVisibility()
    local inner = self.pages["layout"].inner
    if ns.db.split.showOverall then self.laySec2Sub:Show(); self.laySec2:SetHeight(48 + self.laySec2Sub:GetHeight()) else self.laySec2Sub:Hide(); self.laySec2:SetHeight(48) end
    if ns.db.split.enabled then self.laySec3Sub:Show(); self.laySec3:SetHeight(48 + self.laySec3Sub:GetHeight()) else self.laySec3Sub:Hide(); self.laySec3:SetHeight(48) end
    self.laySec1:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
    self.laySec2:SetPoint("TOPLEFT", self.laySec1, "BOTTOMLEFT", 0, -12)
    self.laySec3:SetPoint("TOPLEFT", self.laySec2, "BOTTOMLEFT", 0, -12)
    self.laySec4:SetPoint("TOPLEFT", self.laySec3, "BOTTOMLEFT", 0, -12)

    local sec5BaseH = self._laySec5BaseH or 48
    if ns.db.window.rememberSceneSize then self.laySec5Sub:Show(); self.laySec5:SetHeight(sec5BaseH + self.laySec5Sub:GetHeight()) else self.laySec5Sub:Hide(); self.laySec5:SetHeight(sec5BaseH) end
    self.laySec5:SetPoint("TOPLEFT", self.laySec4, "BOTTOMLEFT", 0, -12)

    local totalH = self.laySec1:GetHeight() + self.laySec2:GetHeight() + self.laySec3:GetHeight() + self.laySec4:GetHeight() + self.laySec5:GetHeight() + 60
    inner:SetHeight(totalH); self:UpdatePageScroll("layout")
end

-- ============================================================
-- Data 页
-- ============================================================
function Config:BuildDataPage()
    local inner = self.pages["data"].inner; local y = 0
    y = self:H(inner, L["数据显示格式"], y)
    y = self:Check(inner, L["同时显示伤害总量和DPS"], y, function() return ns.db.display.showPerSecond end, function(v) ns.db.display.showPerSecond=v; self:RefreshUI() end)
    y = self:Check(inner, L["显示数据贡献百分比 (脱战后生效)"], y, function() return ns.db.display.showPercent end, function(v) ns.db.display.showPercent=v; self:RefreshUI() end)
    y = self:Check(inner, L["显示排名序号"], y, function() return ns.db.display.showRank end, function(v) ns.db.display.showRank=v; self:RefreshUI() end)
    y = self:Check(inner, L["在最左侧显示专精图标"], y, function() return ns.db.display.showSpecIcon end, function(v) ns.db.display.showSpecIcon=v; self:RefreshUI() end)
    y = self:Check(inner, L["显示玩家服务器"], y, function() return ns.db.display.showRealm end, function(v) ns.db.display.showRealm=v; self:RefreshUI() end)
    y = self:Check(inner, L["在排名中永远显示自己"], y, function() return ns.db.display.alwaysShowSelf end, function(v) ns.db.display.alwaysShowSelf=v; self:RefreshUI() end)
    y = self:Check(inner, L["标题下方显示全程摘要行（仅在副本中生效）"], y, function() return ns.db.mythicPlus.dualDisplay end, function(v) ns.db.mythicPlus.dualDisplay=v; self:RefreshUI() end)
    self._dataTopY = y

    -- Section: 生成全程段落
    local secGen = CreateFrame("Frame", nil, inner); secGen:SetWidth(inner:GetWidth()); local yGen = 0
    yGen = self:Check(secGen, L["离开副本后自动生成副本全程段落"], yGen,
        function() return ns.db.mythicPlus.enabled end,
        function(v) ns.db.mythicPlus.enabled=v; self:UpdateDataVisibility() end)
    local dataGenSub = CreateFrame("Frame", nil, secGen); dataGenSub:SetWidth(inner:GetWidth() - 16)
    dataGenSub:SetPoint("TOPLEFT", secGen, "TOPLEFT", 16, yGen); local yg = 0
    yg = self:Desc(dataGenSub, yg, L["全程段落生效场景："])
    yg = self:Check(dataGenSub, L["大秘境"], yg, function() return ns.db.mythicPlus.genOverallMPlus end, function(v) ns.db.mythicPlus.genOverallMPlus=v end)
    yg = self:Check(dataGenSub, L["团队副本"], yg, function() return ns.db.mythicPlus.genOverallRaid end, function(v) ns.db.mythicPlus.genOverallRaid=v end)
    yg = self:Check(dataGenSub, L["其他副本 (含地下堡/战场/竞技场)"], yg, function() return ns.db.mythicPlus.genOverallDungeon end, function(v) ns.db.mythicPlus.genOverallDungeon=v end)
    dataGenSub:SetHeight(math.abs(yg))
    self._dataGenSub = dataGenSub; self._dataSecGen = secGen; self._dataSecGenBaseH = math.abs(yGen)

    -- Section: 删除小怪段落
    local secClean = CreateFrame("Frame", nil, inner); secClean:SetWidth(inner:GetWidth()); local yClean = 0
    yClean = self:Check(secClean, L["离开副本后自动删除小怪段落"], yClean,
        function() return ns.db.mythicPlus.autoCleanTrash end,
        function(v) ns.db.mythicPlus.autoCleanTrash=v; self:UpdateDataVisibility() end)
    local dataCleanSub = CreateFrame("Frame", nil, secClean); dataCleanSub:SetWidth(inner:GetWidth() - 16)
    dataCleanSub:SetPoint("TOPLEFT", secClean, "TOPLEFT", 16, yClean); local yc = 0
    yc = self:Desc(dataCleanSub, yc, L["删除小怪生效场景："])
    yc = self:Check(dataCleanSub, L["大秘境"], yc, function() return ns.db.mythicPlus.cleanTrashMPlus end, function(v) ns.db.mythicPlus.cleanTrashMPlus=v end)
    yc = self:Check(dataCleanSub, L["团队副本"], yc, function() return ns.db.mythicPlus.cleanTrashRaid end, function(v) ns.db.mythicPlus.cleanTrashRaid=v end)
    yc = self:Check(dataCleanSub, L["其他副本 (含地下堡/战场/竞技场)"], yc, function() return ns.db.mythicPlus.cleanTrashDungeon end, function(v) ns.db.mythicPlus.cleanTrashDungeon=v end)
    dataCleanSub:SetHeight(math.abs(yc))
    self._dataCleanSub = dataCleanSub; self._dataSecClean = secClean; self._dataSecCleanBaseH = math.abs(yClean)

    -- Section: 剩余选项
    local secRest = CreateFrame("Frame", nil, inner); secRest:SetWidth(inner:GetWidth()); local yRest = 0
    yRest = yRest - 12
    yRest = self:Check(secRest, L["启用标签简写"], yRest,
        function() return ns.db.display.useShortTabs end,
        function(v) ns.db.display.useShortTabs = v; if ns.UI then ns.UI:LayoutTabs(); ns.UI:Refresh() end end)
    yRest = self:Desc(secRest, yRest, L["标签简写预览"])
    secRest:SetHeight(math.abs(yRest))
    self._dataSecRest = secRest

    self:UpdateDataVisibility()
end

function Config:UpdateDataVisibility()
    if not self._dataSecGen then return end
    local inner = self.pages["data"].inner; if not inner then return end

    if ns.db.mythicPlus.enabled then
        self._dataGenSub:Show()
        self._dataSecGen:SetHeight(self._dataSecGenBaseH + self._dataGenSub:GetHeight())
    else
        self._dataGenSub:Hide()
        self._dataSecGen:SetHeight(self._dataSecGenBaseH)
    end

    if ns.db.mythicPlus.autoCleanTrash then
        self._dataCleanSub:Show()
        self._dataSecClean:SetHeight(self._dataSecCleanBaseH + self._dataCleanSub:GetHeight())
    else
        self._dataCleanSub:Hide()
        self._dataSecClean:SetHeight(self._dataSecCleanBaseH)
    end

    self._dataSecGen:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, self._dataTopY)
    self._dataSecClean:SetPoint("TOPLEFT", self._dataSecGen, "BOTTOMLEFT", 0, 0)
    self._dataSecRest:SetPoint("TOPLEFT", self._dataSecClean, "BOTTOMLEFT", 0, 0)

    local totalH = math.abs(self._dataTopY) + self._dataSecGen:GetHeight() + self._dataSecClean:GetHeight() + self._dataSecRest:GetHeight() + 20
    inner:SetHeight(totalH)
    self:UpdatePageScroll("data")
end
-- ============================================================
-- Look 页
-- ============================================================
function Config:BuildLookPage()
    local inner = self.pages["look"].inner; local y = 0
    local outlines = { {l=L["无"], v=""}, {l=L["发光描边 (Outline)"], v="OUTLINE"}, {l=L["加粗描边"], v="THICKOUTLINE"} }
    local textures = self:GetSharedMediaTextures(); local fonts = self:GetSharedMediaFonts()

    y = self:H(inner, L["全局尺寸"], y)
    y = self:Slider(inner, L["窗口缩放 (Scale)"], y, 0.5, 2.0, 0.05, function() return ns.db.window.scale end, function(v) ns.db.window.scale = v; if ns.UI and ns.UI.frame then ns.UI.frame:SetScale(v) end end)
    y = self:Slider(inner, L["[设置]界面缩放"], y, 0.5, 2.0, 0.05, function() return ns.db.window.configScale or 1.0 end, function(v) ns.db.window.configScale = v; if self.panel then self.panel:SetScale(v) end; if self._pvSwitcher then self._pvSwitcher:SetScale(v) end end)
    y = self:Check(inner, L["锁定窗口位置"], y, function() return ns.db.window.locked end, function(v) ns.db.window.locked = v; if ns.UI and ns.UI.UpdateLockState then ns.UI:UpdateLockState() end end)

    y = y - 12; y = self:H(inner, L["图标风格"], y)
    y = self:Dropdown(inner, L["专精图标"], y,
        { {l=L["默认"], v="default"}, {l="Apex", v="apex"}, {l="Cartoon", v="cartoon"}, {l="ToxiUI", v="toxiui"} },
        function() return ns.db.display.iconPack or "default" end,
        function(v) ns.db.display.iconPack = v; self:RefreshUI() end)

    y = y - 12; y = self:H(inner, L["界面颜色"], y)
    y = self:ColorSwatch(inner, L["标题栏/页签主题色"], y, function() local c = ns.db.window.themeColor or {0.08, 0.08, 0.12, 1}; return c[1], c[2], c[3], c[4] end, function(r, g, b, a) ns.db.window.themeColor = {r, g, b, a}; if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end end)
    y = self:ColorSwatch(inner, L["数据区背景色"], y, function() local c = ns.db.window.bgColor or {0.04, 0.04, 0.05, 0.90}; return c[1], c[2], c[3], c[4] end, function(r, g, b, a) ns.db.window.bgColor = {r, g, b, a}; if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end end)
    y = self:ColorSwatch(inner, L["总计区域背景色"], y, function() local c = ns.db.window.ovrBgColor or {0.02, 0.04, 0.08, 0.95}; return c[1], c[2], c[3], c[4] end, function(r, g, b, a) ns.db.window.ovrBgColor = {r, g, b, a}; if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end end)

    y = y - 12; y = self:H(inner, L["名称颜色"], y)
    local colorModes = { {l=L["职业颜色"], v="class"}, {l=L["纯白"], v="white"}, {l=L["自定义"], v="custom"} }
    y = self:Dropdown(inner, L["名称颜色选择"], y, colorModes, function() return ns.db.display.textColorMode or "class" end, function(v) ns.db.display.textColorMode = v; self:RefreshUI() end)
    y = self:ColorSwatchNoAlpha(inner, L["自定义名称颜色"], y, function() local c = ns.db.display.textColor or {1.0, 1.0, 1.0}; return c[1], c[2], c[3] end, function(r, g, b) ns.db.display.textColor = {r, g, b}; self:RefreshUI() end)

    y = y - 12; y = self:H(inner, L["字体设置"], y)
    y = self:Dropdown(inner, L["全局字体"], y, fonts, function() return ns.db.display.font or STANDARD_TEXT_FONT end, function(v) ns.db.display.font=v; self:RefreshUI() end)
    y = self:Slider(inner, L["字体基础大小"], y, 8, 20, 1, function() return ns.db.display.fontSizeBase or 10 end, function(v) ns.db.display.fontSizeBase=v; self:RefreshUI() end)
    y = self:Dropdown(inner, L["字体描边"], y, outlines, function() return ns.db.display.fontOutline or "OUTLINE" end, function(v) ns.db.display.fontOutline=v; self:RefreshUI() end)
    y = self:Check(inner, L["开启文字阴影"], y, function() return ns.db.display.fontShadow end, function(v) ns.db.display.fontShadow=v; self:RefreshUI() end)

    y = y - 12; y = self:H(inner, L["数据条外观"], y)
    y = self:Slider(inner, L["排版行高 (文字/图标区域)"], y, 10, 30, 1, function() return ns.db.display.barHeight end, function(v) ns.db.display.barHeight=v; self:RefreshUI() end)
    y = self:Slider(inner, L["颜色条实际粗细"], y, 1, 30, 1, function() return ns.db.display.barThickness or ns.db.display.barHeight or 19 end, function(v) ns.db.display.barThickness=v; self:RefreshUI() end)
    y = self:Slider(inner, L["颜色条垂直偏移 (从底向上)"], y, 0, 30, 1, function() return ns.db.display.barVOffset or 0 end, function(v) ns.db.display.barVOffset=v; self:RefreshUI() end)
    y = self:Slider(inner, L["数据条间距"], y, 0, 10, 1, function() return ns.db.display.barGap or 1 end, function(v) ns.db.display.barGap=v; self:RefreshUI() end)
    y = self:Slider(inner, L["数据条透明度"], y, 0.1, 1.0, 0.05, function() return ns.db.display.barAlpha or 0.85 end, function(v) ns.db.display.barAlpha=v; self:RefreshUI() end)
    y = self:Dropdown(inner, L["数据条材质"], y, textures, function() return ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8" end, function(v) ns.db.display.barTexture=v; self:RefreshUI() end)

    y = y - 12; y = self:H(inner, L["技能详情页外观"], y)
    y = self:Slider(inner, L["排版行高 (文字/图标区域)"], y, 10, 40, 1, function() return ns.db.detailDisplay.barHeight end, function(v) ns.db.detailDisplay.barHeight=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Slider(inner, L["颜色条实际粗细"], y, 1, 40, 1, function() return ns.db.detailDisplay.barThickness or ns.db.detailDisplay.barHeight or 20 end, function(v) ns.db.detailDisplay.barThickness=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Slider(inner, L["颜色条垂直偏移 (从底向上)"], y, 0, 30, 1, function() return ns.db.detailDisplay.barVOffset or 0 end, function(v) ns.db.detailDisplay.barVOffset=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Slider(inner, L["数据条间距"], y, 0, 10, 1, function() return ns.db.detailDisplay.barGap or 1 end, function(v) ns.db.detailDisplay.barGap=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Slider(inner, L["数据条透明度"], y, 0.1, 1.0, 0.05, function() return ns.db.detailDisplay.barAlpha or 0.92 end, function(v) ns.db.detailDisplay.barAlpha=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Dropdown(inner, L["数据条材质"], y, textures, function() return ns.db.detailDisplay.barTexture or "Interface\\Buttons\\WHITE8X8" end, function(v) ns.db.detailDisplay.barTexture=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Dropdown(inner, L["技能详情页字体"], y, fonts, function() return ns.db.detailDisplay.font or STANDARD_TEXT_FONT end, function(v) ns.db.detailDisplay.font=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Slider(inner, L["字体基础大小"], y, 8, 20, 1, function() return ns.db.detailDisplay.fontSizeBase or 10 end, function(v) ns.db.detailDisplay.fontSizeBase=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Dropdown(inner, L["字体描边"], y, outlines, function() return ns.db.detailDisplay.fontOutline or "OUTLINE" end, function(v) ns.db.detailDisplay.fontOutline=v; if ns.DetailView then ns.DetailView:Refresh() end end)
    y = self:Check(inner, L["开启文字阴影"], y, function() return ns.db.detailDisplay.fontShadow end, function(v) ns.db.detailDisplay.fontShadow=v; if ns.DetailView then ns.DetailView:Refresh() end end)

    y = y - 12
    local foldContainer = CreateFrame("Frame", nil, inner); foldContainer:SetWidth(inner:GetWidth()); foldContainer:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, y)
    self._foldContainer = foldContainer; self._foldContainerBaseY = y
    self:RebuildFoldAndHide()
    y = y - (self._foldContainer:GetHeight() or 0)
    inner:SetHeight(math.abs(y) + 20)
end

function Config:RebuildFoldAndHide()
    local container = self._foldContainer; if not container then return end
    for _, child in ipairs({container:GetChildren()}) do child:Hide(); child:SetParent(nil) end
    for _, region in ipairs({container:GetRegions()}) do region:Hide() end
    local y = 0
    y = self:H(container, L["折叠与隐藏"], y)
    y = y - 4
    local colHdr = container:CreateFontString(nil, "OVERLAY"); colHdr:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE"); colHdr:SetPoint("TOPLEFT", 6, y); colHdr:SetTextColor(0.6, 0.8, 1.0); colHdr:SetText(" -  " .. L["折叠"]); y = y - 20
    y = self:Check(container, L["脱战后自动折叠"], y, function() return ns.db.collapse.autoCollapse end, function(v) ns.db.collapse.autoCollapse = v; if ns.UI then ns.UI:CheckAutoCollapse() end end)
    y = self:Check(container, L["副本中永不自动折叠"], y, function() return ns.db.collapse.neverInInstance end, function(v) ns.db.collapse.neverInInstance = v; if ns.UI then ns.UI:CheckAutoCollapse() end end)
    y = self:Slider(container, L["脱战后多久后开始折叠 (秒)"], y, 0, 10, 0.5, function() return ns.db.collapse.delay or 1.5 end, function(v) ns.db.collapse.delay = v end)
    y = self:Check(container, L["开启折叠动画"], y, function() return ns.db.collapse.enableAnim end, function(v) ns.db.collapse.enableAnim = v end)
    y = self:Slider(container, L["折叠动画持续时间"], y, 0.1, 2.0, 0.1, function() return ns.db.collapse.animDuration end, function(v) ns.db.collapse.animDuration = v end)

    y = y - 12
    local fadeHdr = container:CreateFontString(nil, "OVERLAY"); fadeHdr:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE"); fadeHdr:SetPoint("TOPLEFT", 6, y); fadeHdr:SetTextColor(0.6, 0.8, 1.0); fadeHdr:SetText(" -  " .. L["自动隐藏"]); y = y - 20
    y = self:Check(container, L["鼠标移到窗口上时取消隐藏"], y, function() return ns.db.fade.unfadeOnHover end, function(v) ns.db.fade.unfadeOnHover = v; if ns.UI then ns.UI:CheckAutoFade(true) end end)
    y = self:Slider(container, L["自动隐藏延迟 (秒)"], y, 0, 10, 0.5, function() return ns.db.fade.delay or 1.5 end, function(v) ns.db.fade.delay = v; if ns.UI then ns.UI:CheckAutoFade(true) end end)
    y = y - 8

    y = self:Check(container, L["顶部与底部菜单"], y, function() return ns.db.fade.fadeBars end, function(v) ns.db.fade.fadeBars = v; if ns.UI then ns.UI:CheckAutoFade(true) end; self:RebuildFoldAndHide(); self:UpdateLookPageHeight() end)
    if ns.db.fade.fadeBars then
        local sub = CreateFrame("Frame", nil, container); sub:SetWidth(container:GetWidth() - 16); sub:SetPoint("TOPLEFT", container, "TOPLEFT", 16, y); local ys = 0
        local whenOpts = { {l=L["永远"], v="always"}, {l=L["脱战时"], v="ooc"} }
        ys = self:Dropdown(sub, L["顶部与底部菜单隐藏的场合"], ys, whenOpts, function() return ns.db.fade.barsWhen or "ooc" end, function(v) ns.db.fade.barsWhen = v; if ns.UI then ns.UI:CheckAutoFade(true) end end)
        ys = self:Check(sub, L["副本中永不隐藏顶部与底部菜单"], ys, function() return ns.db.fade.barsNeverInInstance end, function(v) ns.db.fade.barsNeverInInstance = v; if ns.UI then ns.UI:CheckAutoFade(true) end end)
        ys = self:Slider(sub, L["顶部与底部菜单隐藏时透明度"], ys, 0, 1, 0.05, function() return ns.db.fade.barsAlpha end, function(v) ns.db.fade.barsAlpha = v; if ns.UI then ns.UI:CheckAutoFade(true) end end, true)
        sub:SetHeight(math.abs(ys)); y = y - math.abs(ys)
    end

    y = self:Check(container, L["数据栏"], y, function() return ns.db.fade.fadeBody end, function(v) ns.db.fade.fadeBody = v; if ns.UI then ns.UI:CheckAutoFade(true) end; self:RebuildFoldAndHide(); self:UpdateLookPageHeight() end)
    if ns.db.fade.fadeBody then
        local sub = CreateFrame("Frame", nil, container); sub:SetWidth(container:GetWidth() - 16); sub:SetPoint("TOPLEFT", container, "TOPLEFT", 16, y); local ys = 0
        local whenOpts = { {l=L["永远"], v="always"}, {l=L["脱战时"], v="ooc"} }
        ys = self:Dropdown(sub, L["数据栏隐藏的场合"], ys, whenOpts, function() return ns.db.fade.bodyWhen or "ooc" end, function(v) ns.db.fade.bodyWhen = v; if ns.UI then ns.UI:CheckAutoFade(true) end end)
        ys = self:Check(sub, L["副本中永不隐藏数据栏"], ys, function() return ns.db.fade.bodyNeverInInstance end, function(v) ns.db.fade.bodyNeverInInstance = v; if ns.UI then ns.UI:CheckAutoFade(true) end end)
        ys = self:Slider(sub, L["数据栏隐藏时透明度"], ys, 0, 1, 0.05, function() return ns.db.fade.bodyAlpha end, function(v) ns.db.fade.bodyAlpha = v; if ns.UI then ns.UI:CheckAutoFade(true) end end, true)
        sub:SetHeight(math.abs(ys)); y = y - math.abs(ys)
    end

    y = y - 8
    y = self:Check(container, L["开启隐藏动画"], y, function() return ns.db.fade.enableAnim end, function(v) ns.db.fade.enableAnim = v end)
    y = self:Slider(container, L["隐藏动画持续时间"], y, 0.1, 2.0, 0.1, function() return ns.db.fade.animDuration end, function(v) ns.db.fade.animDuration = v end)
    container:SetHeight(math.abs(y))
end

function Config:UpdateLookPageHeight()
    if not self._foldContainer or not self._foldContainerBaseY then return end
    local inner = self.pages["look"].inner; if not inner then return end
    local totalY = math.abs(self._foldContainerBaseY) + self._foldContainer:GetHeight()
    inner:SetHeight(totalY + 20); self:UpdatePageScroll("look")
end

-- ============================================================
-- Perf 页
-- ============================================================
function Config:BuildPerfPage()
    local inner = self.pages["perf"].inner; local y = 0
    y = self:H(inner, L["智能刷新"], y)
    y = self:Slider(inner, L["战斗中刷新间隔 (秒)"], y, 0.1, 1.0, 0.1, function() return ns.db.smartRefresh.combatInterval end, function(v) ns.db.smartRefresh.combatInterval=v end)
    y = self:Slider(inner, L["脱战刷新间隔 (秒)"], y, 0.5, 5.0, 0.5, function() return ns.db.smartRefresh.idleInterval end, function(v) ns.db.smartRefresh.idleInterval=v end)
    y = y - 12
    y = self:H(inner, L["数据追踪"], y)
    y = self:Slider(inner, L["历史记录保存上限"], y, 5, 100, 1, function() return ns.db.tracking.maxSegments or 20 end, function(v) ns.db.tracking.maxSegments=v; ns.Segments:SetViewSegment(ns.Segments.viewIndex) end)
    y = self:Desc(inner, y, L["(当超过上限时，将自动删除小怪记录，优先保留Boss战和副本全程记录)"])
    inner:SetHeight(math.abs(y) + 20)
end