--[[
    Light Damage - Utils.lua
    工具函数
]]

local addonName, ns = ...
local L = ns.L

-- 职业颜色
ns.CLASS_COLORS = {
    WARRIOR     = {0.78, 0.61, 0.43}, PALADIN     = {0.96, 0.55, 0.73},
    HUNTER      = {0.67, 0.83, 0.45}, ROGUE       = {1.00, 0.96, 0.41},
    PRIEST      = {1.00, 1.00, 1.00}, DEATHKNIGHT = {0.77, 0.12, 0.23},
    SHAMAN      = {0.00, 0.44, 0.87}, MAGE        = {0.25, 0.78, 0.92},
    WARLOCK     = {0.53, 0.53, 0.93}, MONK        = {0.00, 1.00, 0.60},
    DRUID       = {1.00, 0.49, 0.04}, DEMONHUNTER = {0.64, 0.19, 0.79},
    EVOKER      = {0.20, 0.58, 0.50},
}

-- 暴雪职业图标 (回退用)
ns.CLASS_ICONS = {
    WARRIOR=132355, PALADIN=135490, HUNTER=132222, ROGUE=132320,
    PRIEST=135940, DEATHKNIGHT=135771, SHAMAN=135962, MAGE=135932,
    WARLOCK=136145, MONK=608951, DRUID=132115, DEMONHUNTER=1260827,
    EVOKER=4567212,
}

-- 自定义图标包: specID → 文件名 stem
ns.SPEC_ICON_KEYS = {
    [62]="Mage_TouchOfTheArchmage", [63]="Mage_FiredUp", [64]="Mage_HandOfFrost",
    [65]="Paladin_BeaconOfTheSavior", [66]="Paladin_GloryOfTheVanguard", [70]="Paladin_LightWithin",
    [71]="Warrior_MasterOfWarfare", [72]="Warrior_RampagingBerserker", [73]="Warrior_Phalanx",
    [102]="Druid_AscendanceEclipses", [103]="Druid_UnseenPredator", [104]="Druid_WildGuardian", [105]="Druid_Everbloom",
    [250]="DeathKnight_DanceOfMidnight", [251]="DeathKnight_ChosenOfTheFrostbrood", [252]="DeathKnight_ForbiddenKnowledge",
    [253]="Hunter_KillFrenzy", [254]="Hunter_DeadlyInsight", [255]="Hunter_RaptorSwipe",
    [256]="Priest_VoidShield", [257]="Priest_Benediction", [258]="Priest_VoidApparitions",
    [259]="Rogue_AncientArts", [260]="Rogue_Gravedigger", [261]="Rogue_Implacable",
    [262]="Shaman_FeedbackLoop", [263]="Shaman_StormUnleashed", [264]="Shaman_StormstreamTotem",
    [265]="Warlock_ShadowsOfNathreza", [266]="Warlock_DominionOfArgus", [267]="Warlock_EmbersOfNihilam",
    [268]="Monk_BringMeAnother", [269]="Monk_TigereyeBrew", [270]="Monk_Spiritfont",
    [577]="DemonHunter_EternalHunt", [581]="DemonHunter_UntetheredRage", [1480]="DemonHunter_Midnight",
    [1467]="Evoker_RisingFury", [1468]="Evoker_MerithrasBlessing", [1473]="Evoker_Duplicate",
}

-- 自定义图标包路径前缀
local ICON_ROOT = "Interface\\AddOns\\LightDamage\\Textures\\icons\\"

-- NPC GUID 判断（用于区分玩家与生物，避免 NPC 被误染战士色）
-- 用首字节快速过滤，避免 4 次 string.match 调用
local NPC_GUID_PREFIX_BYTES = {
    [67] = true,  -- 'C' Creature
    [86] = true,  -- 'V' Vehicle
    [80] = true,  -- 'P' Pet
    [71] = true,  -- 'G' GameObject
}
function ns:IsNPCGUID(guid)
    if not guid or #guid < 5 then return false end
    local b = guid:byte(1)
    if not NPC_GUID_PREFIX_BYTES[b] then return false end
    -- 只在首字节命中时才做精确匹配，避免 Player- 之类误判
    if b == 67 then return guid:byte(2) == 114 -- "Cr"eature
    elseif b == 86 then return guid:byte(2) == 101 -- "Ve"hicle
    elseif b == 80 then return guid:byte(2) == 101 -- "Pe"t
    elseif b == 71 then return guid:byte(2) == 97  -- "Ga"meObject
    end
    return false
