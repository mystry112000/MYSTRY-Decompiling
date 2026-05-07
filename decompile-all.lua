-- Universal Roblox Script Decompiler
-- Works with most executors: Solara, Fluxus, Delta, etc.
-- Dumps all LocalScripts and ModuleScripts to readable Lua

local success, result = pcall(function()
    print("[Decompiler] Starting universal script decompiler...")

    -- Detect available decompile function
    local function getDecompiler()
        if decompile then
            print("[Decompiler] Using: decompile()")
            return decompile
        elseif dump_scripts or dumpscript then
            print("[Decompiler] Using: dump_scripts()")
            return dump_scripts or dumpscript
        elseif getsenv then
            print("[Decompiler] Using: getsenv()")
            return function(script)
                local env = getsenv(script)
                return env and tostring(env) or "-- No source available"
            end
        else
            return nil
        end
    end

    local decompiler = getDecompiler()
    if not decompiler then
        return error("[Decompiler] No decompiler API found in this executor")
    end

    -- Collect all scripts
    local scripts = {}
    local function collectScripts(parent)
        for _, obj in ipairs(parent:GetDescendants()) do
            if obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
                table.insert(scripts, obj)
            end
        end
    end

    print("[Decompiler] Scanning game scripts...")
    collectScripts(game)

    print(string.format("[Decompiler] Found %d scripts", #scripts))

    -- Results output
    local output = "-- Decompiled Scripts\n-- Game: " .. game.Name .. "\n-- PlaceId: " .. game.PlaceId .. "\n-- Date: " .. tostring(os.date()) .. "\n\n"
    local count = 0
    local failed = 0

    for _, script in ipairs(scripts) do
        local name = script:GetFullName()
        output = output .. "-- ========================================\n"
        output = output .. "-- Script: " .. name .. "\n"
        output = output .. "-- Type: " .. script.ClassName .. "\n"
        output = output .. "-- ========================================\n"

        local success, source = pcall(function()
            return decompiler(script)
        end)

        if success and source and source ~= "" then
            output = output .. tostring(source) .. "\n\n"
            count = count + 1
            print(string.format("[OK] %s", name))
        else
            output = output .. "-- Failed to decompile (protected/empty)\n\n"
            failed = failed + 1
            print(string.format("[FAIL] %s", name))
        end
    end

    output = output .. string.format("\n-- Total: %d scripts | Success: %d | Failed: %d\n", #scripts, count, failed)

    -- Save using executor writefile if available
    if writefile then
        local filename = string.format("decompiled_%s_%s.lua", game.PlaceId, game.Name:gsub("[^%w%s]", ""))
        writefile(filename, output)
        print(string.format("[Decompiler] Saved to: %s", filename))
    else
        -- Fallback: set to clipboard or print
        if setclipboard then
            setclipboard(output)
            print("[Decompiler] Copied to clipboard!")
        else
            print(output)
        end
    end

    print(string.format("[Decompiler] Done. %d decompiled, %d failed.", count, failed))
end)

if not success then
    print("[Decompiler] Error: " .. tostring(result))
end
