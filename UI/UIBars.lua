--[[
    Light Damage - UIBars.lua
    数据条:MakeBar, FillBars, FillBarsFromAPI, FillDeathBars, MakeValueStr

    ★ 改造说明:
    - FillBarsFromAPI 新增第 5 个可选参数 sessionID
      如果传了,从 GetCombatSessionFromID(sid, dmType) 读 (用于虚拟段)
      如果没传,沿用旧行为 GetCombatSessionFromType(sType, dmType)
]]
local addonName, ns = ...
local L = ns.L
local UI = ns.UI
local MAX_BARS = UI.MAX_BARS
local COUNT_MODES = UI.COUNT_MODES
local MODE_TO_DM = UI.MODE_TO_DM
local INTERP = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut

local function _safeSetBarValue(fs, total, ps, showPS, isCount, suffix)
    if isCount then
        fs:SetFormattedText("%s" .. suffix, ns.AbbrevNumber(total))
    elseif showPS then
        fs:SetFormattedText("%s (%s)", ns.AbbrevNumber(total), ns.AbbrevNumber(ps))
    else
        fs:SetText(ns.AbbrevNumber(total))
    end
end

local function _safeSetStatusBar(sb, maxV, val)
    if INTERP then
        sb:SetMinMaxValues(0, maxV, INTERP)
        sb:SetValue(val, INTERP)
    else
        sb:SetMinMaxValues(0, maxV)
        sb:SetValue(val)
    end
end

function UI:MakeBar(parent, section, index)
    local bar = {}

    bar.frame = CreateFrame("Button", nil, parent)
    bar.frame:SetHeight(18)
    bar.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bar.frame:Hide()

    -- ★ 最底层：背景
    bar.bg = bar.frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.1, 0.1, 0.12, 0)

    -- ★ 底层：旧 fill 备用，死亡条/分隔条还会用它
    bar.fill = bar.frame:CreateTexture(nil, "BORDER", nil, 0)
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.fill:SetWidth(1)

    -- ★ 底层 Frame：正常数据条
    bar.statusbar = CreateFrame("StatusBar", nil, bar.frame)
    bar.statusbar:SetPoint("TOPLEFT")
    bar.statusbar:SetPoint("BOTTOMRIGHT")
    bar.statusbar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar.statusbar:SetMinMaxValues(0, 1)
    bar.statusbar:SetFrameLevel(bar.frame:GetFrameLevel() + 1)
    bar.statusbar:Hide()

    local sbTex = bar.statusbar:GetStatusBarTexture()
    if sbTex then
        sbTex:SetDrawLayer("BORDER", 1)
    end

    -- ★ 上层：所有文字和 icon 都放这里，保证盖在 bar 上面
    bar.textFrame = CreateFrame("Frame", nil, bar.frame)
    bar.textFrame:SetAllPoints()
    bar.textFrame:SetFrameLevel(bar.frame:GetFrameLevel() + 5)

    -- ★ icon 放在 textFrame 上，而不是 bar.frame 上
    bar.specIcon = bar.textFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    bar.specIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.specIcon:Hide()

    bar.rank = self:FS(bar.textFrame, 9, "OUTLINE")
    bar.rank:SetPoint("LEFT", 3, 0)
    bar.rank:SetJustifyH("RIGHT")
    bar.rank:SetTextColor(1.0, 1.0, 1.0, 0.9)

    bar.name = self:FS(bar.textFrame, 10, "OUTLINE")
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)

    bar.value = self:FS(bar.textFrame, 9, "OUTLINE")
    bar.value:SetJustifyH("RIGHT")

    -- ★ 高亮最高层
    bar.hl = bar.frame:CreateTexture(nil, "HIGHLIGHT")
    bar.hl:SetAllPoints()
    bar.hl:SetColorTexture(1, 1, 1, 0.05)

    bar.section = section
    bar.index = index

    bar.frame:SetScript("OnClick", function(self2, btn)
        if btn == "RightButton" then ns.db.display.mode = ns:NextMode(ns.db.display.mode); if ns.UI then ns.UI:Layout() end; return end
        if not ns.DetailView then return end

        -- 死亡条
        if bar._isDeath then
            ns.DetailView:ShowDeathDetail(bar._data)
            return
        end

        -- 归档段(seg.players 数据路径)的敌人承伤行：直接展示来源列表
        if bar._data and bar._data._isEnemy and bar._data._sources then
            ns.DetailView:ShowEnemyDamageTakenDetail(bar._data.name, bar._data._sources, bar._data.value)
            return
        end

        -- API 路径下的敌人承伤：查 EnemyDamageTaken source，按攻击玩家聚合后展示
        if bar._data and bar._data.isAPI and bar._mode == "enemyDamageTaken" then
            ns.DetailView:ShowEnemyDamageTakenFromAPI(
                bar._data.sourceCreatureID,
                bar._nameStr,
                bar._data.totalAmount,
                bar._data.sessionType,
                bar._data.sessionID
            )
            return
        end

        -- API 路径(普通玩家技能细分)
        if bar._data and bar._data.isAPI then
            -- secret GUID 防御：自己用 UnitGUID 兜底，队友放弃 GUID 靠 creatureID
            local resolvedGUID = bar._data.sourceGUID
            if resolvedGUID and issecretvalue and issecretvalue(resolvedGUID) then
                resolvedGUID = bar._data.isLocalPlayer and UnitGUID("player") or nil
            end
            ns.DetailView:ShowSpellBreakdownFromAPI(
                resolvedGUID,
                bar._data.sourceCreatureID,
                bar._nameStr,
                bar._classStr,
                bar._mode,
                bar._data.sessionType,
                bar._data.sessionID
            )
            return
        end

        -- 归档段(Analysis 数据路径)
        if not bar._guid then return end
        local isOvr = bar.section and bar.section:sub(1, 3) == "ovr"
        local seg = isOvr and (ns.Segments and ns.Segments:GetOverallSegment()) or nil
        ns.DetailView:ShowSpellBreakdown(bar._guid, bar._nameStr, bar._classStr, bar._mode, seg)
    end)
    bar.frame:SetScript("OnEnter", function() UI:ShowTooltip(bar, bar.section) end)
    bar.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return bar
