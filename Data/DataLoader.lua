--[[
    Light Damage - DataLoader.lua
    按需加载段落数据 (LoadSegmentData) + 重建 Overall (RebuildOverall)
    方法挂载到 ns.CombatTracker (CT) 上
]]

local addonName, ns = ...
local L = ns.L

local function getAmount(val)
    if issecretvalue and issecretvalue(val) then return 0 end
    if type(val) == "number" then return val end
    return 0
end

-- ============================================================
-- 按需加载段落数据
-- ============================================================
function ns.CombatTracker:LoadSegmentData(seg)
    if not seg or not seg._sessionID then return end
    local sid  = seg._sessionID
    local segs = ns.Segments
    if not segs then return end

    local sessions = C_DamageMeter.GetAvailableCombatSessions()
    local sessionAvailable = false
    for _, s in ipairs(sessions or {}) do
        if s.sessionID == sid then sessionAvailable = true; seg.duration = s.durationSeconds or seg.duration; break end
    end
    if not sessionAvailable then return end

    local snapshotCache = {}
    for guid, pd in pairs(seg.players) do
        snapshotCache[guid] = { specID = pd.specID, ilvl = pd.ilvl, score = pd.score }
    end

    seg.players = {}; seg.totalDamage = 0; seg.totalHealing = 0; seg.totalDamageTaken = 0

    local function checkSecret(val) return issecretvalue and issecretvalue(val) end

    for dmType, field in pairs({
        [Enum.DamageMeterType.DamageDone]  = "damage",
        [Enum.DamageMeterType.HealingDone] = "healing",
        [Enum.DamageMeterType.DamageTaken] = "damageTaken",
    }) do
        local spellField = field == "damageTaken" and "damageTakenSpells" or "spells"
        local ok, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, dmType)
        if ok and dmSession then
            if checkSecret(dmSession.totalAmount) then seg._dataLoaded = false; return end
            local segField = field == "damage" and "totalDamage" or field == "healing" and "totalHealing" or "totalDamageTaken"
            seg[segField] = dmSession.totalAmount or 0
            if dmSession.combatSources then
                for _, src in ipairs(dmSession.combatSources) do
                    if checkSecret(src.totalAmount) then seg._dataLoaded = false; return end
                    local guid, creatureID, total = src.sourceGUID, src.sourceCreatureID, src.totalAmount or 0
                    if guid and total > 0 then
                        local isPet = (creatureID ~= nil and creatureID > 0)
                        local pd = segs:GetPlayer(seg, guid, isPet and nil or src.name, nil)
                        if pd then
                            if not isPet then pd.class = src.classFilename or pd.class; local aps = getAmount(src.amountPerSecond); if aps > 0 then pd[field.."PerSec"] = aps end end
                            pd[field] = (pd[field] or 0) + total
                            if isPet then
                                pd.pets = pd.pets or {}
                                pd.pets[creatureID] = pd.pets[creatureID] or { name = src.name, spells = {}, damageTakenSpells = {}, damage = 0, healing = 0 }
                                pd.pets[creatureID][field] = (pd.pets[creatureID][field] or 0) + total
                            end
                            local ok3, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, dmType, guid, creatureID)
                            if ok3 and srcData and srcData.combatSpells then
                                local baseSpells = isPet and pd.pets[creatureID][spellField] or pd[spellField]
                                for _, sp in ipairs(srcData.combatSpells) do
                                    local spellID = getAmount(sp.spellID)
                                    if spellID > 0 then
                                        local amt = getAmount(sp.totalAmount)
                                        if amt > 0 then
                                            local targetSpells = baseSpells
                                            if not isPet then
                                                local petName = sp.creatureName
                                                if petName and petName ~= "" and not (issecretvalue and issecretvalue(pd.name)) and petName ~= pd.name and not (issecretvalue and issecretvalue(srcData.name)) and petName ~= srcData.name then
                                                    local fallbackKey = "pet_"..petName
                                                    pd.pets = pd.pets or {}
                                                    if not pd.pets[fallbackKey] then pd.pets[fallbackKey] = { name = petName, spells = {}, damageTakenSpells = {}, damage = 0, healing = 0 } end
                                                    targetSpells = pd.pets[fallbackKey][spellField]
                                                    if dmType == Enum.DamageMeterType.HealingDone then pd.pets[fallbackKey].healing = (pd.pets[fallbackKey].healing or 0) + amt
                                                    elseif dmType == Enum.DamageMeterType.DamageDone then pd.pets[fallbackKey].damage = (pd.pets[fallbackKey].damage or 0) + amt end
                                                end
                                            end
                                            if not targetSpells[spellID] then
                                                local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ("spell:"..spellID)
                                                targetSpells[spellID] = segs:NewSpellData(spellID, spellName, nil)
                                            end
                                            local sd = targetSpells[spellID]
                                            if dmType == Enum.DamageMeterType.HealingDone then sd.healing = (sd.healing or 0) + amt else sd.damage = (sd.damage or 0) + amt end
                                            sd.hits = (sd.hits or 0) + 1
                                            if sp.isAvoidable then sd.isAvoidable = true end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 可规避伤害标记（交叉查询 AvoidableDamageTaken）
    for guid, pd in pairs(seg.players) do
        if pd.damageTakenSpells and next(pd.damageTakenSpells) then
            local okAv, avoidSrc = pcall(
                C_DamageMeter.GetCombatSessionSourceFromID,
                sid, Enum.DamageMeterType.AvoidableDamageTaken, guid)
            if okAv and avoidSrc and avoidSrc.combatSpells then
                for _, sp in ipairs(avoidSrc.combatSpells) do
                    local spellID = getAmount(sp.spellID)
                    if spellID > 0 and pd.damageTakenSpells[spellID] then
                        pd.damageTakenSpells[spellID].isAvoidable = true
                    end
                end
            end
        end
    end

    -- 敌人承伤（EnemyDamageTaken type 10）
    do
        seg.enemyDamageTakenList = {}
        local okET, etSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, Enum.DamageMeterType.EnemyDamageTaken)
        if okET and etSession and etSession.combatSources then
            for _, enemy in ipairs(etSession.combatSources) do
                local creatureID = enemy.sourceCreatureID
                local enemyName = enemy.name or "?"
                local total = getAmount(enemy.totalAmount)
                if total > 0 then
                    local perSec = getAmount(enemy.amountPerSecond)
                    local entry = { creatureID = creatureID, name = enemyName, total = total, perSec = perSec, sources = {} }
                    local okSrc, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
                        sid, Enum.DamageMeterType.EnemyDamageTaken, nil, creatureID)
                    if okSrc and srcData and srcData.combatSpells then
                        for _, sp in ipairs(srcData.combatSpells) do
                            local details = sp.combatSpellDetails
                            if details then
                                local playerName = details.unitName
                                local playerClass = details.unitClassFilename or "WARRIOR"
                                local amt = getAmount(details.amount)
                                if amt == 0 then amt = getAmount(sp.totalAmount) end
                                if playerName and amt > 0 then
                                    local found = false
                                    for _, s in ipairs(entry.sources) do
                                        if s.name == playerName then s.amount = s.amount + amt; found = true; break end
                                    end
                                    if not found then
                                        table.insert(entry.sources, { name = playerName, class = playerClass, amount = amt })
                                    end
                                end
                            end
                        end
                    end
                    table.sort(entry.sources, function(a, b) return a.amount > b.amount end)
                    table.insert(seg.enemyDamageTakenList, entry)
                end
            end
            table.sort(seg.enemyDamageTakenList, function(a, b) return a.total > b.total end)
        end
    end

    -- 打断 / 驱散
    for dmType, field in pairs({ [Enum.DamageMeterType.Interrupts] = "interrupts", [Enum.DamageMeterType.Dispels] = "dispels" }) do
        local spellField = field == "interrupts" and "interruptSpells" or "dispelSpells"
        local ok, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, dmType)
        if ok and dmSession and dmSession.combatSources then
            for _, src in ipairs(dmSession.combatSources) do
                local guid, creatureID, total = src.sourceGUID, src.sourceCreatureID, getAmount(src.totalAmount)
                if guid and total > 0 then
                    local isPet = (creatureID ~= nil and creatureID > 0)
                    local pd = segs:GetPlayer(seg, guid, isPet and nil or src.name, nil)
                    if pd then
                        if not isPet then pd.class = src.classFilename or pd.class end
                        pd[field] = (pd[field] or 0) + total
                        local ok3, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, dmType, guid, creatureID)
                        if ok3 and srcData and srcData.combatSpells then
                            for _, sp in ipairs(srcData.combatSpells) do
                                local spellID = getAmount(sp.spellID)
                                if spellID > 0 then
                                    local amt = getAmount(sp.totalAmount); if amt == 0 then amt = getAmount(sp.casts) end; if amt == 0 then amt = 1 end
                                    if amt > 0 then
                                        if not pd[spellField][spellID] then local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ("spell:"..spellID); pd[spellField][spellID] = segs:NewSpellData(spellID, spellName, nil) end
                                        pd[spellField][spellID].hits = pd[spellField][spellID].hits + amt; pd[spellField][spellID].damage = pd[spellField][spellID].damage + amt
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 死亡次数
    local ok2, deathSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, Enum.DamageMeterType.Deaths)
    if ok2 and deathSession and deathSession.combatSources then
        for _, src in ipairs(deathSession.combatSources) do
            local guid, creatureID, deaths = src.sourceGUID, src.sourceCreatureID, getAmount(src.totalAmount)
            if guid and deaths > 0 and not (creatureID ~= nil and creatureID > 0) then
                local pd = segs:GetPlayer(seg, guid, src.name, nil)
                if pd then pd.class = src.classFilename or pd.class; pd.deaths = (pd.deaths or 0) + deaths end
            end
        end
    end

    for guid, pd in pairs(seg.players) do
        local snap = snapshotCache[guid]
        if snap then pd.specID = snap.specID or pd.specID; pd.ilvl = snap.ilvl or pd.ilvl; pd.score = snap.score or pd.score end
    end
    seg._dataLoaded = true
