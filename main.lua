local chestSide = "minecraft:chest_8"
local itemsPerPage = 17
local speaker = peripheral.find("speaker")

local depositChest = peripheral.wrap(chestSide)
if not depositChest then
    error("No chest found on " .. chestSide)
end


local usageStats = {}

local function loadStats()
    if fs.exists("stats") then
        local f = fs.open("stats", "r")
        local content = f.readAll()
        f.close()
        usageStats = textutils.unserialize(content) or {}
    end
end

local function saveStats()
    local f = fs.open("stats", "w")
    f.write(textutils.serialize(usageStats))
    f.close()
end

loadStats()

local inventory = {}
local filtered = {}
local searchStr = ""
local selectedIdx = 1
local scrollOffset = 0
local running = true
local status = ""
local statuscol = colors.white

local function evaluateExpression(expr)
    expr = expr:gsub("%s+", "")

    if not expr:match("^[%d%+%-%*/%%%^%(%)%.]+$") then
        return nil
    end

    local func = load("return " .. expr, nil, "t", {})
    if not func then
        return nil
    end

    local ok, result = pcall(func)
    if not ok or type(result) ~= "number" then
        return nil
    end

    return math.floor(result)
end

local function drawStatus(msg, color)
    term.setBackgroundColor(colors.gray)
    term.setCursorPos(33,19) 
    term.write("                              ") 
    term.setCursorPos(33,19)
    term.setTextColor(colors.lightGray)
    term.write(" | ")
    term.setTextColor(color)
    term.write(msg)
end

local function getStorage()
    local storage = {
        depositable = {},
        withdrawOnly = {}
    }

    local names = peripheral.getNames()

    for _, name in ipairs(names) do
        if name ~= "back" and name ~= "right" and name ~= chestSide then
            local pType = peripheral.getType(name)

            -- Barrels: withdraw ONLY
            if pType == "minecraft:barrel" or pType == "barrel" then
                table.insert(storage.withdrawOnly, name)

            -- Normal storage
            elseif pType == "minecraft:chest"
                or pType == "inventory" then
                table.insert(storage.depositable, name)
            end
        end
    end

    return storage
end

local function refreshInventory()
    drawStatus("Syncing...", colors.orange)
    saveStats()

    local tempInv = {}
    local storage = getStorage()

    -- Scan BOTH normal storage and withdraw-only barrels
    local allStorage = {}

    for _, name in ipairs(storage.depositable) do
        table.insert(allStorage, name)
    end

    for _, name in ipairs(storage.withdrawOnly) do
        table.insert(allStorage, name)
    end

    for _, name in ipairs(allStorage) do
        local remote = peripheral.wrap(name)

        if remote then
            local items = remote.list()

            for slot, item in pairs(items) do
                local key = item.name

                if not tempInv[key] then
                    tempInv[key] = {
                        name = item.name,
                        count = 0,
                        locations = {}
                    }
                end

                tempInv[key].count = tempInv[key].count + item.count

                table.insert(tempInv[key].locations, {
                    chest = name,
                    slot = slot,
                    count = item.count
                })
            end
        end
    end

    inventory = {}

    for _, data in pairs(tempInv) do
        table.insert(inventory, data)
    end

    table.sort(inventory, function(a, b)
        local countA = usageStats[a.name] or 0
        local countB = usageStats[b.name] or 0

        if countA ~= countB then
            return countA > countB
        end

        return a.name < b.name
    end)

    drawStatus("Sync Complete!", colors.green)
    os.sleep(0.5)
    drawStatus("", colors.black)
end

local function updateFilter()
    filtered = {}
    for _, item in ipairs(inventory) do
        local displayName = item.name:gsub("^.-:", ""):lower()
        if displayName:find(searchStr:lower()) then
            table.insert(filtered, item)
        end
    end
    selectedIdx = 1
end

local function depositItems()
    drawStatus("Depositing items...", colors.yellow)

    if speaker then
        speaker.playNote("bell")
    end

    local items = depositChest.list()
    local storage = getStorage()

    -- ONLY deposit into approved storage
    for slot, item in pairs(items) do
        for _, sName in ipairs(storage.depositable) do
            local success = depositChest.pushItems(sName, slot)

            if success > 0 then
                break
            end
        end
    end

    refreshInventory()
    updateFilter()
