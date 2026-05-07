--!native
--!optimize 2
-- Universal Syn Save Instance++ Recreated
-- Full game dumper: scripts, models, terrain, GUI, everything
-- Works on: Solara, Fluxus, Delta, Celery, Wave, and more

local GlobalState = {}

-- ========================================
-- 1. STRING UTILITIES
-- ========================================

local function string_find(s, pattern)
    return string.find(s, pattern, 1, true)
end

local function string_gsub_case_insensitive(input, search, replacement)
    local pattern = search:gsub(".", function(c)
        return string.format("[%s%s]", c:lower(), c:upper())
    end)
    return input:gsub(pattern, replacement)
end

local function sanitize_filename(str)
    return str:gsub("[^%w%s%-%_%.]", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- ========================================
-- 2. UNIVERSAL API FINDER
-- ========================================

local function find_api_function(keyword1, keyword2, keyword3, min_args, max_args)
    local results = {}
    local seen = {}

    local function scan(tbl, depth)
        if depth > 3 or type(tbl) ~= "table" then return end
        for key, value in pairs(tbl) do
            if seen[value] then continue end
            seen[value] = true
            if type(value) == "function" then
                local s = tostring(value)
                local match = false
                if keyword1 and string_find(s, keyword1) then match = true end
                if keyword2 and not match and string_find(s, keyword2) then match = true end
                if keyword3 and not match and string_find(s, keyword3) then match = true end
                if match then
                    local info = debug.getinfo(value)
                    local params = info and info.nparams or 0
                    if (not min_args or params >= min_args) and (not max_args or params <= max_args) then
                        table.insert(results, { func = value, score = (keyword1 and 3 or 0) + (keyword2 and 2 or 0) + (keyword3 and 1 or 0) })
                    end
                end
            elseif type(value) == "table" then
                scan(value, depth + 1)
            end
        end
    end

    local reg = getreg and getreg() or getregistry and getregistry()
    if reg then scan(reg, 0) end
    scan(getfenv and getfenv() or _G, 0)

    table.sort(results, function(a, b) return a.score > b.score end)
    return results[1] and results[1].func
end

-- ========================================
-- 3. EXECUTOR DETECTION
-- ========================================

local identify_executor = identifyexecutor or getexecutorname or whatexecutor
local EXECUTOR_NAME = identify_executor and identify_executor() or "Unknown"

print("[SSI++] Executor: " .. EXECUTOR_NAME)

-- Fix for Solara nil instances
if enablenilinstances then enablenilinstances() end

-- ========================================
-- 4. API ALIASES (Universal Finder Fallback)
-- ========================================

local writefile = writefile
local readfile = readfile
local isfile = isfile
local appendfile = appendfile
local decompile = decompile
local gethiddenproperty = gethiddenproperty
local gethui = gethui
local getnilinstances = getnilinstances or function() return {} end
local getscriptbytecode = getscriptbytecode
local setthreadidentity = setthreadidentity
local protectgui = protectgui or function() end
local setclipboard = setclipboard

-- Find APIs via universal finder if not natively available
if not gethiddenproperty then
    gethiddenproperty = find_api_function("gethiddenproperty", "gethiddenprop", "hiddenproperty")
end
if not gethui then
    gethui = find_api_function("gethui", "gethiddenui")
end
if not decompile then
    decompile = find_api_function("decompile", "dumpstring", "scriptdump")
end
if not getscriptbytecode then
    getscriptbytecode = find_api_function("getscriptbytecode", "dumpbytecode", "getbytecode")
end
if not setthreadidentity then
    setthreadidentity = find_api_function("setthreadidentity", "setidentity", "identity")
end

-- Set thread identity if available (needed for hidden properties)
if setthreadidentity then
    local old_identity = setthreadidentity(2)
    if old_identity then setthreadidentity(old_identity) end
end

-- ========================================
-- 5. SERVICE PROXY (Lazy-Loaded)
-- ========================================

local ServiceCache = {}
local Services = {}

local function get_service(name)
    if ServiceCache[name] then return ServiceCache[name] end
    local svc = game:GetService(name)
    ServiceCache[name] = svc
    return svc
end

local ContentProvider = get_service("ContentProvider")
local HttpService = get_service("HttpService")
local CollectionService = get_service("CollectionService")
local GuiService = get_service("GuiService")
local RunService = get_service("RunService")
local Stats = get_service("Stats")
local LocalizationService = get_service("LocalizationService")
local UGCValidationService = get_service("UGCValidationService")

-- ========================================
-- 6. REFERENT SYSTEM (UUID v4)
-- ========================================

local InstanceRefMap = {}

local function generate_uuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return template:gsub("[xy]", function(c)
        local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format("%x", v)
    end):gsub("-", ""):upper()
end

local function get_ref(instance)
    if not InstanceRefMap[instance] then
        InstanceRefMap[instance] = "RBX" .. generate_uuid()
    end
    return InstanceRefMap[instance]
end

-- ========================================
-- 7. SHAREDSTRING SYSTEM
-- ========================================

local SharedStrings = {}
local SharedStringLookup = {}

local function get_shared_string(content)
    if SharedStringLookup[content] then
        return SharedStringLookup[content]
    end
    local hash
    if base64encode then
        hash = base64encode(content)
    else
        hash = string.format("hash_%d", #SharedStrings + 1)
    end
    SharedStrings[hash] = content
    SharedStringLookup[content] = hash
    return hash
end

-- ========================================
-- 8. HTTP FETCH (API Dump from GitHub)
-- ========================================

local API_CLASSES = {}
local API_LOADED = false

local function fetch_api_classes()
    if API_LOADED then return end
    local success, result = pcall(function()
        local urls = {
            "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/MiniAPI/Classes.lua",
            "https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API/Classes.json",
        }
        for _, url in ipairs(urls) do
            local ok, data = pcall(function()
                return HttpService:GetAsync(url)
            end)
            if ok and data then
                local parsed = HttpService:JSONDecode(data)
                if parsed.Classes then
                    for _, class in ipairs(parsed.Classes) do
                        local props = {}
                        if class.Members then
                            for _, member in ipairs(class.Members) do
                                if member.MemberType == "Property" and member.Serialization then
                                    if member.Serialization.CanLoad ~= false then
                                        table.insert(props, member.Name)
                                    end
                                end
                            end
                        end
                        API_CLASSES[class.Name] = props
                        -- Also handle flat array format
                        if type(class) == "table" and not class.Members then
                            API_CLASSES[class.Name or tostring(_)] = {}
                        end
                    end
                end
                return true
            end
        end
        return false
    end)
    API_LOADED = true
    return success and result
end

local function get_class_properties(className)
    if API_CLASSES[className] then
        return API_CLASSES[className]
    end
    local props = {}
    local ok, classInfo = pcall(function()
        return game:GetService("Workspace"):GetPropertyChangedSignal("Parent")
    end)
    -- Fallback: use instance properties
    local temp = Instance.new(className)
    if temp then
        for _, prop in ipairs(temp:GetProperties()) do
            table.insert(props, prop.Name)
        end
        temp:Destroy()
    end
    API_CLASSES[className] = props
    return props
end

-- ========================================
-- 9. ESCAPE / CDATA UTILITIES
-- ========================================

local ESCAPES = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&apos;",
}

local function xml_escape(str)
    if not str then return "" end
    return tostring(str):gsub("[&<>'\"]", function(c) return ESCAPES[c] end)
end

local function cdata_wrap(str)
    if not str then return "" end
    str = tostring(str)
    if string_find(str, "]]>") then
        return str:gsub("]]>", "]]]]><![CDATA[>")
    end
    return "<![CDATA[" .. str .. "]]>"
end

-- ========================================
-- 10. XML PROPERTY SERIALIZERS
-- ========================================

local function serialize_BrickColor(val)
    return tostring(val.Number)
end

local function serialize_Color3(val)
    return string.format("%f,%f,%f", val.r, val.g, val.b)
end

local function serialize_Color3uint8(val)
    return string.format("%d,%d,%d",
        math.floor(val.r * 255 + 0.5),
        math.floor(val.g * 255 + 0.5),
        math.floor(val.b * 255 + 0.5)
    )
end

local function serialize_CFrame(val)
    local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = val:GetComponents()
    return string.format(
        "%f,%f,%f,%.14f,%.14f,%.14f,%.14f,%.14f,%.14f,%.14f,%.14f,%.14f",
        x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22
    )
end

local function serialize_Vector2(val)
    return string.format("%f,%f", val.X, val.Y)
end

local function serialize_Vector3(val)
    return string.format("%f,%f,%f", val.X, val.Y, val.Z)
end

local function serialize_Vector2int16(val)
    return string.format("%d,%d", val.X, val.Y)
end

local function serialize_Vector3int16(val)
    return string.format("%d,%d,%d", val.X, val.Y, val.Z)
end

local function serialize_UDim(val)
    return string.format("%f,%d", val.Scale, val.Offset)
end

local function serialize_UDim2(val)
    return string.format("%f,%d,%f,%d",
        val.X.Scale, val.X.Offset, val.Y.Scale, val.Y.Offset
    )
end

local function serialize_Region3(val)
    return serialize_Vector3(val.CFrame.Position - val.Size / 2)
        .. "," .. serialize_Vector3(val.Size)
end

local function serialize_Region3int16(val)
    local min = val.Min
    local max = val.Max
    return string.format("%d,%d,%d,%d,%d,%d",
        min.X, min.Y, min.Z, max.X, max.Y, max.Z
    )
end

local function serialize_Ray(val)
    return serialize_Vector3(val.Origin) .. "," .. serialize_Vector3(val.Direction)
end

local function serialize_Rect(val)
    return serialize_Vector2(val.Min) .. "," .. serialize_Vector2(val.Max)
end

local function serialize_PhysicalProperties(val)
    return string.format("%f,%f,%f,%f,%f",
        val.Density, val.Friction, val.Elasticity,
        val.FrictionWeight, val.ElasticityWeight
    )
end

local function serialize_Font(val)
    local face = val.Family or "rbxasset://fonts/families/SourceSansPro.json"
    local weight = val.Weight and val.Weight.Value or 400
    local style = val.Style and val.Style.Value or 0
    local cached = val.CachedFaceId or ""
    return string.format("%s,%d,%d,%s", face, weight, style, cached)
end

local function serialize_Faces(val)
    local n = 0
    local bit = 1
    for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
        if val[face.Name] then n = n + bit end
        bit = bit * 2
    end
    return tostring(n)
end

local function serialize_Axes(val)
    local n = 0
    if val.X then n = n + 1 end
    if val.Y then n = n + 2 end
    if val.Z then n = n + 4 end
    return tostring(n)
end

local function serialize_NumberSequence(val)
    local parts = {}
    for _, kp in ipairs(val.Keypoints) do
        table.insert(parts, string.format("%f,%f,%d", kp.Time, kp.Value, kp.Envelope))
    end
    return table.concat(parts, ",")
end

local function serialize_ColorSequence(val)
    local parts = {}
    for _, kp in ipairs(val.Keypoints) do
        table.insert(parts, string.format("%f,%f,%f,%f",
            kp.Time, kp.Value.r, kp.Value.g, kp.Value.b
        ))
    end
    return table.concat(parts, ",")
end

local function serialize_NumberRange(val)
    return string.format("%f,%f", val.Min, val.Max)
end

local function serialize_EnumItem(val)
    return tostring(val.Value)
end

local function serialize_SecurityCapabilities(val)
    return tostring(val)
end

local function serialize_UniqueId(val)
    if type(val) == "string" then return val end
    return tostring(val)
end

local function serialize_Random(val)
    local seed = val:NextInteger(0, 2^31 - 1)
    return tostring(seed)
end

local function serialize_Content(val)
    return tostring(val)
end

-- XML tag map
local XML_TAGS = {
    ["string"] = "string",
    ["Content"] = "Content",
    ["bool"] = "bool",
    ["int"] = "int",
    ["int64"] = "int64",
    ["float"] = "float",
    ["double"] = "double",
    ["UDim"] = "UDim",
    ["UDim2"] = "UDim2",
    ["Ray"] = "Ray",
    ["Faces"] = "Faces",
    ["Axes"] = "Axes",
    ["BrickColor"] = "BrickColor",
    ["Color3"] = "Color3",
    ["Color3uint8"] = "Color3uint8",
    ["Vector2"] = "Vector2",
    ["Vector3"] = "Vector3",
    ["Vector2int16"] = "Vector2int16",
    ["Vector3int16"] = "Vector3int16",
    ["CFrame"] = "CFrame",
    ["EnumItem"] = "Enum",
    ["NumberSequence"] = "NumberSequence",
    ["ColorSequence"] = "ColorSequence",
    ["NumberRange"] = "NumberRange",
    ["Rect"] = "Rect",
    ["PhysicalProperties"] = "PhysicalProperties",
    ["Region3"] = "Region3",
    ["Region3int16"] = "Region3int16",
    ["Font"] = "Font",
    ["SecurityCapabilities"] = "SecurityCapabilities",
    ["BinaryString"] = "BinaryString",
    ["UniqueId"] = "UniqueId",
    ["Ref"] = "Ref",
    ["ProtectedString"] = "ProtectedString",
    ["SharedString"] = "SharedString",
    ["Random"] = "Random",
}

-- ========================================
-- 11. NOTSCRIPTABLEFIXES
-- ========================================

local NotScriptableFixes = {}

-- Instance AttributesSerialize
NotScriptableFixes["Instance.AttributesSerialize"] = function(instance, value)
    if type(value) ~= "table" or next(value) == nil then
        return nil, nil
    end
    local attrs = {}
    for name, val in pairs(value) do
        table.insert(attrs, { name = name, value = val })
    end
    -- Simple binary-ish encoding for XML (as hex string)
    local buf = {}
    for _, attr in ipairs(attrs) do
        local attrType = type(attr.value)
        table.insert(buf, attr.name .. "=" .. attrType .. "=" .. tostring(attr.value))
    end
    return table.concat(buf, "\n"), "BinaryString"
end

-- Instance Tags
NotScriptableFixes["Instance.Tags"] = function(instance, value)
    local tags = CollectionService:GetTags(instance)
    if #tags == 0 then return nil, nil end
    return table.concat(tags, ","), "string"
end

-- Terrain MaterialColors
NotScriptableFixes["Terrain.MaterialColors"] = function(instance, value)
    if not value then return nil, nil end
    local colors = {}
    for _, mat in ipairs(Enum.Material:GetEnumItems()) do
        local color = instance:GetMaterialColor(mat)
        table.insert(colors, string.format("%d,%d,%d,%d",
            mat.Value,
            math.floor(color.r * 255),
            math.floor(color.g * 255),
            math.floor(color.b * 255)
        ))
    end
    return table.concat(colors, ","), "string"
end

-- BallSocketConstraint
NotScriptableFixes["BallSocketConstraint.MaxFrictionTorqueXml"] = function(instance, value)
    local prop = instance:FindFirstChild("MaxFrictionTorqueXml")
    if not prop then return nil, nil end
    return tostring(prop.Value), "float"
end

-- DoubleConstrainedValue / IntConstrainedValue
NotScriptableFixes["DoubleConstrainedValue.value"] = function(instance, value)
    return tostring(instance.Value or 0), "double"
end
NotScriptableFixes["IntConstrainedValue.value"] = function(instance, value)
    return tostring(instance.Value or 0), "int"
end

-- ========================================
-- 12. CLASS PROPERTY EXCEPTIONS
-- ========================================

local ClassPropertyExceptions = {
    -- Properties to always skip
    SkipAll = {
        "Parent",
    },
    -- Properties that must be read via hidden property
    ForceHidden = {
        "Source",
        "LinkedSource",
        "ScriptGuid",
    },
}

-- ========================================
-- 13. READ PROPERTY (with fallback chain)
-- ========================================

local function read_property(instance, propName, propType, options)
    options = options or {}
    local success, value

    -- Try normal read first
    success, value = pcall(function()
        return instance[propName]
    end)

    -- If that failed, try gethiddenproperty
    if not success and gethiddenproperty then
        success, value = pcall(function()
            return gethiddenproperty(instance, propName)
        end)
    end

    -- If still failed, try UGCValidationService fallback
    if not success and UGCValidationService then
        success, value = pcall(function()
            return UGCValidationService:GetPropertyValue(instance, propName)
        end)
    end

    -- If still failed, check NotScriptableFixes
    if not success or value == nil then
        local key = instance.ClassName .. "." .. propName
        if NotScriptableFixes[key] then
            success, value = pcall(function()
                return NotScriptableFixes[key](instance, value)
            end)
        end
    end

    if success and value ~= nil then
        -- Filter invalid values
        if type(value) == "userdata" and not pcall(function() return tostring(value) end) then
            return nil, nil
        end
        return value, propType
    end

    return nil, nil
end

-- ========================================
-- 14. GET INHERITED PROPERTIES
-- ========================================

local function get_inherited_props(className)
    local props = {}
    local current = className
    local seen = {}
    while current and current ~= "" and not seen[current] do
        seen[current] = true
        local classProps = get_class_properties(current)
        for _, prop in ipairs(classProps) do
            if not props[prop.Name] then
                props[prop.Name] = { Type = prop.ValueType, Name = prop.Name }
            end
        end
        -- Get superclass
        local temp = Instance.new(current)
        if temp then
            current = temp.ClassName
            if current == className then current = nil end
            temp:Destroy()
        else
            break
        end
    end
    return props
end

-- ========================================
-- 15. SCRIPT DECOMPILER (with cache + timeout)
-- ========================================

local ScriptCache = {}
local DecompilerRunning = false

local function timeout_handler(timeout, func)
    local result = nil
    local done = false
    local thread = coroutine.create(func)

    local start = tick()
    while not done and (tick() - start) < timeout do
        local ok, val = coroutine.resume(thread)
        if not ok then
            return nil, val
        end
        if coroutine.status(thread) == "dead" then
            result = val
            done = true
        else
            RunService.Heartbeat:Wait()
        end
    end

    if not done then
        return nil, "timeout"
    end
    return result
end

local function save_bytecode(script)
    if not getscriptbytecode then return nil end
    local success, bc = pcall(function()
        return getscriptbytecode(script)
    end)
    if success and bc and #bc > 0 then
        if base64encode then
            return base64encode(bc)
        end
        return tostring(bc)
    end
    return nil
end

local function decompile_script(script, options)
    options = options or {}
    local cache_key = script:GetFullName()

    -- Check cache
    if options.scriptcache ~= false and ScriptCache[cache_key] then
        return ScriptCache[cache_key]
    end

    -- Check if we should skip
    if options.noscripts then
        return nil
    end

    -- Check decompile ignore list
    if options.decompile_ignore then
        for _, ignore in ipairs(options.decompile_ignore) do
            if string_find(cache_key, ignore) then
                return nil
            end
        end
    end

    -- Skip jobless mode
    if options.decompile_jobless then
        return nil
    end

    if not decompile then
        return nil
    end

    -- Decompile with timeout
    local timeout = options.timeout or 15
    local source = nil
    local err = nil

    local ok, result = pcall(function()
        return decompile(script)
    end)

    if ok and result and result ~= "" then
        source = result
    else
        err = result or "decompile failed"
    end

    -- Fallback: try LinkedSource
    if not source then
        local linked_ok, linked = pcall(function()
            local ls = script:GetAttribute("LinkedSource")
            if ls then
                return HttpService:JSONDecode(ls)
            end
            return nil
        end)
        if linked_ok and linked and linked.URL then
            local fetch_ok, fetched = pcall(function()
                return HttpService:GetAsync("https://assetdelivery.roproxy.com/v1/asset/?id=" .. linked.URL:match("rbxassetid://(%d+)"))
            end)
            if fetch_ok then
                source = fetched
            end
        end
    end

    if source then
        ScriptCache[cache_key] = source
        return source
    end

    return nil
end

-- ========================================
-- 16. IS LUA SOURCE CONTAINER
-- ========================================

local function is_lua_source_container(instance)
    return instance:IsA("Script")
        or instance:IsA("LocalScript")
        or instance:IsA("ModuleScript")
end

-- ========================================
-- 17. IGNORE PATH (default scripts)
-- ========================================

local DEFAULT_IGNORE_SCRIPTS = {
    "DataModel.CoreGui",
    "DataModel.Players",
    "DataModel.StarterGui.RobloxGui",
    "DataModel.StarterPlayer.StarterCharacterScripts",
    "DataModel.StarterPlayer.StarterPlayerScripts",
    "DataModel.Chat",
    "DataModel.Players.LocalPlayer",
}

local function should_ignore_script(fullName)
    for _, ignore in ipairs(DEFAULT_IGNORE_SCRIPTS) do
        if string_find(fullName, ignore) then
            return true
        end
    end
    return false
end

-- ========================================
-- 18. GET LOCAL PLAYER
-- ========================================

local function get_local_player()
    local lp = game:GetService("Players").LocalPlayer
    if not lp then
        for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
            lp = p
            break
        end
    end
    return lp
end

-- ========================================
-- 19. SAVE HIERARCHY (recursive XML serialization)
-- ========================================

local function write_xml_property(buf, name, value, propType, sharedStrings)
    local tag = XML_TAGS[propType] or XML_TAGS["string"] or "string"

    -- Handle Ref type
    if propType == "Ref" then
        if value and value ~= nil then
            local ref = get_ref(value)
            table.insert(buf, string.format('<Ref name="%s">%s</Ref>', xml_escape(name), ref))
        else
            table.insert(buf, string.format('<Ref name="%s">NULL</Ref>', xml_escape(name)))
        end
        return
    end

    -- Handle SharedString
    if propType == "SharedString" or propType == "BinaryString" then
        if type(value) == "string" and #value > 100 then
            local hash = get_shared_string(value)
            table.insert(buf, string.format('<SharedString name="%s" md5="%s"/>', xml_escape(name), xml_escape(hash)))
            return
        end
    end

    -- Serialize value
    local serialized
    local serialize_func = _G["serialize_" .. propType]
    if serialize_func then
        serialized = serialize_func(value)
    else
        serialized = tostring(value)
    end

    -- Handle ProtectedString for script source
    if propType == "ProtectedString" then
        table.insert(buf, string.format('<ProtectedString name="%s">%s</ProtectedString>',
            xml_escape(name), cdata_wrap(serialized)))
        return
    end

    -- Write XML tag
    table.insert(buf, string.format('<%s name="%s">%s</%s>',
        tag, xml_escape(name), xml_escape(serialized), tag))
end

local function save_instance(instance, buf, refMap, options)
    options = options or {}

    local className = instance.ClassName

    -- Handle non-creatable classes
    local not_creatable = false
    local ok, test = pcall(function()
        local t = Instance.new(className)
        t:Destroy()
    end)
    if not ok and options.save_not_creatable then
        className = "Folder"
        not_creatable = true
    end
    if not ok and not options.save_not_creatable then
        return nil
    end

    -- Check archivable
    if not instance.Archivable and options.ignore_not_archivable then
        return nil
    end

    local ref = get_ref(instance)
    refMap[instance] = ref

    table.insert(buf, string.format('<Item class="%s" referent="%s">', xml_escape(className), ref))
    table.insert(buf, '<Properties>')

    -- Name property
    table.insert(buf, string.format('<string name="Name">%s</string>', xml_escape(instance.Name)))

    -- Get properties for this class
    local allProps = get_inherited_props(className)

    -- Add Parent ref
    if instance.Parent and instance.Parent ~= game then
        local parentRef = refMap[instance.Parent]
        if parentRef then
            table.insert(buf, string.format('<Ref name="Parent">%s</Ref>', parentRef))
        end
    end

    -- Serialize each property
    for propName, propInfo in pairs(allProps) do
        -- Skip exceptions
        local skip = false
        for _, s in ipairs(ClassPropertyExceptions.SkipAll) do
            if propName == s then skip = true; break end
        end
        if skip then continue end

        -- Skip default properties if option set
        if options.ignore_default_properties then
            local ok, val = pcall(function() return instance[propName] end)
            if ok then
                local default = Instance.new(className)
                local ok2, defVal = pcall(function() return default[propName] end)
                default:Destroy()
                if ok2 and tostring(val) == tostring(defVal) then continue end
            end
        end

        local value, propType = read_property(instance, propName, propInfo.Type, options)
        if value ~= nil and propType then
            write_xml_property(buf, propName, value, propType, SharedStrings)
        end
    end

    -- Script source handling
    if is_lua_source_container(instance) then
        local source = decompile_script(instance, options)
        if source then
            table.insert(buf, string.format('<ProtectedString name="Source">%s</ProtectedString>',
                cdata_wrap(source)))
        end

        -- Bytecode if requested
        if options.save_bytecode then
            local bc = save_bytecode(instance)
            if bc then
                table.insert(buf, string.format('<ProtectedString name="Bytecode">%s</ProtectedString>',
                    cdata_wrap(bc)))
            end
        end
    end

    -- NotScriptableFixes for this instance
    for fixKey, fixFunc in pairs(NotScriptableFixes) do
        local fixClass, fixProp = fixKey:match("^(.+)%.(.+)$")
        if fixClass == className then
            local value, propType = fixFunc(instance, nil)
            if value and propType then
                write_xml_property(buf, fixProp, value, propType, SharedStrings)
            end
        end
    end

    table.insert(buf, '</Properties>')

    -- Recurse children
    for _, child in ipairs(instance:GetChildren()) do
        save_instance(child, buf, refMap, options)
    end

    table.insert(buf, '</Item>')
    return ref
end

-- ========================================
-- 20. SAVE EXTRA (NilInstances, etc.)
-- ========================================

local function save_extra_container(name, instances, buf, refMap, options)
    if not instances or #instances == 0 then return end

    local containerRef = get_ref(Instance.new("Folder"))
    table.insert(buf, string.format('<Item class="Folder" referent="%s">', containerRef))
    table.insert(buf, '<Properties>')
    table.insert(buf, string.format('<string name="Name">%s</string>', xml_escape(name)))
    table.insert(buf, '</Properties>')

    for _, instance in ipairs(instances) do
        if instance and instance.Parent == nil then
            save_instance(instance, buf, refMap, options)
        end
    end

    table.insert(buf, '</Item>')
end

-- ========================================
-- 21. MAIN SAVE ORCHESTRATION
-- ========================================

local function synsaveinstance(customOptions)
    customOptions = customOptions or {}

    -- Default options
    local options = {
        mode = customOptions.mode or "full",
        noscripts = customOptions.noscripts or false,
        save_bytecode = customOptions.save_bytecode or false,
        safe_mode = customOptions.safe_mode or false,
        nil_instances = customOptions.nil_instances or false,
        isolate_local_player = customOptions.isolate_local_player or false,
        isolate_players = customOptions.isolate_players or false,
        isolate_starter_player = customOptions.isolate_starter_player or false,
        ignore_not_archivable = customOptions.ignore_not_archivable or true,
        ignore_default_properties = customOptions.ignore_default_properties or true,
        save_not_creatable = customOptions.save_not_creatable or false,
        treat_unions_as_parts = customOptions.treat_unions_as_parts or false,
        decompile_jobless = customOptions.decompile_jobless or false,
        scriptcache = customOptions.scriptcache ~= false,
        timeout = customOptions.timeout or 15,
        readme = customOptions.readme or true,
        show_status = customOptions.show_status ~= false,
        kill_all_scripts = customOptions.kill_all_scripts or false,
        anti_idle = customOptions.anti_idle or false,
        anonymous = customOptions.anonymous or false,
        shutdown_when_done = customOptions.shutdown_when_done or false,
        avoid_file_overwrite = customOptions.avoid_file_overwrite or true,
        shared_string_overwrite = customOptions.shared_string_overwrite or false,
        ignore_shared_strings = customOptions.ignore_shared_strings or false,
        file_path = customOptions.file_path,
        callback = customOptions.callback,
        alternative_writefile = customOptions.alternative_writefile or false,
        remove_player_characters = customOptions.remove_player_characters or false,
        save_cache_interval = customOptions.save_cache_interval or 500,
        decompile_ignore = customOptions.decompile_ignore or {},
        instances_overrides = customOptions.instances_overrides or {},
    }

    -- Validate mode
    if options.mode ~= "full" and options.mode ~= "optimized" and options.mode ~= "scripts" then
        options.mode = "full"
    end

    -- Setup file path
    local placeName = game.Name ~= "Untitled" and game.Name or "Place"
    local placeId = game.PlaceId
    local fileName = string.format("place_%d_%s.rbxlx", placeId, sanitize_filename(placeName))

    if options.file_path then
        fileName = options.file_path
    end

    -- Avoid overwrite
    if options.avoid_file_overwrite and isfile then
        local counter = 1
        while isfile(fileName) do
            local base = fileName:match("(.+)%..+$") or fileName
            local ext = fileName:match("%.([^%.]+)$") or "rbxlx"
            fileName = string.format("%s_%d.%s", base, counter, ext)
            counter = counter + 1
        end
    end

    -- Status GUI
    local statusGui = nil
    local statusLabel = nil
    if options.show_status then
        local parent = gethui and gethui() or game:GetService("CoreGui")
        statusGui = Instance.new("ScreenGui")
        statusGui.Name = "SSI++_" .. tostring(math.random(100000, 999999))
        statusGui.DisplayOrder = 2000000000
        statusGui.ResetOnSpawn = false

        statusLabel = Instance.new("TextLabel")
        statusLabel.Size = UDim2.new(0, 300, 0, 50)
        statusLabel.Position = UDim2.new(0.5, -150, 0.9, -25)
        statusLabel.BackgroundTransparency = 0.3
        statusLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        statusLabel.TextSize = 16
        statusLabel.Font = Enum.Font.GothamBold
        statusLabel.Text = "SSI++: Saving..."
        statusLabel.BorderSizePixel = 0
        statusLabel.Parent = statusGui

        protectgui(statusGui)
        statusGui.Parent = parent
    end

    local function update_status(text, color)
        if statusLabel then
            statusLabel.Text = text
            if color then statusLabel.TextColor3 = color end
        end
    end

    -- Spinner
    local spinner_chars = { "|", "/", "-", "\\" }
    local spinner_idx = 1
    local function spinner()
        local c = spinner_chars[spinner_idx]
        spinner_idx = spinner_idx % #spinner_chars + 1
        return c
    end

    -- Anti-idle
    local antiIdleConn = nil
    if options.anti_idle then
        antiIdleConn = RunService.Heartbeat:Connect(function()
            if Stats.Value then
                local network = Stats:FindFirstChild("Network")
                if network then
                    local ping = network:FindFirstChild("ServerStatsItem")
                    if ping then
                        local data = ping:FindFirstChild("DataReceive")
                        if data then data.Value = data.Value + 1 end
                    end
                end
            end
        end)
    end

    -- SafeMode
    if options.safe_mode then
        update_status("[SAFEMODE] Saving.. Do NOT leave [WARNING] LVL7 Executor RECOMMENDED", Color3.fromRGB(255, 100, 100))
        if setthreadidentity then
            setthreadidentity(2)
        end
        GuiService:DisconnectErrorPrompt()
        RunService:Set3dRenderingEnabled(false)
    end

    -- KillAllScripts
    if options.kill_all_scripts then
        local is_closure_check = isexecutorclosure or checkclosure or isourclosure
        local reg = getreg and getreg() or getregistry and getregistry()
        if reg and is_closure_check then
            for _, v in ipairs(reg) do
                if type(v) == "function" and islclosure and islclosure(v) and not is_closure_check(v) then
                    local ok, env = pcall(function() return getfenv(v) end)
                    if ok and env and env.script then
                        if hookfunction then
                            hookfunction(v, function() end)
                        end
                    end
                end
            end
            -- Kill threads
            local threads = getallthreads and getallthreads() or {}
            for _, thread in ipairs(threads) do
                local ok, env = pcall(function() return getfenv(thread) end)
                if ok and env and env.script and not is_closure_check(env.script) then
                    coroutine.close(thread)
                end
            end
        end
    end

    -- Fetch API classes
    pcall(fetch_api_classes)

    -- Start save
    local startTime = tick()
    local buf = {}
    local refMap = {}
    local scriptCount = 0
    local failCount = 0

    update_status("SSI++: Scanning game" .. spinner())

    -- Write header
    table.insert(buf, '<?xml version="1.0" encoding="UTF-8"?>')
    table.insert(buf, string.format('<roblox xml:schemaversion="4" xmlns:xmime="http://www.w3.org/2005/05/xmlmime">'))

    -- Save game hierarchy
    if options.mode == "full" or options.mode == "optimized" then
        -- StarterPlayer handling
        if options.isolate_starter_player then
            local sp = game:GetService("StarterPlayer")
            if sp then
                save_instance(sp, buf, refMap, options)
            end
        end

        -- Main hierarchy
        for _, child in ipairs(game:GetChildren()) do
            if child ~= game:GetService("Players") or not options.isolate_local_player then
                if options.remove_player_characters and child:IsA("Model") then
                    local player = game:GetService("Players"):GetPlayerFromCharacter(child)
                    if player then continue end
                end
                save_instance(child, buf, refMap, options)
            end
        end

        -- LocalPlayer isolation
        if options.isolate_local_player then
            local lp = get_local_player()
            if lp then
                local lpRef = get_ref(lp)
                refMap[lp] = lpRef
                save_instance(lp, buf, refMap, options)
            end
        end

        -- Players
        if options.isolate_players then
            local players = game:GetService("Players")
            for _, player in ipairs(players:GetPlayers()) do
                if player ~= game:GetService("Players").LocalPlayer or not options.isolate_local_player then
                    save_instance(player, buf, refMap, options)
                end
            end
        end

        -- NilInstances
        if options.nil_instances then
            local nilInstances = getnilinstances()
            update_status("SSI++: Saving nil instances" .. spinner())
            save_extra_container("NilInstances", nilInstances, buf, refMap, options)
        end
    end

    -- Scripts-only mode
    if options.mode == "scripts" then
        table.insert(buf, '<Item class="Folder" referent="' .. get_ref(Instance.new("Folder")) .. '">')
        table.insert(buf, '<Properties>')
        table.insert(buf, '<string name="Name">Scripts</string>')
        table.insert(buf, '</Properties>')

        local function find_scripts(parent)
            for _, obj in ipairs(parent:GetDescendants()) do
                if is_lua_source_container(obj) then
                    if not should_ignore_script(obj:GetFullName()) then
                        save_instance(obj, buf, refMap, options)
                    end
                end
            end
        end
        find_scripts(game)
        table.insert(buf, '</Item>')
    end

    -- SharedStrings
    if not options.ignore_shared_strings and next(SharedStrings) then
        table.insert(buf, '<SharedStrings>')
        for hash, content in pairs(SharedStrings) do
            table.insert(buf, string.format('<SharedString md5="%s">', xml_escape(hash)))
            table.insert(buf, cdata_wrap(content))
            table.insert(buf, '</SharedString>')
        end
        table.insert(buf, '</SharedStrings>')
    end

    -- Close root
    table.insert(buf, '</roblox>')

    update_status("SSI++: Writing file" .. spinner())

    -- Build final string
    local totalStr = table.concat(buf, "\n")
    local totalSize = #totalStr

    -- File writing
    local writeSuccess = false
    if options.callback then
        options.callback(totalStr, 1, totalSize)
        writeSuccess = true
    elseif options.alternative_writefile and appendfile then
        -- Chunked writing for Celery
        local chunkSize = 4 * 1024 * 1024 -- 4MB
        local offset = 1
        while offset <= totalSize do
            local chunk = totalStr:sub(offset, offset + chunkSize - 1)
            if offset == 1 then
                writefile(fileName, chunk)
            else
                appendfile(fileName, chunk)
            end
            offset = offset + chunkSize
        end
        writeSuccess = true
    elseif writefile then
        writefile(fileName, totalStr)
        writeSuccess = true
    elseif setclipboard then
        setclipboard(totalStr)
        writeSuccess = true
    end

    local endTime = tick()
    local elapsed = math.floor((endTime - startTime) * 1000)
    local sizeMB = string.format("%.2f", totalSize / (1024 * 1024))

    -- Status
    if writeSuccess then
        update_status(string.format("Saved! Time: %dms; Size: %s MB", elapsed, sizeMB), Color3.fromRGB(100, 255, 100))
        print(string.format("[SSI++] %s (%s MB in %dms)", fileName, sizeMB, elapsed))
    else
        update_status("Failed! Check F9 console", Color3.fromRGB(255, 100, 100))
        print("[SSI++] Failed to write file")
    end

    -- README
    if options.readme and writefile then
        local readme = string.format([[
-- SSI++ Save Info
-- Game: %s
-- PlaceId: %d
-- Executor: %s
-- Mode: %s
-- Date: %s
-- Size: %s MB
-- Scripts decompiled: %d
-- Scripts failed: %d
]],
            game.Name, placeId, EXECUTOR_NAME, options.mode, os.date(), sizeMB, scriptCount, failCount
        )
        writefile(fileName:gsub("%.rbxlx$", ".txt"), readme)
    end

    -- Cleanup
    if antiIdleConn then antiIdleConn:Disconnect() end
    if statusGui then
        delay(3, function()
            if statusGui and statusGui.Parent then
                statusGui:Destroy()
            end
        end)
    end

    -- Shutdown
    if options.shutdown_when_done then
        delay(2, function()
            game:Shutdown()
        end)
    end

    return {
        success = writeSuccess,
        fileName = fileName,
        size = totalSize,
        elapsed = elapsed,
    }
end

-- ========================================
-- 22. EXPORT
-- ========================================

return synsaveinstance
