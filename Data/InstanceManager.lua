--[[
    Light Damage - InstanceManager.lua
    副本生命周期：SmartTrimHistory + MergeAndCleanInstance
    方法挂载到 ns.CombatTracker (CT) 上
]]

local addonName, ns = ...
local L = ns.L

local function getInstanceScene(mythicLevel, instanceType)
    if mythicLevel and mythicLevel > 0 then return "mplus" end
    if instanceType == "raid" then return "raid" end
    return "dungeon"
end

local function shouldGenOverall(scene)
    if not ns.db.mythicPlus.enabled then return false end
    if scene == "mplus"   then return ns.db.mythicPlus.genOverallMPlus end
    if scene == "raid"    then return ns.db.mythicPlus.genOverallRaid end
    return ns.db.mythicPlus.genOverallDungeon
end

local function shouldCleanTrash(scene)
    if not ns.db.mythicPlus.autoCleanTrash then return false end
    if scene == "mplus"   then return ns.db.mythicPlus.cleanTrashMPlus end
    if scene == "raid"    then return ns.db.mythicPlus.cleanTrashRaid end
    return ns.db.mythicPlus.cleanTrashDungeon
end
-- ============================================================
-- 智能裁剪历史记录
-- ============================================================
function ns.CombatTracker:SmartTrimHistory()
    local segs = ns.Segments
    if not segs or not segs.history then return end
    local maxSeg = ns.db and ns.db.tracking and ns.db.tracking.maxSegments or 30

    while #segs.history > maxSeg do
        table.remove(segs.history, #segs.history)
    end
end

-- ============================================================
-- 退出副本时：合并该副本所有 seg → 一条汇总
-- ============================================================
function ns.CombatTracker:MergeAndCleanInstance(instanceTag, mythicLevel, mythicMapName, instanceName)
    local CT = ns.CombatTracker
    local segs = ns.Segments
    if not segs then return end

    mythicLevel = mythicLevel or 0
    local isRaid = (CT._currentInstanceType == "raid")

    local scene = getInstanceScene(mythicLevel, CT._currentInstanceType)
    local doGenOverall = shouldGenOverall(scene)
    local doCleanTrash = shouldCleanTrash(scene)

    local instSegs = {}
    for i, seg in ipairs(segs.history) do
        if seg._instanceTag == instanceTag and not seg._isMerged then
            table.insert(instSegs, {idx = i, seg = seg})
        end
    end
    if #instSegs == 0 then return end

    local zoneName
    if mythicLevel > 0 and mythicMapName and mythicMapName ~= "" then zoneName = mythicMapName
    elseif instanceName and instanceName ~= "" then zoneName = instanceName
    elseif instSegs[1].seg._instanceDisplayName and instSegs[1].seg._instanceDisplayName ~= "" then zoneName = instSegs[1].seg._instanceDisplayName
    else zoneName = instanceTag:match("^([^|]+)") or L["副本"] end

    -- 公共逻辑：克隆 Overall 到合并段
    local function cloneOverallToMerged(merged)
        local ovr = segs.overall
        if not ovr then return end
        merged.totalDamage = ovr.totalDamage or 0; merged.totalHealing = ovr.totalHealing or 0; merged.totalDamageTaken = ovr.totalDamageTaken or 0
        merged.duration = (CT._overallDurationSnapshot and CT._overallDurationSnapshot > 0) and CT._overallDurationSnapshot or (ovr.duration or 0)
        merged.players = CopyTable(ovr.players or {})
        merged.deathLog = CopyTable(ovr.deathLog or {})
        merged.enemyDamageTakenList = CopyTable(ovr.enemyDamageTakenList or {})
        table.sort(merged.deathLog, function(a, b) if a.isSelf ~= b.isSelf then return a.isSelf end; return (a.gameTime or 0) < (b.gameTime or 0) end)
        while #merged.deathLog > 50 do
            local removed = false
            for i = 1, #merged.deathLog do if not merged.deathLog[i].isSelf then table.remove(merged.deathLog, i); removed = true; break end end
            if not removed then table.remove(merged.deathLog, 2) end
        end
    end

    -- ================= 分支1：M+ 正常通关 =================
    if mythicLevel > 0 then
        local pending = ns.MythicPlus and ns.MythicPlus._pendingMythicSeg
        if pending then
            ns.MythicPlus._pendingMythicSeg = nil
            local mergedName = string.format("|cff4cb8e8+%d|r %s", pending.level, pending.mapName)
            local merged = segs:NewSegment("mythicplus", mergedName)
            merged.isActive = false; merged._instanceTag = nil; merged._isBoss = false; merged._isMerged = true
            merged._builtByMythicPlus = true; merged.success = pending.success
            merged._mythicLevel = pending.level; merged._mapName = pending.mapName
            merged.mythicLevel = pending.level; merged.mapName = pending.mapName
            merged.mapID = pending.mapID; merged._keystoneTime = (pending.elapsed or 0) / 1000

            cloneOverallToMerged(merged)

            local indicesToRemove, bossCount = {}, 0
            if doCleanTrash then
                for _, entry in ipairs(instSegs) do
                    if entry.seg._isBoss then 
                        bossCount = bossCount + 1 
                    else 
                        -- 记录被删的 sessionID,防止下次扫描复活
                        if entry.seg._sessionID then
                            CT._deletedSessionIDs = CT._deletedSessionIDs or {}
                            CT._deletedSessionIDs[entry.seg._sessionID] = true
                        end
                        table.insert(indicesToRemove, entry.idx) 
                    end
                end
                table.sort(indicesToRemove, function(a, b) return a > b end)
                for _, idx in ipairs(indicesToRemove) do table.remove(segs.history, idx) end
            end

            if doGenOverall and (merged.totalDamage > 0 or merged.totalHealing > 0) then table.insert(segs.history, 1, merged); segs.viewIndex = 1 end
            CT:SmartTrimHistory()
            CT:ResetBaselineToCurrentCount()
            if ns.Segments then
                ns.Segments._preReloadOverallData = nil
                if not ns.state.isInInstance then ns.Segments.overall = ns.Segments:NewSegment("overall", L["总计"]) end
            end
            CT._overallDurationSnapshot = nil; CT._exitingInstanceTag = nil
            if ns.SaveSessionHistory then ns:SaveSessionHistory() end
            if ns.UI then C_Timer.After(0, function() ns.UI:Layout() end) end
            local bossStr = bossCount > 0 and string.format(L["，保留 %d 个 Boss"], bossCount) or ""
            print(string.format(L["|cff00ccff[Light Damage]|r 副本 %s 已整理%s + 1 条全程汇总"], pending.mapName, bossStr))
            return
        end
    end

    -- ================= 分支2：非M+ 或 M+中途放弃 =================
    local mergedName
    if mythicLevel > 0 then mergedName = string.format(L["|cff4cb8e8+%d|r %s |cffaaaaaa[全程]|r"], mythicLevel, zoneName)
    else mergedName = string.format(L["%s [全程]"], zoneName) end

    local merged = segs:NewSegment("history", mergedName)
    merged.isActive = false; merged._instanceTag = nil; merged._isBoss = false; merged._isMerged = true
    if mythicLevel > 0 then merged._mythicLevel = mythicLevel; merged._mapName = zoneName end

    if not isRaid then
        cloneOverallToMerged(merged)
    else
        local totalDur = 0
        for i = #instSegs, 1, -1 do
            local entry = instSegs[i]; local src = entry.seg
            src._dataLoaded = false; CT:LoadSegmentData(src)
            if src._isBoss then
                totalDur = totalDur + (src.duration or 0)
                for guid, pd in pairs(src.players) do
                    local mp = segs:GetPlayer(merged, guid, pd.name, nil)
                    if mp then
                        mp.class = pd.class or mp.class
                        mp.damage = (mp.damage or 0) + (pd.damage or 0); mp.healing = (mp.healing or 0) + (pd.healing or 0)
                        mp.damageTaken = (mp.damageTaken or 0) + (pd.damageTaken or 0)
                        mp.interrupts = (mp.interrupts or 0) + (pd.interrupts or 0); mp.dispels = (mp.dispels or 0) + (pd.dispels or 0)
                        mp.deaths = (mp.deaths or 0) + (pd.deaths or 0)
                        for spellID, sd in pairs(pd.spells or {}) do
                            if not mp.spells[spellID] then mp.spells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school) end
                            local msd = mp.spells[spellID]; msd.damage = (msd.damage or 0) + (sd.damage or 0); msd.healing = (msd.healing or 0) + (sd.healing or 0)
                            msd.hits = (msd.hits or 0) + (sd.hits or 0); msd.crits = (msd.crits or 0) + (sd.crits or 0)
                        end
                        for spellID, sd in pairs(pd.damageTakenSpells or {}) do
                            if not mp.damageTakenSpells[spellID] then mp.damageTakenSpells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school) end
                            local msd = mp.damageTakenSpells[spellID]; msd.damage = (msd.damage or 0) + (sd.damage or 0); msd.hits = (msd.hits or 0) + (sd.hits or 0)
                        end
                        for spellID, sd in pairs(pd.interruptSpells or {}) do
                            if not mp.interruptSpells[spellID] then mp.interruptSpells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school) end
                            local msd = mp.interruptSpells[spellID]; msd.damage = (msd.damage or 0) + (sd.damage or 0); msd.hits = (msd.hits or 0) + (sd.hits or 0)
                        end
                        for spellID, sd in pairs(pd.dispelSpells or {}) do
                            if not mp.dispelSpells[spellID] then mp.dispelSpells[spellID] = segs:NewSpellData(spellID, sd.name, sd.school) end
                            local msd = mp.dispelSpells[spellID]; msd.damage = (msd.damage or 0) + (sd.damage or 0); msd.hits = (msd.hits or 0) + (sd.hits or 0)
                        end
                    end
                end
                merged.totalDamage = merged.totalDamage + (src.totalDamage or 0)
                merged.totalHealing = merged.totalHealing + (src.totalHealing or 0)
                merged.totalDamageTaken = merged.totalDamageTaken + (src.totalDamageTaken or 0)
                for _, dr in ipairs(src.deathLog or {}) do table.insert(merged.deathLog, dr) end
                for _, edt in ipairs(src.enemyDamageTakenList or {}) do
                    local found = false
                    for _, existing in ipairs(merged.enemyDamageTakenList) do
                        if existing.creatureID == edt.creatureID then
                            existing.total = existing.total + edt.total
                            for _, s in ipairs(edt.sources or {}) do
                                local sf = false
                                for _, es in ipairs(existing.sources) do
                                    if es.name == s.name then es.amount = es.amount + s.amount; sf = true; break end
                                end
                                if not sf then table.insert(existing.sources, CopyTable(s)) end
                            end
                            found = true; break
                        end
                    end
                    if not found then table.insert(merged.enemyDamageTakenList, CopyTable(edt)) end
                end
            end
        end
        merged.duration = (CT._overallDurationSnapshot and CT._overallDurationSnapshot > 0) and CT._overallDurationSnapshot or totalDur
    end

    -- 收尾：删掉小怪，保留 Boss
    local indicesToRemove, bossCount = {}, 0
    if doCleanTrash then
        for _, entry in ipairs(instSegs) do
            if entry.seg._isBoss then 
                bossCount = bossCount + 1 
            else 
                if entry.seg._sessionID then
                    CT._deletedSessionIDs = CT._deletedSessionIDs or {}
                    CT._deletedSessionIDs[entry.seg._sessionID] = true
                end
                table.insert(indicesToRemove, entry.idx) 
            end
        end
        table.sort(indicesToRemove, function(a, b) return a > b end)
        for _, idx in ipairs(indicesToRemove) do table.remove(segs.history, idx) end
    end

    if doGenOverall and (merged.totalDamage > 0 or merged.totalHealing > 0) then table.insert(segs.history, 1, merged); segs.viewIndex = 1 end
    CT:SmartTrimHistory()
    CT:ResetBaselineToCurrentCount()

    if ns.Segments then
        ns.Segments._preReloadOverallData = nil
        if not ns.state.isInInstance then
            if C_DamageMeter.ResetAllCombatSessions then
                if ns.Segments.history then
                    for _, s in ipairs(ns.Segments.history) do
                        if s._sessionID and not s._dataLoaded then CT:LoadSegmentData(s) end
                    end
                end
                CT:ClearLoadedSessionIDs()
                CT._internalReset = true; C_DamageMeter.ResetAllCombatSessions()
            end
            CT._baselineSessionCount = 0; CT._lastProcessedCount = 0; CT._initialBaselineSet = false
            ns.Segments.overall = ns.Segments:NewSegment("overall", L["总计"])
        end
    end
    CT._overallDurationSnapshot = nil; CT._exitingInstanceTag = nil
    if ns.SaveSessionHistory then ns:SaveSessionHistory() end
    if ns.UI then C_Timer.After(0, function() ns.UI:Layout() end) end
    local bossStr = bossCount > 0 and string.format(L["，保留 %d 个 Boss"], bossCount) or ""
    print(string.format(L["|cff00ccff[Light Damage]|r 副本 %s 已整理%s + 1 条全程汇总"], zoneName, bossStr))
end