end

-- ============================================================
-- 重建 Overall 段
-- ============================================================
function ns.CombatTracker:RebuildOverall(sessions, sessionCount)
    local CT = ns.CombatTracker
    local segs = ns.Segments
    if not segs then return end
    sessions = sessions or C_DamageMeter.GetAvailableCombatSessions()
    sessionCount = sessionCount or (sessions and #sessions or 0)

    local newPlayers, newTotalDamage, newTotalHealing, newTotalDTaken, totalDur = {}, 0, 0, 0, 0
    local snap = segs._preReloadOverallData
    if snap then
        newTotalDamage = snap.totalDamage; newTotalHealing = snap.totalHealing; newTotalDTaken = snap.totalDamageTaken; totalDur = snap.duration
        for guid, pd in pairs(snap.players) do newPlayers[guid] = CopyTable(pd) end
    end

    local function getOrCreatePlayer(guid, name)
        if not newPlayers[guid] then local _, classEng = GetPlayerInfoByGUID(guid); newPlayers[guid] = segs:NewPlayerData(guid, name, classEng or "WARRIOR") end
        if name and not (issecretvalue and issecretvalue(name)) and name ~= "" then newPlayers[guid].name = ns:ShortName(name) end
        return newPlayers[guid]
    end

    for i = CT._baselineSessionCount + 1, sessionCount do
        local s = sessions[i]; local sid = s.sessionID; local dur = s.durationSeconds or 0
        if dur > 0 then
            totalDur = totalDur + dur
            for dmType, field in pairs({ [Enum.DamageMeterType.DamageDone] = "damage", [Enum.DamageMeterType.HealingDone] = "healing", [Enum.DamageMeterType.DamageTaken] = "damageTaken" }) do
                local spellField = field == "damageTaken" and "damageTakenSpells" or "spells"
                local ok2, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, dmType)
                if ok2 and dmSession and dmSession.combatSources then
                    for _, src in ipairs(dmSession.combatSources) do
                        local guid, creatureID, total = src.sourceGUID, src.sourceCreatureID, getAmount(src.totalAmount)
                        if guid and total > 0 then
                            local isPet = (creatureID ~= nil and creatureID > 0)
                            local pd = getOrCreatePlayer(guid, isPet and nil or src.name)
                            if not isPet then pd.class = src.classFilename or pd.class end
                            pd[field] = (pd[field] or 0) + total
                            if field == "damage" then newTotalDamage = newTotalDamage + total
                            elseif field == "healing" then newTotalHealing = newTotalHealing + total
                            else newTotalDTaken = newTotalDTaken + total end
                            if isPet then
                                pd.pets = pd.pets or {}; pd.pets[creatureID] = pd.pets[creatureID] or { name = src.name, spells = {}, damageTakenSpells = {}, damage = 0, healing = 0 }
                                pd.pets[creatureID][field] = (pd.pets[creatureID][field] or 0) + total
                            end
                            local ok3, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, dmType, guid, creatureID)
                            if ok3 and srcData and srcData.combatSpells then
                                local baseSpells = isPet and pd.pets[creatureID][spellField] or pd[spellField]
                                for _, sp in ipairs(srcData.combatSpells) do
                                    local spellID = getAmount(sp.spellID)
                                    if spellID > 0 then
                                        local amt = getAmount(sp.totalAmount)
                                        if amt > 0 then
                                            local targetSpells = baseSpells
                                            if not isPet then
                                                local petName = sp.creatureName
                                                if petName and petName ~= "" and not (issecretvalue and issecretvalue(pd.name)) and petName ~= pd.name and not (issecretvalue and issecretvalue(srcData.name)) and petName ~= srcData.name then
                                                    local fk = "pet_"..petName; pd.pets = pd.pets or {}
                                                    if not pd.pets[fk] then pd.pets[fk] = { name = petName, spells = {}, damageTakenSpells = {}, damage = 0, healing = 0 } end
                                                    targetSpells = pd.pets[fk][spellField]
                                                    if dmType == Enum.DamageMeterType.HealingDone then pd.pets[fk].healing = (pd.pets[fk].healing or 0) + amt
                                                    elseif dmType == Enum.DamageMeterType.DamageDone then pd.pets[fk].damage = (pd.pets[fk].damage or 0) + amt end
                                                end
                                            end
                                            if not targetSpells[spellID] then local sn = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ("spell:"..spellID); targetSpells[spellID] = segs:NewSpellData(spellID, sn, nil) end
                                            local sd = targetSpells[spellID]
                                            if dmType == Enum.DamageMeterType.HealingDone then sd.healing = (sd.healing or 0) + amt else sd.damage = (sd.damage or 0) + amt end
                                            sd.hits = (sd.hits or 0) + 1; if sp.isAvoidable then sd.isAvoidable = true end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- 可规避伤害标记（交叉查询 AvoidableDamageTaken）
            for guid, pd in pairs(newPlayers) do
                if pd.damageTakenSpells and next(pd.damageTakenSpells) then
                    local okAv, avoidSrc = pcall(
                        C_DamageMeter.GetCombatSessionSourceFromID,
                        sid, Enum.DamageMeterType.AvoidableDamageTaken, guid)
                    if okAv and avoidSrc and avoidSrc.combatSpells then
                        for _, sp in ipairs(avoidSrc.combatSpells) do
                            local spellID = getAmount(sp.spellID)
                            if spellID > 0 and pd.damageTakenSpells[spellID] then
                                pd.damageTakenSpells[spellID].isAvoidable = true
                            end
                        end
                    end
                end
            end

            -- 敌人承伤聚合
            do
                local okET, etSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, Enum.DamageMeterType.EnemyDamageTaken)
                if okET and etSession and etSession.combatSources then
                    if not segs.overall.enemyDamageTakenList then segs.overall.enemyDamageTakenList = {} end
                    local edtMap = {}
                    for _, existing in ipairs(segs.overall.enemyDamageTakenList) do edtMap[existing.creatureID or existing.name] = existing end
                    for _, enemy in ipairs(etSession.combatSources) do
                        local key = enemy.sourceCreatureID or enemy.name
                        local total = getAmount(enemy.totalAmount)
                        if total > 0 then
                            if not edtMap[key] then
                                edtMap[key] = { creatureID = enemy.sourceCreatureID, name = enemy.name or "?", total = 0, sources = {} }
                                table.insert(segs.overall.enemyDamageTakenList, edtMap[key])
                            end
                            edtMap[key].total = edtMap[key].total + total
                            local okSrc, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID,
                                sid, Enum.DamageMeterType.EnemyDamageTaken, nil, enemy.sourceCreatureID)
                            if okSrc and srcData and srcData.combatSpells then
                                for _, sp in ipairs(srcData.combatSpells) do
                                    local details = sp.combatSpellDetails
                                    if details and details.unitName then
                                        local amt = getAmount(details.amount)
                                        if amt == 0 then amt = getAmount(sp.totalAmount) end
                                        if amt > 0 then
                                            local found = false
                                            for _, s in ipairs(edtMap[key].sources) do
                                                if s.name == details.unitName then s.amount = s.amount + amt; found = true; break end
                                            end
                                            if not found then
                                                table.insert(edtMap[key].sources, { name = details.unitName, class = details.unitClassFilename or "WARRIOR", amount = amt })
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    table.sort(segs.overall.enemyDamageTakenList, function(a, b) return a.total > b.total end)
                end
            end

            -- 死亡
            local ok2, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, Enum.DamageMeterType.Deaths)
            if ok2 and dmSession and dmSession.combatSources then
                for _, src in ipairs(dmSession.combatSources) do
                    local guid, creatureID, total = src.sourceGUID, src.sourceCreatureID, getAmount(src.totalAmount)
                    if guid and total > 0 and not (creatureID ~= nil and creatureID > 0) then
                        local pd = getOrCreatePlayer(guid, src.name); pd.class = src.classFilename or pd.class; pd.deaths = (pd.deaths or 0) + total
                    end
                end
            end
            -- 打断/驱散
            for dmType, field in pairs({ [Enum.DamageMeterType.Interrupts] = "interrupts", [Enum.DamageMeterType.Dispels] = "dispels" }) do
                local spellField = field == "interrupts" and "interruptSpells" or "dispelSpells"
                local ok2, dmSession = pcall(C_DamageMeter.GetCombatSessionFromID, sid, dmType)
                if ok2 and dmSession and dmSession.combatSources then
                    for _, src in ipairs(dmSession.combatSources) do
                        local guid, creatureID, total = src.sourceGUID, src.sourceCreatureID, getAmount(src.totalAmount)
                        if guid and total > 0 then
                            local isPet = (creatureID ~= nil and creatureID > 0)
                            local pd = getOrCreatePlayer(guid, isPet and nil or src.name)
                            if not isPet then pd.class = src.classFilename or pd.class end
                            pd[field] = (pd[field] or 0) + total
                            local ok3, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sid, dmType, guid, creatureID)
                            if ok3 and srcData and srcData.combatSpells then
                                for _, sp in ipairs(srcData.combatSpells) do
                                    local spellID = getAmount(sp.spellID); if spellID > 0 then
                                        local amt = getAmount(sp.totalAmount); if amt == 0 then amt = getAmount(sp.casts) end; if amt == 0 then amt = 1 end
                                        if amt > 0 then
                                            if not pd[spellField][spellID] then local sn = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or ("spell:"..spellID); pd[spellField][spellID] = segs:NewSpellData(spellID, sn, nil) end
                                            pd[spellField][spellID].hits = pd[spellField][spellID].hits + amt; pd[spellField][spellID].damage = pd[spellField][spellID].damage + amt
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    segs.overall.players = newPlayers; segs.overall.totalDamage = newTotalDamage; segs.overall.totalHealing = newTotalHealing; segs.overall.totalDamageTaken = newTotalDTaken
    if CT._baselineSessionCount == 0 then segs.overall.duration = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Overall) or totalDur
    else segs.overall.duration = totalDur end
    segs.overall.isActive = false
    -- 敌人承伤：直接查 Overall session type，不手动累加
    do
        segs.overall.enemyDamageTakenList = {}
        local okET, etSession = pcall(C_DamageMeter.GetCombatSessionFromType,
            Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.EnemyDamageTaken)
        if okET and etSession and etSession.combatSources then
            for _, enemy in ipairs(etSession.combatSources) do
                local creatureID = enemy.sourceCreatureID
                local enemyName = enemy.name or "?"
                local total = getAmount(enemy.totalAmount)
                if total > 0 then
                    local perSec = getAmount(enemy.amountPerSecond)
                    local entry = { creatureID = creatureID, name = enemyName, total = total, perSec = perSec, sources = {} }
                    local okSrc, srcData = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
                        Enum.DamageMeterSessionType.Overall, Enum.DamageMeterType.EnemyDamageTaken,
                        nil, creatureID)
                    if okSrc and srcData and srcData.combatSpells then
                        for _, sp in ipairs(srcData.combatSpells) do
                            local details = sp.combatSpellDetails
                            if details then
                                local playerName = details.unitName
                                local playerClass = details.unitClassFilename or "WARRIOR"
                                local amt = getAmount(details.amount)
                                if amt == 0 then amt = getAmount(sp.totalAmount) end
                                if playerName and amt > 0 then
                                    local found = false
                                    for _, s in ipairs(entry.sources) do
                                        if s.name == playerName then s.amount = s.amount + amt; found = true; break end
                                    end
                                    if not found then
                                        table.insert(entry.sources, { name = playerName, class = playerClass, amount = amt })
                                    end
                                end
                            end
                        end
                    end
                    table.sort(entry.sources, function(a, b) return a.amount > b.amount end)
                    table.insert(segs.overall.enemyDamageTakenList, entry)
                end
            end
            table.sort(segs.overall.enemyDamageTakenList, function(a, b) return a.total > b.total end)
        end
    end
    if snap and snap.deathLog then segs.overall.deathLog = CopyTable(snap.deathLog) elseif not segs.overall.deathLog then segs.overall.deathLog = {} end
end
