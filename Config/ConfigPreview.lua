--[[
    Light Damage - ConfigPreview.lua
    预览系统
]]
local addonName, ns = ...
local L = ns.L
local Config = ns.Config

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
    { id="mplus",    labelKey="大秘境" },
    { id="raid",     labelKey="团队副本" },
    { id="dungeon",  labelKey="其他副本" },
    { id="outdoor",  labelKey="非副本" },
}

function Config:BuildSceneSwitcher()
    if self._pvSwitcher then return end
    local sw = CreateFrame("Frame", "LightDamagePreviewSwitcher", UIParent, "BackdropTemplate")
    sw:SetSize(430, 36); sw:SetFrameStrata("DIALOG"); sw:SetFrameLevel(110)
    sw:SetScale(ns.db and ns.db.window and ns.db.window.configScale or 1.0)
    sw:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile=nil, edgeSize=0 }); sw:SetBackdropColor(0.05, 0.05, 0.06, 0.98)
    self:CreateBorder(sw, 0.15, 0.15, 0.2, 1); sw:Hide(); self._pvSwitcher = sw
    local hint = sw:CreateFontString(nil, "OVERLAY"); hint:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE"); hint:SetPoint("LEFT", 14, 0); hint:SetText(L["|cff00ccff预览场景:|r"])
    local btnW, btnGap, rightOffset = 76, 6, -12
    self._pvSceneBtns = {}
    for i = #PREVIEW_SCENES, 1, -1 do
        local sc = PREVIEW_SCENES[i]
        local btn = CreateFrame("Button", nil, sw); btn:SetSize(btnW, 22); btn:SetPoint("RIGHT", sw, "RIGHT", rightOffset - (btnW + btnGap) * (#PREVIEW_SCENES - i), 0)
        self:FillBg(btn, 0.1, 0.1, 0.15, 1); self:CreateBorder(btn, 0.3, 0.3, 0.4, 1)
        local bt = btn:CreateFontString(nil, "OVERLAY"); bt:SetFont(STANDARD_TEXT_FONT, 10, ""); bt:SetPoint("CENTER"); bt:SetText(L[sc.labelKey]); bt:SetTextColor(0.6, 0.6, 0.6)
        btn._label = bt; btn._sceneId = sc.id
        btn:SetScript("OnClick", function() self:ApplyPreviewScene(sc.id) end)
        btn:SetScript("OnEnter", function() if self._previewSceneId ~= sc.id then bt:SetTextColor(1, 1, 1) end end)
        btn:SetScript("OnLeave", function() if self._previewSceneId ~= sc.id then bt:SetTextColor(0.6, 0.6, 0.6) end end)
        self._pvSceneBtns[i] = btn; self._pvSceneBtns[sc.id] = btn
    end
end

function Config:TogglePreview()
    if self._previewActive then self:ClosePreview() else self:OpenPreview() end
end

function Config:OpenPreview()
    if not ns.UI or not ns.Segments then return end; ns.UI:EnsureCreated()
    self._pvSave = {
        inCombat = ns.state.inCombat, isInInstance = ns.state.isInInstance, inMythicPlus = ns.state.inMythicPlus,
        instanceCategory = ns.state.instanceCategory, viewIndex = ns.Segments.viewIndex,
        current = ns.Segments.current, overall = ns.Segments.overall, history = ns.Segments.history,
        locked = ns.Segments._locked, uiPoint = ns.db.window.point, uiRelPoint = ns.db.window.relPoint,
        uiX = ns.db.window.x, uiY = ns.db.window.y,
    }
    self._pvRefreshBlocked = true; ns.Segments._locked = false; self._previewActive = true; self._previewSceneId = "mplus"
    if self._previewBtnT then self._previewBtnT:SetText(L["取消预览"]) end
    ns.UI.frame:ClearAllPoints(); ns.UI.frame:SetPoint("TOPLEFT", self.panel, "TOPRIGHT", 8, 0); ns.UI.frame:Show()
    if self._pvSwitcher then self._pvSwitcher:ClearAllPoints(); self._pvSwitcher:SetPoint("BOTTOM", ns.UI.frame, "TOP", 0, 8); self._pvSwitcher:Show() end
    self:ApplyPreviewScene("mplus")
end

function Config:ClosePreview()
    if not self._pvSave then return end
    ns.state.inCombat = self._pvSave.inCombat; ns.state.isInInstance = self._pvSave.isInInstance; ns.state.inMythicPlus = self._pvSave.inMythicPlus
    ns.state.instanceCategory = self._pvSave.instanceCategory; ns.Segments.viewIndex = self._pvSave.viewIndex
    ns.Segments.current = self._pvSave.current; ns.Segments.overall = self._pvSave.overall; ns.Segments.history = self._pvSave.history; ns.Segments._locked = self._pvSave.locked
    ns.UI.frame:ClearAllPoints(); ns.UI.frame:SetPoint(self._pvSave.uiPoint, UIParent, self._pvSave.uiRelPoint, self._pvSave.uiX, self._pvSave.uiY)
    if self._pvSwitcher then self._pvSwitcher:Hide() end
    self._pvSave = nil; self._previewActive = false; self._pvRefreshBlocked = false
    if self._previewBtnT then self._previewBtnT:SetText(L["预览"]) end
    if ns.Analysis then ns.Analysis:InvalidateCache() end; ns.UI:Layout()
end

function Config:ApplyPreviewScene(sceneId)
    if not self._previewActive then return end; self._previewSceneId = sceneId
    for id, btn in pairs(self._pvSceneBtns) do
        if type(id) == "string" then local active = (id == sceneId); btn._label:SetTextColor(active and 0 or 0.6, active and 0.75 or 0.6, active and 1 or 0.6) end
    end
    ns.state.inCombat = false; ns.state.isInInstance = (sceneId ~= "outdoor"); ns.state.inMythicPlus = (sceneId == "mplus"); ns.state.instanceCategory = sceneId
    local mockCurrent = self:BuildMockSegment(false); local mockOverall = self:BuildMockSegment(true)
    ns.Segments.current = nil; ns.Segments.history = { mockCurrent }; ns.Segments.viewIndex = 1; ns.Segments.overall = mockOverall
    if ns.Analysis then ns.Analysis:InvalidateCache() end
    -- 预览模式：只应用场景尺寸，不改变位置
    if ns.db.window.rememberSceneSize and ns.db.window.sceneSizes then
        local s = ns.db.window.sceneSizes[sceneId]
        if s then ns.UI.frame:SetSize(s.width, s.height) end
    end
    ns.UI:Layout()
end

function Config:BuildMockSegment(isOverall)
    local seg = ns.Segments:NewSegment("history", isOverall and L["模拟全程"] or L["模拟战斗"])
    seg.isActive = false; seg.duration = isOverall and 330 or 225
    local totalDmg, totalHeal, totalTaken = 0, 0, 0
    for i, mock in ipairs(PREVIEW_MOCK) do
        local guid = "pvGUID_" .. i; local pd = ns.Segments:NewPlayerData(guid, mock.name, mock.class)
        pd.damage = isOverall and math.floor(mock.damage * 1.45) or mock.damage; pd.healing = isOverall and math.floor(mock.healing * 1.45) or mock.healing
        pd.damageTaken = mock.damageTaken; pd.deaths = mock.deaths; pd.interrupts = mock.interrupts; pd.dispels = mock.dispels
        pd.damagePerSec = mock.dps; pd.healingPerSec = mock.hps; pd.damageTakenPerSec = 0; pd.pets = {}
        seg.players[guid] = pd; totalDmg = totalDmg + pd.damage; totalHeal = totalHeal + pd.healing; totalTaken = totalTaken + pd.damageTaken
    end
    seg.totalDamage = totalDmg; seg.totalHealing = totalHeal; seg.totalDamageTaken = totalTaken
    seg.deathLog = {
        { playerName="Ironhide", playerGUID="pvGUID_2", playerClass="WARRIOR", isSelf=false, killingAbility="Shadow Bolt", killerName="Big Boss", events={}, totalDamageTaken=450000, totalHealingReceived=0, timeSpan=3.2, timestamp=time(), gameTime=GetTime() },
        { playerName="Frostmantle", playerGUID="pvGUID_7", playerClass="DEATHKNIGHT", isSelf=false, killingAbility="Cleave", killerName="Big Boss", events={}, totalDamageTaken=380000, totalHealingReceived=0, timeSpan=2.1, timestamp=time(), gameTime=GetTime() },
    }
    return seg
end

function Config:RefreshPreviewTheme()
    -- 预览时同步主题
    if ns.UI and ns.UI.ApplyTheme then ns.UI:ApplyTheme() end
end

function Config:UpdatePreviewScene(sceneId)
    self:ApplyPreviewScene(sceneId)
end