end

function ns:GetClassColor(class)
    return ns.CLASS_COLORS[class] or {0.5, 0.5, 0.5}
end

function ns:GetClassHex(class)
    local c = ns:GetClassColor(class)
    return string.format("|cff%02x%02x%02x", c[1]*255, c[2]*255, c[3]*255)
end

-- 统一图标查询: 根据当前图标包返回 specID 对应的图标
-- 返回 nil 表示完全无图标 (调用者应自行决定是否显示职业图标兜底)
function ns:GetSpecIcon(specID, class, specIconID)
    local pack = (ns.db and ns.db.display and ns.db.display.iconPack) or "default"

    if pack == "default" then
        -- ★ 优先用 API 直接给的图标值 (队友自己都靠这个, 零延迟、不需要 inspect)
        if specIconID and specIconID > 0 then return specIconID end
        -- 没拿到 specIconID 时再走 specID 路径 (主要给本地玩家自己用)
        if specID then
            local _, _, _, icon = GetSpecializationInfoByID(specID)
            if icon then return icon end
        end
        return class and ns.CLASS_ICONS[class] or nil
    end

    -- 自定义图标包: specID -> tga 文件名映射
    -- specID 缺失时, 用 specIconID 反查 specID
    if not specID and specIconID and specIconID > 0 and ns.ICON_TO_SPECID then
        specID = ns.ICON_TO_SPECID[specIconID]
    end
    if specID then
        local stem = ns.SPEC_ICON_KEYS[specID]
        if stem then
            return ICON_ROOT .. pack .. "\\" .. stem
        end
    end
    -- ★ 自定义包匹配失败时, 用 API 给的 specIconID 作二级兜底 (起码能看到一个图标)
    if specIconID and specIconID > 0 then return specIconID end
    return class and ns.CLASS_ICONS[class] or nil
end


-- ============================================================
-- 一次性建立 specIconID -> specID 反查表
-- 用于自定义图标包: 当 API 只返回 specIconID 时反查 specID
-- 在 PLAYER_LOGIN 后调用一次即可, 数据不会变
-- ============================================================
function ns:BuildIconToSpecIDMap()
    if ns.ICON_TO_SPECID then return end
    ns.ICON_TO_SPECID = {}
    if not GetNumClasses or not GetNumSpecializationsForClassID or not GetSpecializationInfoForClassID then
        return
    end
    for classID = 1, GetNumClasses() do
        local n = GetNumSpecializationsForClassID(classID) or 0
        for specIdx = 1, n do
            local sid, _, _, icon = GetSpecializationInfoForClassID(classID, specIdx)
            if icon and sid then
                ns.ICON_TO_SPECID[icon] = sid
            end
        end
    end
end

-- 学校颜色 (伤害类型)
ns.SCHOOL_COLORS = {
    [1]  = {0.6, 0.6, 0.6},   -- Physical
    [2]  = {1.0, 0.9, 0.5},   -- Holy
    [4]  = {1.0, 0.5, 0.0},   -- Fire
    [8]  = {0.3, 1.0, 0.3},   -- Nature
    [16] = {0.5, 0.5, 1.0},   -- Frost
    [32] = {0.5, 0.0, 0.5},   -- Shadow
    [64] = {1.0, 0.5, 1.0},   -- Arcane
}

