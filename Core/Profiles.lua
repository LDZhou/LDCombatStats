--[[
    Light Damage - Profiles.lua
    配置管理 + 历史存档读写
]]

local addonName, ns = ...
local L = ns.L

-- ============================================================
-- 配置切换
-- ============================================================
function ns:SwitchProfile(name)
    if not LightDamageGlobal.profiles[name] then return end
    
    local oldLang = ns.db.display and ns.db.display.language or "auto"

    LightDamageDB.activeProfile = name
    ns:MergeDefaults(LightDamageGlobal.profiles[name], ns.defaults)

    local newLang = ns.db.display and ns.db.display.language or "auto"

    if ns.UI and ns.UI.frame then
        local w = ns.db.window
        ns.UI.frame:SetSize(ns.UI:ClampSize(w.width, w.height))
        ns.UI.frame:ClearAllPoints()
        ns.UI.frame:SetPoint(w.point, UIParent, w.relPoint, w.x, w.y)
        ns.UI.frame:SetScale(w.scale or 1.0)
        ns.UI.frame:SetAlpha(w.alpha or 0.92)
        ns.UI:ApplyTheme()
        ns.UI:Layout()
    end
    if ns.Config then
        if ns.Config.panel then 
            ns.Config:RefreshUI() 
            local cScale = ns.db.window and ns.db.window.configScale or 1.0
            ns.Config.panel:SetScale(cScale)
            if ns.Config._pvSwitcher then ns.Config._pvSwitcher:SetScale(cScale) end
        end
        if ns.Config.RefreshTitle then ns.Config:RefreshTitle() end
    end
    
    local displayName = (name == "默认") and L["默认"] or name
    print(L["|cff00ccff[Light Damage]|r 已应用 "] .. displayName .. L["的配置"])

    if oldLang ~= newLang then
        ReloadUI()
    end
end

function ns:CreateProfile(name)
    if not name or name == "" or LightDamageGlobal.profiles[name] then return false end
    LightDamageGlobal.profiles[name] = CopyTable(LightDamageGlobal.profiles[LightDamageDB.activeProfile])
    ns:SwitchProfile(name)
    return true
end

function ns:DeleteProfile(name)
    if name == "默认" or not LightDamageGlobal.profiles[name] then return end
    LightDamageGlobal.profiles[name] = nil
    if LightDamageDB.activeProfile == name then
        ns:SwitchProfile("默认")
    end
end

function ns:RenameProfile(oldName, newName)
    if oldName == "默认" or not LightDamageGlobal.profiles[oldName] then return false end
    if not newName or newName == "" or LightDamageGlobal.profiles[newName] then return false end

    LightDamageGlobal.profiles[newName] = CopyTable(LightDamageGlobal.profiles[oldName])
    LightDamageGlobal.profiles[oldName] = nil

    if LightDamageDB.activeProfile == oldName then
        LightDamageDB.activeProfile = newName
        if ns.Config and ns.Config.RefreshTitle then ns.Config:RefreshTitle() end
    end
    print(L["|cff00ccff[Light Damage]|r 配置已重命名为 "] .. newName)
    return true
end

