--[[
    LD Combat Stats - DeathTracker.lua
    死亡追踪器
]]

local addonName, ns = ...
local L = ns.L

local DT = {}
ns.DeathTracker = DT

local playerBuffers = {}
local BUFFER_SIZE   = 20

-- ============================================================
-- 初始化
-- ============================================================
function DT:Init()
    BUFFER_SIZE   = ns.db.tracking.deathLogSize or 20
    playerBuffers = {}
end

function DT:ClearBuffers()
    playerBuffers = {}
end
-- ============================================================
-- 环形缓冲区操作
-- ============================================================
local function GetBuffer(guid)
    if not playerBuffers[guid] then
        playerBuffers[guid] = {
            events   = {},
            writeIdx = 0,
            count    = 0,
            lastHP   = 0,
            maxHP    = 0,
            name     = nil,
            class    = nil,
        }
    end
    return playerBuffers[guid]
end

local function PushEvent(buf, ev)
    buf.writeIdx = (buf.writeIdx % BUFFER_SIZE) + 1
    buf.events[buf.writeIdx] = ev
    if buf.count < BUFFER_SIZE then buf.count = buf.count + 1 end
end

local function ReadBuffer(buf)
    local result = {}
    local total  = buf.count
    if total == 0 then return result end
    local startSlot = total < BUFFER_SIZE and 1 or (buf.writeIdx % BUFFER_SIZE) + 1
    for i = 0, total - 1 do
        local slot = ((startSlot - 1 + i) % BUFFER_SIZE) + 1
        local ev   = buf.events[slot]
        if ev then table.insert(result, ev) end
    end
    return result
end

-- ============================================================
-- 记录受到的伤害（CLEU）
-- 12.0 副本内 CLEU 受限，开放世界仍可用
-- ============================================================
function DT:RecordIncomingDamage(destGUID, destName, destFlags,
        amount, spellID, spellName, school, srcGUID, srcName)
    if not destGUID then return end
    if not ns:IsPlayerType(destFlags) then return end

    local buf  = GetBuffer(destGUID)
    buf.name   = ns:ShortName(destName)

    local hp, maxHP = 0, 0
    local unit = ns:FindUnitByGUID(destGUID)
    if unit then
        hp    = UnitHealth(unit)    or 0
        maxHP = UnitHealthMax(unit) or 1
    end
    buf.lastHP = hp
    buf.maxHP  = maxHP

    if not buf.class then
        local _, classEng = GetPlayerInfoByGUID(destGUID)
        buf.class = classEng
    end

    PushEvent(buf, {
        time      = GetTime(),
        timestamp = time(),
        srcName   = ns:ShortName(srcName) or "?",
        srcGUID   = srcGUID,
        spellID   = spellID  or 0,
        spellName = ns:SafeStr(spellName) ~= "" and ns:SafeStr(spellName) or L["近战"],
        school    = school   or 1,
        amount    = ns:SafeNum(amount),
        hp        = hp,
        maxHP     = maxHP,
        hpPercent = maxHP > 0 and (hp / maxHP * 100) or 0,
        overkill  = 0,
        isHeal    = false,
    })
end

-- ============================================================
-- 记录受到的治疗（CLEU）
-- ============================================================
function DT:RecordIncomingHeal(destGUID, destName, destFlags,
        amount, spellID, spellName, srcGUID, srcName)
    if not destGUID then return end
    if not ns:IsPlayerType(destFlags) then return end

    local buf = GetBuffer(destGUID)
    local hp, maxHP = 0, 0
    local unit = ns:FindUnitByGUID(destGUID)
    if unit then
        hp    = UnitHealth(unit)    or 0
        maxHP = UnitHealthMax(unit) or 1
    end

    PushEvent(buf, {
        time      = GetTime(),
        timestamp = time(),
        srcName   = ns:ShortName(srcName) or "?",
        spellID   = spellID or 0,
        spellName = ns:SafeStr(spellName) ~= "" and ns:SafeStr(spellName) or L["治疗"],
        amount    = -(ns:SafeNum(amount)),
        hp        = hp,
        maxHP     = maxHP,
        hpPercent = maxHP > 0 and (hp / maxHP * 100) or 0,
        isHeal    = true,
    })
end