-- 格式化数字
function ns:FormatNumber(num)
    if not num or num == 0 then return "0" end
    local abs = math.abs(num)
    
    local lang = ns.currentLang
    if not lang or lang == "auto" then
        lang = (ns.db and ns.db.display and ns.db.display.language) or "auto"
    end
    if lang == "auto" then
        lang = GetLocale()
    end

    if lang == "zhCN" or lang == "zhTW" then
        if abs >= 1e8 then return string.format("%.2f亿", num / 1e8)
        elseif abs >= 1e4 then return string.format("%.2f万", num / 1e4)
        else return string.format("%.0f", num) end
    else
        if abs >= 1e6 then return string.format("%.2fM", num / 1e6)
        elseif abs >= 1e3 then return string.format("%.1fK", num / 1e3)
        else return string.format("%.0f", num) end
    end
end

-- 格式化时间
function ns:FormatTime(sec)
    if not sec or sec <= 0 then return "0:00" end
    return string.format("%d:%02d", math.floor(sec/60), math.floor(sec%60))
end

-- 格式化时间戳 (HH:MM:SS)
function ns:FormatTimestamp(t)
    if not t then return "--:--:--" end
    return date("%H:%M:%S", t)
end

-- 安全数值读取 (12.0 Secret Values 兼容)
function ns:SafeNum(val)
    if val == nil then return 0 end
    if type(val) == "number" then return val end
    local ok, n = pcall(tonumber, val)
    return (ok and n) or 0
end

function ns:SafeStr(val)
    if type(val) == "string" then return val end
    if val == nil then return "" end
    local ok, s = pcall(tostring, val)
    return (ok and s) or ""
end

-- GUID相关
function ns:IsPlayerGUID(guid)
    return guid and guid:match("^Player%-") ~= nil
end

function ns:IsPetGUID(guid)
    return guid and (guid:match("^Pet%-") ~= nil or guid:match("^Creature%-") ~= nil)
end

-- ============================================================
-- Flag 常量
-- ============================================================
local AFFILIATION_MASK = 0x0000000F
local AFF_MINE         = 0x00000001
local AFF_PARTY        = 0x00000002
local AFF_RAID         = 0x00000004

local FLAG_PLAYER      = 0x00000400
local FLAG_PET         = 0x00001000
local FLAG_GUARDIAN    = 0x00002000

function ns:IsGroupUnit(flags, guid)
    if guid and guid == ns.state.playerGUID then
        return true
    end
    if not flags then return false end
    local aff = bit.band(flags, AFFILIATION_MASK)
    return aff == AFF_MINE or aff == AFF_PARTY or aff == AFF_RAID
end

function ns:IsPlayerType(flags)
    return flags ~= nil and bit.band(flags, FLAG_PLAYER) ~= 0
end

function ns:IsPetType(flags)
    return flags ~= nil and bit.band(flags, FLAG_PET + FLAG_GUARDIAN) ~= 0
end

-- ============================================================
-- GUID → Unit 缓存
-- ============================================================
ns._guidUnitCache    = {}
ns._guidUnitCacheAge = 0

function ns:InvalidateGUIDCache()
    ns._guidUnitCache    = {}
    ns._guidUnitCacheAge = GetTime()
end

function ns:FindUnitByGUID(guid)
    if guid == ns.state.playerGUID then return "player" end

    local cached = ns._guidUnitCache[guid]
    if cached and UnitExists(cached) and UnitGUID(cached) == guid then
        return cached
    end

    local prefix = IsInRaid() and "raid" or "party"
    local count  = IsInRaid() and GetNumGroupMembers() or math.max(0, GetNumGroupMembers() - 1)
    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) then
            local g = UnitGUID(unit)
            if g then
                ns._guidUnitCache[g] = unit
                if g == guid then return unit end
            end
        end
    end
    return nil
end

-- 获取宠物主人GUID
function ns:FindPetOwner(petGUID)
    if UnitExists("pet") and UnitGUID("pet") == petGUID then
        return UnitGUID("player")
    end

    local prefix = IsInRaid() and "raid" or "party"
    local count  = IsInRaid() and GetNumGroupMembers() or math.max(0, GetNumGroupMembers() - 1)
    for i = 1, count do
        local petUnit = prefix .. "pet" .. i
        if UnitExists(petUnit) and UnitGUID(petUnit) == petGUID then
            return UnitGUID(prefix .. i)
        end
    end
    return nil