-- ============================================================
-- 历史存档保存
-- ============================================================
function ns:SaveSessionHistory()
    if not ns.Segments then return end
    local maxSeg = ns.db and ns.db.tracking and ns.db.tracking.maxSegments or 30

    -- 预览模式下取出真实数据
    local historyToSave = ns.Segments.history
    local overallToSave = ns.Segments.overall
    
    if ns.Config and ns.Config._previewActive and ns.Config._pvSave then
        historyToSave = ns.Config._pvSave.history or {}
        overallToSave = ns.Config._pvSave.overall
    end

    local toSave = {}
    for i, seg in ipairs(historyToSave) do
        if i > maxSeg then break end
        local compact = {
            type             = seg.type,
            name             = seg.name,
            startTime        = seg.startTime,
            endTime          = seg.endTime,
            duration         = seg.duration,
            isActive         = false,
            totalDamage      = seg.totalDamage,
            totalHealing     = seg.totalHealing,
            totalDamageTaken = seg.totalDamageTaken,
            encounterName    = seg.encounterName,
            success          = seg.success,
            mythicLevel      = seg.mythicLevel,
            mapName          = seg.mapName,
            _isMerged        = seg._isMerged,
            _isBoss          = seg._isBoss,
            _instanceTag     = seg._instanceTag,
            _preKeystone     = seg._preKeystone,
            _mythicLevel     = seg._mythicLevel,
            _mapName         = seg._mapName,
            _builtByMythicPlus = seg._builtByMythicPlus,
            _sessionID       = seg._sessionID,
            _sessionIdx      = seg._sessionIdx,
            players          = {},
            deathLog         = {},
            enemyDamageTakenList = seg.enemyDamageTakenList or {},
        }
        for guid, pd in pairs(seg.players) do
            compact.players[guid] = {
                guid            = pd.guid,
                name            = pd.name,
                class           = pd.class,
                specID          = pd.specID,
                specIconID      = pd.specIconID,
                ilvl            = pd.ilvl   or 0,
                score           = pd.score  or 0,
                damage          = pd.damage,
                healing         = pd.healing,
                damageTaken     = pd.damageTaken,
                deaths          = pd.deaths,
                interrupts      = pd.interrupts,
                dispels         = pd.dispels,
                spells          = pd.spells or {},
                damageTakenSpells = pd.damageTakenSpells or {},
                interruptSpells = pd.interruptSpells or {},
                dispelSpells    = pd.dispelSpells or {},
                pets            = pd.pets or {},
                activeTime      = pd.activeTime,
                lastActionTime  = 0,
            }
        end

        if seg.deathLog then
            for _, dr in ipairs(seg.deathLog) do
                table.insert(compact.deathLog, CopyTable(dr))
            end
        end

        table.insert(toSave, compact)
    end
    ns.db.savedHistory = toSave

    -- 保存 overall
    local ovr = overallToSave
    if ovr and (ovr.totalDamage > 0 or ovr.totalHealing > 0) then
        local compactOvr = {
            name             = ovr.name,
            duration         = ovr.duration,
            totalDamage      = ovr.totalDamage,
            totalHealing     = ovr.totalHealing,
            totalDamageTaken = ovr.totalDamageTaken,
            players          = {},
            enemyDamageTakenList = ovr.enemyDamageTakenList or {},
        }
        for guid, pd in pairs(ovr.players) do
            compactOvr.players[guid] = {
                guid            = pd.guid,
                name            = pd.name,
                class           = pd.class,
                specID          = pd.specID or (ns.PlayerInfoCache[guid] and ns.PlayerInfoCache[guid].specID),
                ilvl            = pd.ilvl or (ns.PlayerInfoCache[guid] and ns.PlayerInfoCache[guid].ilvl) or 0,
                score           = pd.score or (ns.PlayerInfoCache[guid] and ns.PlayerInfoCache[guid].score) or 0,
                damage          = pd.damage,
                healing         = pd.healing,
                damageTaken     = pd.damageTaken,
                deaths          = pd.deaths,
                interrupts      = pd.interrupts,
                dispels         = pd.dispels,
                spells          = pd.spells          or {},
                damageTakenSpells = pd.damageTakenSpells or {},
                interruptSpells = pd.interruptSpells or {},
                dispelSpells    = pd.dispelSpells    or {},
                pets            = pd.pets            or {},
                activeTime      = pd.activeTime,
                lastActionTime  = 0,
            }
        end

        compactOvr.deathLog = {}
        if ovr.deathLog then
            for _, dr in ipairs(ovr.deathLog) do
                table.insert(compactOvr.deathLog, CopyTable(dr))
            end
        end

        ns.db.savedOverall = compactOvr
    else
        ns.db.savedOverall = nil
    end
        
    -- 保存底层基准线进度
    if ns.CombatTracker then
        ns.db.savedBaseline = ns.CombatTracker._baselineSessionCount or 0
        ns.db.savedLastProcessed = ns.CombatTracker._lastProcessedCount or 0
    end
end

-- ============================================================
-- 历史存档加载
-- ============================================================
function ns:LoadSessionHistory()
    if not ns.Segments then return end
    if not ns.db.savedHistory or #ns.db.savedHistory == 0 then return end
    ns.Segments.history = {}
    for _, seg in ipairs(ns.db.savedHistory) do
        seg._dataLoaded = true
        table.insert(ns.Segments.history, seg)
    end
    if #ns.Segments.history > 0 then
        ns.Segments.viewIndex = 1
    end

    -- 恢复 overall
    local saved = ns.db.savedOverall
    if saved and (saved.totalDamage or 0) > 0 then
        ns.Segments.overall = ns.Segments:NewSegment("overall", saved.name or L["总计"])
        ns.Segments.overall.isActive         = false
        ns.Segments.overall.duration         = saved.duration         or 0
        ns.Segments.overall.totalDamage      = saved.totalDamage      or 0
        ns.Segments.overall.totalHealing     = saved.totalHealing     or 0
        ns.Segments.overall.totalDamageTaken = saved.totalDamageTaken or 0
        for guid, pd in pairs(saved.players or {}) do
            pd.specID = pd.specID or nil
            pd.ilvl   = pd.ilvl or 0
            pd.score  = pd.score or 0
            ns.Segments.overall.players[guid] = pd
        end

        if saved.deathLog then
            for _, dr in ipairs(saved.deathLog) do
                table.insert(ns.Segments.overall.deathLog, dr)
            end
        end

        ns.Segments._preReloadOverallData = {
            totalDamage      = saved.totalDamage      or 0,
            totalHealing     = saved.totalHealing     or 0,
            totalDamageTaken = saved.totalDamageTaken or 0,
            duration         = saved.duration         or 0,
            players          = CopyTable(saved.players or {}),
        }
    end

    -- 恢复底层基准线进度
    if ns.CombatTracker then
        ns.CombatTracker._baselineSessionCount = ns.db.savedBaseline or 0
        ns.CombatTracker._lastProcessedCount = ns.db.savedLastProcessed or 0
    end
end