end

function UI:MakeValueStr(value, dur, mode, perSec, percent)
    if COUNT_MODES[mode] then return ns:FormatNumber(value) .. L["次"] end
    local baseStr
    if ns.db.display.showPerSecond then
        local ps = (perSec and perSec > 0) and perSec or (dur and dur > 0 and (value / dur) or nil)
        if ps then baseStr = string.format("%s (%s)", ns:FormatNumber(value), ns:FormatNumber(ps))
        else baseStr = ns:FormatNumber(value) end
    else baseStr = ns:FormatNumber(value) end
    if ns.db.display.showPercent and percent and percent > 0 then return string.format("%s  %.1f%%", baseStr, percent)
    else return baseStr end
end

function UI:FillBars(bars, listObj, data, dur, mode)
    local count = math.min(#data, MAX_BARS)
    self:UpdateScrollState(listObj, count)
    local maxV = data[1] and data[1].value or 0
    local textMode = ns.db.display.textColorMode or "class"
    local texPath = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()

    for i, bar in ipairs(bars) do
        if i <= count then
            bar.frame:SetHeight(bh); bar.frame:ClearAllPoints()
            bar.frame:SetPoint("TOPLEFT", listObj.child, "TOPLEFT", 0, -((i-1)*(bh+gap)))
            bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, -((i-1)*(bh+gap)))
            self:AnchorBarTexts(bar)
            self:ApplyFont(bar.rank, font, fSz-1, fOut, fShad); self:ApplyFont(bar.name, font, fSz, fOut, fShad); self:ApplyFont(bar.value, font, fSz-1, fOut, fShad)
            local d = data[i]; bar._data = d; bar._mode = mode; bar._isDeath = false; bar._guid = d.guid; bar._nameStr = d.name; bar._classStr = d.class
            bar.fill:Hide(); bar.statusbar:Show()
            local cc = ns:GetClassColor(d.class) or {0.5, 0.5, 0.5}
            local offset = ns.db.display.showSpecIcon and (bh + 4) or 0
            if INTERP then
                bar.statusbar:SetMinMaxValues(0, maxV > 0 and maxV or 1, INTERP)
                bar.statusbar:SetValue(d.value or 0, INTERP)
            else
                bar.statusbar:SetMinMaxValues(0, maxV > 0 and maxV or 1)
                bar.statusbar:SetValue(d.value or 0)
            end
            bar.statusbar:SetStatusBarTexture(texPath)
            bar.statusbar:SetStatusBarColor(cc[1], cc[2], cc[3], alpha)
            bar.rank:SetText(ns.db.display.showRank and (i..".") or "")
            bar.name:SetText(ns:DisplayName(d.name))
            do local nr, ng, nb
                if textMode == "white" then nr, ng, nb = 1, 1, 1
                elseif textMode == "custom" then local c = ns.db.display.textColor or {1,1,1}; nr, ng, nb = c[1], c[2], c[3]
                else nr, ng, nb = cc[1], cc[2], cc[3] end
                bar.name:SetTextColor(nr, ng, nb)
            end
            if bar.specIcon then
                local specID = d and d.specID
                if d.guid == ns.state.playerGUID then
                    local specIdx = GetSpecialization()
                    if specIdx then specID = GetSpecializationInfo(specIdx) end
                    if d then d.specID = specID end
                end
                local icon = ns:GetSpecIcon(specID, bar._classStr, d.specIconID)
                if d._isEnemy then icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" end
                if ns.db.display.showSpecIcon and icon then bar.specIcon:SetTexture(icon); bar.specIcon:Show() else bar.specIcon:Hide() end
            end
            bar.value:SetText(self:MakeValueStr(d.value, dur, mode, d.perSec, d.percent))
            bar.frame:Show()
        else if bar.specIcon then bar.specIcon:Hide() end; bar.frame:Hide(); bar._data = nil end
    end
    local listKey = nil
    if listObj == self.priList then listKey = "pri" elseif listObj == self.secList then listKey = "sec"
    elseif listObj == self.ovrPriList then listKey = "ovrPri" elseif listObj == self.ovrSecList then listKey = "ovrSec" end
    if listKey then self:CheckPinnedSelfForBars(listKey, listObj, data, dur, mode, count) end