end

local function withdrawItem(itemData, amount)
    local remaining = amount
    
    usageStats[itemData.name] = (usageStats[itemData.name] or 0) + 1
    
    for i = #itemData.locations, 1, -1 do
        if remaining <= 0 then break end
        
        local loc = itemData.locations[i]
        local toMove = math.min(remaining, loc.count)
        local moved = peripheral.call(loc.chest, "pushItems", peripheral.getName(depositChest), loc.slot, toMove)
        
        if moved > 0 then
            remaining = remaining - moved
            loc.count = loc.count - moved
            itemData.count = itemData.count - moved
            if loc.count <= 0 then table.remove(itemData.locations, i) end
        end
    end
    
    if itemData.count <= 0 then
        for i, item in ipairs(inventory) do
            if item == itemData then table.remove(inventory, i) break end
        end
    end
    searchStr = ""
    updateFilter()
end


local function draw()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" Storage Manager | Search: " .. searchStr .. "_")

    for i = 1, itemsPerPage do
        local idx = i + scrollOffset
        term.setCursorPos(1, i + 1)
        
        if filtered[idx] then
            if idx == selectedIdx then
                term.setBackgroundColor(colors.blue)
                term.setTextColor(colors.white)
            else
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.lightGray)
            end
            term.clearLine()
            local displayName = filtered[idx].name:gsub("^.-:", ""):gsub("_", " ")
            local line = string.format(" %-24s | %d", displayName, filtered[idx].count)
            term.write(line)
        else
            term.setBackgroundColor(colors.black)
            term.clearLine()
        end
    end

    term.setCursorPos(1, 19)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" [Tab] Deposit  [Enter] Withdraw")
end

local function getAmountInput()
    local w, h = term.getSize()
    local win = window.create(term.current(), 1, 19, w, 1)

    local input = ""

    while true do
        win.setBackgroundColor(colors.gray)
        win.setTextColor(colors.white)
        win.clear()

        win.setCursorPos(1, 1)
        win.write(" Amount: " .. input)

        local preview = nil

        if input:match("[%+%-%*/%%%^%(%)]+") then
            preview = evaluateExpression(input)
        end

        if preview then
            local previewText = " = " .. tostring(preview)
            local x = w - #previewText + 1

            if x > #(" Amount: " .. input) then
                win.setCursorPos(x, 1)
                win.setTextColor(colors.lime)
                win.write(previewText)
            end
        end

        local event, p1 = os.pullEvent()

        if event == "char" then
            input = input .. p1

        elseif event == "key" then
            if p1 == keys.backspace then
                input = input:sub(1, -2)

            elseif p1 == keys.enter then
                if input == "a" then
                    return math.huge
                end

                local result = evaluateExpression(input)
                return result or 0
            end
        end
    end
end

refreshInventory()
updateFilter()

while running do
    draw()
    local event, key = os.pullEvent()
    
    if redstone.getInput("top") then
        depositItems()
    end
    
    if event == "key" then
        if key == keys.up then
            selectedIdx = math.max(1, selectedIdx - 1)
            if selectedIdx <= scrollOffset then scrollOffset = selectedIdx - 1 end
        elseif key == keys.down then
            selectedIdx = math.min(#filtered, selectedIdx + 1)
            if selectedIdx > scrollOffset + itemsPerPage then scrollOffset = selectedIdx - itemsPerPage end
        elseif key == keys.enter then
            if filtered[selectedIdx] then
                local amt = getAmountInput()
                if amt > 0 then withdrawItem(filtered[selectedIdx], amt) end
            end
        elseif key == keys.backspace then
            searchStr = searchStr:sub(1, -2)
            updateFilter()
        elseif key == keys.tab then
            depositItems()
        elseif key == keys.period then
            running = false
        end
    elseif event == "char" then
        searchStr = searchStr .. key:lower()
        updateFilter()
    end
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