end

function ns:ShortName(name)
    if not name then return "?" end
    return name
end

function ns:DisplayName(name)
    if not name then return "?" end
    if issecretvalue and issecretvalue(name) then
        return name
    end
    if name == "" then return "?" end
    
    local ok, result = pcall(function()
        if ns.db and ns.db.display and ns.db.display.showRealm then
            return name:gsub("%-", " - ")
        else
            return name:match("^([^%-]+)") or name
        end
    end)
    
    if ok and result then return result end
    return name
end

-- 模式名称映射
ns.MODE_NAMES = {
    damage      = "伤害",
    healing     = "治疗",
    damageTaken = "承伤",
    deaths      = "死亡",
    interrupts  = "打断",
    dispels     = "驱散",
    enemyDamageTaken = "敌人承伤",
}

ns.MODE_SHORT = {
    damage          = "伤",
    healing         = "治",
    damageTaken     = "承",
    enemyDamageTaken= "敌",
    deaths          = "死",
    interrupts      = "断",
    dispels         = "驱",
    enemyDamageTaken= "敌",
}

ns.MODE_UNITS = {
    damage      = "DPS",
    healing     = "HPS",
    damageTaken = "DTPS",
}

ns.MODE_ORDER = { "damage", "healing", "damageTaken", "deaths", "interrupts", "dispels" }

function ns:NextMode(current)
    for i, m in ipairs(ns.MODE_ORDER) do
        if m == current then
            return ns.MODE_ORDER[(i % #ns.MODE_ORDER) + 1]
        end
    end
    return "damage"
end

function ns:FormatValueStr(perSec, total, mode, dur)
    local unit = ns.MODE_UNITS[mode]
    if unit and dur and dur > 0 then
        return string.format("%s(%s)", ns:FormatNumber(perSec), ns:FormatNumber(total))
    else
        return ns:FormatNumber(total)
    end
end

-- ============================================================
-- 工具函数 (从原 Core.lua 搬入)
-- ============================================================
function ns:MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = CopyTable(v)
            else
                ns:MergeDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

do
    local lang = GetLocale()
    local asian = lang == "zhCN" or lang == "zhTW" or lang == "koKR"

    local options
    if asian then
        -- 中文/韩文：< 10000 不缩写，10000 起用 萬，1亿 起用 億
        options = {
            {breakpoint=100000000, abbreviation="SECOND_NUMBER_CAP_NO_SPACE", significandDivisor=1000000, fractionDivisor=100, abbreviationIsGlobal=true},  -- 億
            {breakpoint=10000,     abbreviation="FIRST_NUMBER_CAP_NO_SPACE",  significandDivisor=100,     fractionDivisor=100, abbreviationIsGlobal=true},  -- 萬
            {breakpoint=1,         abbreviation="",                            significandDivisor=1,       fractionDivisor=1,   abbreviationIsGlobal=false},
        }
    else
        -- 英文：1K / 1M / 1B
        options = {
            {breakpoint=1000000000, abbreviation="B", significandDivisor=10000000, fractionDivisor=100, abbreviationIsGlobal=false},
            {breakpoint=1000000,    abbreviation="M", significandDivisor=10000,    fractionDivisor=100, abbreviationIsGlobal=false},
            {breakpoint=1000,       abbreviation="K", significandDivisor=10,       fractionDivisor=100, abbreviationIsGlobal=false},
            {breakpoint=1,          abbreviation="",  significandDivisor=1,        fractionDivisor=1,   abbreviationIsGlobal=false},
        }
    end

    local cfg = CreateAbbreviateConfig(options)
    local settings = {config = cfg}
    function ns.AbbrevNumber(n)
        if n == nil then return "0" end
        return AbbreviateNumbers(n, settings)
    end
end