end

-- ★ 改造:新增第 5 个可选参数 sessionID
--   传了 → 从 GetCombatSessionFromID(sid, dmType) 读 (虚拟段路径)
--   没传 → 走 GetCombatSessionFromType(sType, dmType) (实时 current/overall 路径)
function UI:FillBarsFromAPI(bars, listObj, mode, sessionType, sessionID)
    local dmType = MODE_TO_DM[mode]
    if not dmType then self:UpdateScrollState(listObj, 0); for _, bar in ipairs(bars) do bar.frame:Hide() end; return end

    local session
    if sessionID then
        local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, dmType)
        if ok then session = s end
    else
        local sType = sessionType or Enum.DamageMeterSessionType.Current
        session = self:GetCachedSession(sType, dmType)
    end

    if not session or not session.combatSources then self:UpdateScrollState(listObj, 0); for _, bar in ipairs(bars) do bar.frame:Hide() end; return end
    local sources, maxAmt = session.combatSources, session.maxAmount
    local count = math.min(#sources, MAX_BARS); self:UpdateScrollState(listObj, count)
    local textMode = ns.db.display.textColorMode or "class"; local texPath = ns.db.display.barTexture or "Interface\\Buttons\\WHITE8X8"
    local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()

    for i, bar in ipairs(bars) do
        if i <= count then
            local src = sources[i]; bar.frame:SetHeight(bh); bar.frame:ClearAllPoints()
            bar.frame:SetPoint("TOPLEFT", listObj.child, "TOPLEFT", 0, -((i-1)*(bh+gap)))
            bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, -((i-1)*(bh+gap)))
            self:AnchorBarTexts(bar); self:ApplyFont(bar.rank, font, fSz-1, fOut, fShad); self:ApplyFont(bar.name, font, fSz, fOut, fShad); self:ApplyFont(bar.value, font, fSz-1, fOut, fShad)
            bar.fill:Hide(); bar.statusbar:Show()
            local cls = src.classFilename or "WARRIOR"; local cc = ns:GetClassColor(cls) or {0.5, 0.5, 0.5}

            bar.statusbar:SetStatusBarTexture(texPath); bar.fill:SetTexture(texPath)
            bar.statusbar:SetStatusBarColor(cc[1], cc[2], cc[3], alpha)
            local tex = bar.statusbar:GetStatusBarTexture(); if tex then tex:SetVertexColor(cc[1], cc[2], cc[3], alpha) end
            bar.fill:SetVertexColor(cc[1], cc[2], cc[3], alpha)

            pcall(_safeSetStatusBar, bar.statusbar, maxAmt or 1, src.totalAmount)

            bar.rank:SetText(ns.db.display.showRank and (i .. ".") or "")

            local nameRaw = src.name
            local nameStr = ""
            local isSecret = issecretvalue and issecretvalue(nameRaw)

            if isSecret then
                nameStr = nameRaw
            elseif nameRaw then
                local ok, str = pcall(tostring, nameRaw)
                if ok and str then nameStr = str end
            end
            bar.name:SetText(ns:DisplayName(nameStr)); bar._nameStr = nameStr

            do local nr, ng, nb
                if textMode == "white" then nr, ng, nb = 1, 1, 1
                elseif textMode == "custom" then local c = ns.db.display.textColor or {1,1,1}; nr, ng, nb = c[1], c[2], c[3]
                else nr, ng, nb = cc[1], cc[2], cc[3] end
                bar.name:SetTextColor(nr, ng, nb)
            end

            pcall(_safeSetBarValue, bar.value, src.totalAmount, src.amountPerSecond,
                  ns.db.display.showPerSecond, COUNT_MODES[mode], L["次"])

            if not bar._apiData then bar._apiData = {} end
            bar._apiData.isAPI = true; bar._apiData.sourceGUID = src.sourceGUID; bar._apiData.sourceCreatureID = src.sourceCreatureID
            bar._apiData.isLocalPlayer = src.isLocalPlayer; bar._apiData.totalAmount = src.totalAmount; bar._apiData.amountPerSecond = src.amountPerSecond
            bar._apiData.sessionType = sessionType
            bar._apiData.sessionID = sessionID  -- ★ 透传给 detail view
            bar._data = bar._apiData; bar._mode = mode; bar._isDeath = false
            local guid = src.sourceGUID; bar._guid = guid; bar._classStr = cls
            local isSecretGuid = issecretvalue and issecretvalue(guid)
            local specID, ilvl, score = nil, 0, 0
            if src.isLocalPlayer then
                local specIdx = GetSpecialization(); if specIdx then specID = GetSpecializationInfo(specIdx) end
                local _, equipped = GetAverageItemLevel(); ilvl = math.floor(equipped or 0)
                local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[ns.state.playerGUID] or {}; score = cache.score or 0
            elseif not isSecretGuid then
                local cache = ns.PlayerInfoCache and ns.PlayerInfoCache[guid] or {}
                specID = cache.specID; ilvl = cache.ilvl or 0; score = cache.score or 0
            end
            bar._apiData.specID = specID; bar._apiData.ilvl = ilvl; bar._apiData.score = score
            bar._apiData.specIconID = src.specIconID

            if bar.specIcon then
                local icon = ns:GetSpecIcon(specID, cls, src.specIconID)
                if bar._mode == "enemyDamageTaken" then icon = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" end
                if ns.db.display.showSpecIcon and icon then bar.specIcon:SetTexture(icon); bar.specIcon:Show() else bar.specIcon:Hide() end
            end
            bar.frame:Show()
        else if bars[i].specIcon then bars[i].specIcon:Hide() end; bar.statusbar:Hide(); bar.fill:Show(); bar.frame:Hide() end
    end
    local listKey = nil
    if listObj == self.priList then listKey = "pri" elseif listObj == self.secList then listKey = "sec"
    elseif listObj == self.ovrPriList then listKey = "ovrPri" elseif listObj == self.ovrSecList then listKey = "ovrSec" end
    if listKey then self:CheckPinnedSelfForAPI(listKey, listObj, sources, mode, maxAmt, sessionType, sessionID) end