-- ============================================================
-- 玩家死亡（CLEU UNIT_DIED）
-- ============================================================
function DT:OnUnitDied(guid, name, flags, cleuTimestamp)
    local buf = GetBuffer(guid)
    if buf.count == 0 then return end

    local deathEvents = ReadBuffer(buf)
    if #deathEvents == 0 then return end

    local killingBlow
    for i = #deathEvents, 1, -1 do
        if not deathEvents[i].isHeal then
            killingBlow = deathEvents[i]; break
        end
    end
    if killingBlow then
        killingBlow.overkill = math.max(0, killingBlow.amount - (killingBlow.hp or 0))
    end

    local class = buf.class
    if not class then
        if ns:IsNPCGUID(guid) then
            class = "NPC"
        else
            local ok, _, classEng = pcall(GetPlayerInfoByGUID, guid)
            class = (ok and classEng) or nil
        end
    end

    local totalDmg  = 0
    local totalHeal = 0
    for _, ev in ipairs(deathEvents) do
        if ev.isHeal then
            totalHeal = totalHeal + math.abs(ev.amount)
        else
            totalDmg = totalDmg + ev.amount
        end
    end

    local timeSpan = #deathEvents >= 2
        and (deathEvents[#deathEvents].time - deathEvents[1].time)
        or 0

    local isSelf = (guid == ns.state.playerGUID)

    local deathRecord = {
        timestamp            = recapEvents[1] and recapEvents[1].timestamp and math.floor(recapEvents[1].timestamp) or time(),
        gameTime             = GetTime(),
        playerName           = ns:ShortName(name),
        playerGUID           = guid,
        playerClass          = class,
        isSelf               = isSelf,
        killingAbility       = killingBlow and killingBlow.spellName or "Unknown",
        killerName           = killingBlow and killingBlow.srcName   or "Unknown",
        events               = deathEvents,
        lastHP               = buf.lastHP,
        maxHP                = buf.maxHP,
        totalDamageTaken     = totalDmg,
        totalHealingReceived = totalHeal,
        timeSpan             = timeSpan,
        _fromRecap           = false,
    }

    local function addToSeg(seg)
        if not seg then return end
        if isSelf then
            table.insert(seg.deathLog, 1, deathRecord)
        else
            local insertIdx = #seg.deathLog + 1
            for i, dr in ipairs(seg.deathLog) do
                if not dr.isSelf then insertIdx = i; break end
            end
            table.insert(seg.deathLog, insertIdx, deathRecord)
        end
        while #seg.deathLog > 50 do table.remove(seg.deathLog) end
    end

    if ns.Segments then
        addToSeg(ns.Segments.current)
        addToSeg(ns.Segments.overall)
        -- ★ 修复竞态：processArchivedSessions 可能已先于此函数运行，
        --   直接同步到最新历史段，确保不丢失
        if ns.Segments.history and ns.Segments.history[1] then
            addToSeg(ns.Segments.history[1])
        end
    end

    playerBuffers[guid] = nil
end

-- ============================================================
-- 自己的死亡（PLAYER_DEAD 事件）- 优先用 C_DeathRecap
-- ============================================================
function DT:OnPlayerDead()
    C_Timer.After(0.5, function()
        self:RefreshSelfDeathFromRecap()
    end)
end

function DT:RefreshSelfDeathFromRecap()
    if not C_DeathRecap or not C_DeathRecap.HasRecapEvents then return end
    if not C_DeathRecap.HasRecapEvents() then return end

    local recapEvents = C_DeathRecap.GetRecapEvents()
    if not recapEvents or #recapEvents == 0 then return end

    local maxHP  = (C_DeathRecap.GetRecapMaxHealth and C_DeathRecap.GetRecapMaxHealth()) or 0
    local events = self:ParseRecapEvents(recapEvents, maxHP)

    local killingAbility = "?"
    local killerName     = ""
    for i = #events, 1, -1 do
        if not events[i].isHeal then
            killingAbility = events[i].spellName or "?"
            killerName     = events[i].srcName   or ""
            break
        end
    end

    local totalDmg  = 0
    local totalHeal = 0
    local timeSpan  = 0
    for _, ev in ipairs(events) do
        if ev.isHeal then totalHeal = totalHeal + math.abs(ev.amount)
        else totalDmg = totalDmg + math.abs(ev.amount) end
    end
    if #events >= 2 then
        timeSpan = events[#events].time - events[1].time
    end

    local pName   = UnitName("player") or L["我"]
    local _, cls  = UnitClass("player")
    local pGUID   = UnitGUID("player")

    local deathRecord = {
        timestamp            = time(),
        gameTime             = GetTime(),
        playerName           = pName,
        playerGUID           = pGUID,
        playerClass          = cls,
        isSelf               = true,
        killingAbility       = killingAbility,
        killerName           = killerName,
        events               = events,
        lastHP               = 0,
        maxHP                = maxHP,
        totalDamageTaken     = totalDmg,
        totalHealingReceived = totalHeal,
        timeSpan             = timeSpan,
        _fromRecap           = true,
    }

    local function updateSeg(seg)
        if not seg then return end
        for i = #seg.deathLog, 1, -1 do
            if seg.deathLog[i].playerGUID == pGUID
                and (GetTime() - seg.deathLog[i].gameTime) < 5 then
                table.remove(seg.deathLog, i)
                break
            end
        end
        table.insert(seg.deathLog, 1, deathRecord)
        while #seg.deathLog > 50 do table.remove(seg.deathLog) end
    end

    if ns.Segments then
        updateSeg(ns.Segments.current)
        updateSeg(ns.Segments.overall)
        -- ★ 修复竞态：同步到最新历史段
        if ns.Segments.history and ns.Segments.history[1] then
            updateSeg(ns.Segments.history[1])
        end
    end
end

-- ============================================================
-- 解析 C_DeathRecap 事件为统一格式
--
-- 实际字段（/ldcs recap dump 确认）：
--   spellId (number, 小写d！), spellName (string),
--   sourceName (string), currentHP (number),
--   timestamp (number, unix float), event (string CLEU类型),
--   amount (number), overkill (number, -1=无超杀),
--   school (number)
-- ============================================================
function DT:ParseRecapEvents(recapEvents, maxHP)
    local result = {}
    maxHP = maxHP or 1

    -- recapEvents 是新→旧（index 1 = 致命一击），翻转为旧→新
    local reversed = {}
    for i = #recapEvents, 1, -1 do
        table.insert(reversed, recapEvents[i])
    end

    for _, ev in ipairs(reversed) do
        local spellID   = ev.spellId or 0          -- ★ 小写 d
        local spellName = ev.spellName or ""
        local evType    = ev.event or ""
        local isHeal    = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
        local amount    = ev.amount or 0
        -- overkill: -1 表示无超杀，>= 0 才是真正超杀量
        local overkill  = (ev.overkill and ev.overkill >= 0) and ev.overkill or 0

        -- 补全技能名（SWING_DAMAGE 没有 spellName）
        if spellName == "" then
            if isHeal then spellName = L["治疗"]
            elseif evType == "SWING_DAMAGE" then spellName = L["近战"]
            else spellName = L["未知"] end
        end

        -- currentHP 是该事件后的实时血量，直接使用（无需重建）
        local hp    = ev.currentHP or 0
        local hpPct = maxHP > 0 and (hp / maxHP * 100) or 0

        table.insert(result, {
            time      = ev.timestamp or GetTime(),   -- ★ 真实 unix 浮点时间戳
            spellID   = spellID,
            spellName = spellName,
            amount    = isHeal and -math.abs(amount) or math.abs(amount),
            isHeal    = isHeal,
            srcName   = ev.sourceName or "",          -- ★ 击杀者名字直接可用
            hp        = hp,
            maxHP     = maxHP,
            hpPercent = hpPct,
            overkill  = overkill,
        })
    end

    return result
end

-- ============================================================
-- 获取死亡日志
-- ============================================================
function DT:GetDeathLog(segment)
    if not segment then
        segment = ns.Segments and ns.Segments:GetViewSegment()
    end
    return segment and segment.deathLog or {}
end

function DT:GetDeathDetail(segment, index)
    local log = self:GetDeathLog(segment)
    return log and log[index]
end

function DT:GetSelfDeaths(segment)
    local log    = self:GetDeathLog(segment)
    local result = {}
    for _, dr in ipairs(log) do
        if dr.isSelf then table.insert(result, dr) end
    end
    return result
end

function DT:GetOtherDeaths(segment)
    local log    = self:GetDeathLog(segment)
    local result = {}
    for _, dr in ipairs(log) do
        if not dr.isSelf then table.insert(result, dr) end
    end
    return result
end