end

function UI:FillDeathBars(seg, bars, listObj)
    bars = bars or self.priBars; listObj = listObj or self.priList
    if self._pinnedSelf then
        local listKey = nil
        if listObj == self.priList then listKey = "pri" elseif listObj == self.ovrPriList then listKey = "ovrPri" end
        if listKey and self._pinnedSelf[listKey] then self._pinnedSelf[listKey].frame:Hide() end
    end
    local dl = ns.DeathTracker and ns.DeathTracker:GetDeathLog(seg) or {}
    local selfDeaths, otherDeaths = {}, {}
    for _, d in ipairs(dl) do if d.isSelf then table.insert(selfDeaths, d) else table.insert(otherDeaths, d) end end
    local items = {}
    if #selfDeaths > 0 then table.insert(items, {isSeparator=true, label=L["|cffff8888[自己的死亡]|r"], count=#selfDeaths}); for _, d in ipairs(selfDeaths) do table.insert(items, {isSeparator=false, d=d}) end end
    if #otherDeaths > 0 then table.insert(items, {isSeparator=true, label=L["|cffaaaaaa[队友死亡]|r"], count=#otherDeaths}); for _, d in ipairs(otherDeaths) do table.insert(items, {isSeparator=false, d=d}) end end
    local count = math.max(1, math.min(#items, MAX_BARS)); self:UpdateScrollState(listObj, count)
    local cw = listObj.child:GetWidth(); local bh, gap, alpha, font, fSz, fOut, fShad = self:GetBarConfig()
    if #items == 0 then
        for _, bar in ipairs(bars) do bar.frame:Hide() end
        local bar = bars[1]; if not bar then return end
        bar.frame:SetHeight(bh); bar.frame:ClearAllPoints()
        bar.frame:SetPoint("TOPLEFT", listObj.child, "TOPLEFT", 0, 0); bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, 0)
        self:AnchorBarTexts(bar); self:ApplyFont(bar.rank, font, fSz-1, fOut, fShad); self:ApplyFont(bar.name, font, fSz, fOut, fShad); self:ApplyFont(bar.value, font, fSz-1, fOut, fShad)
        bar._data = nil; bar._isDeath = false; bar._guid = nil; bar.statusbar:Hide(); bar.fill:Show(); bar.fill:SetWidth(1); bar.fill:SetVertexColor(0,0,0,0)
        bar.rank:SetText(""); bar.name:SetText(L["|cff555555本段暂无死亡记录|r"]); bar.name:SetTextColor(1,1,1); bar.value:SetText("")
        if bar.specIcon then bar.specIcon:Hide() end; bar.frame:Show(); return
    end
    for i = 1, MAX_BARS do
        local bar = bars[i]
        if i <= count then
            local item = items[i]; bar.frame:SetHeight(bh); bar.frame:ClearAllPoints()
            bar.frame:SetPoint("TOPLEFT", listObj.child, "TOPLEFT", 0, -((i-1)*(bh+gap)))
            bar.frame:SetPoint("TOPRIGHT", listObj.child, "TOPRIGHT", 0, -((i-1)*(bh+gap)))
            self:AnchorBarTexts(bar); self:ApplyFont(bar.rank, font, fSz-1, fOut, fShad); self:ApplyFont(bar.name, font, fSz, fOut, fShad); self:ApplyFont(bar.value, font, fSz-1, fOut, fShad)
            bar.statusbar:Hide(); bar.fill:Show()
            if item.isSeparator then
                bar._data = nil; bar._isDeath = false; bar._guid = nil; bar.fill:SetWidth(cw); bar.fill:SetVertexColor(0.06,0.06,0.08,0.95)
                bar.rank:SetText(""); bar.name:SetText(item.label .. string.format(" |cff666666(%d)|r", item.count)); bar.name:SetTextColor(1,1,1); bar.value:SetText("")
                if bar.specIcon then bar.specIcon:Hide() end
            else
                local d = item.d; bar._data = d; bar._mode = "deaths"; bar._isDeath = true; bar._guid = d.playerGUID
                bar.fill:SetVertexColor(d.isSelf and 0.45 or 0.30, 0.05, 0.05, alpha); bar.fill:SetWidth(cw)
                bar.rank:SetText("|cff888888" .. (d.timestamp and date("%H:%M", d.timestamp) or "--:--") .. "|r")
                local cc = ns:GetClassColor(d.playerClass); bar.name:SetText(ns:DisplayName(d.playerName or "?")); bar.name:SetTextColor(cc[1], cc[2], cc[3])
                local killStr = "|cffff5555" .. (d.killingAbility or "?") .. "|r"
                if d.killerName and d.killerName ~= "" and d.killerName ~= "?" then killStr = killStr .. " |cff888888by |r|cffcccccc" .. ns:DisplayName(d.killerName) .. "|r" end
                bar.value:SetText(killStr)
                if bar.specIcon then
                    local guid = d.playerGUID
                    local specID = nil
                    if guid == ns.state.playerGUID then
                        local specIdx = GetSpecialization()
                        if specIdx then specID = GetSpecializationInfo(specIdx) end
                    end
                    local icon = ns:GetSpecIcon(specID, d.playerClass, d._specIconID)
                    if ns.db.display.showSpecIcon and icon then bar.specIcon:SetTexture(icon); bar.specIcon:Show() else bar.specIcon:Hide() end
                end
            end
            bar.frame:Show()
        else bars[i].frame:Hide() end
    end
end