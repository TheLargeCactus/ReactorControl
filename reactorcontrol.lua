component = require("component")
term = require("term")
event = require("event")
keyboard = require("keyboard")
colors = require("colors")
thread = require("thread")

turbines = component.list("br_turbine")
turbineMaxOutputs = {}
capacitor = component.capacitor_bank
reactor = component.br_reactor
gpu = component.gpu

reactorPercentProduction = 0
turbineMaxProduction = 0

local loo = true

function isActive(bool)
    if bool then
        return "Active"
    else
        return "Inactive"
    end
end

function updateScreen()
    local index = 0
    for turbine, _ in pairs(turbines) do
        print("Turbine " .. index .. " | Status: " .. isActive(component.invoke(turbine, "getActive")) .. " | Power Production: " .. component.invoke(turbine, "getEnergyProducedLastTick") .. "RF/t")
        index = index + 1
    end

    print("Power Consumption: " .. capacitor.getAverageOutputPerTick() .. "RF/t | Power Production: " .. totalEnergyProduced() .. "RF/t")
end

function totalEnergyProduced()
    local total = 0
    
    for _, turbine in pairs(activeTurbines) do
        total = total + component.invoke(turbine, "getEnergyProducedLastTick")
    end
    
    return total
end

function engageSingleTurbine()
    print("Engaging Turbine")
    
    for turbine, _ in pairs(turbines) do
        if not component.invoke(turbine, "getActive") then 
            component.invoke(turbine, "setActive", true)
            component.invoke(turbine, "setInductorEngaged", true)
            return
        end
    end
end

function disengageSingleTurbine()
    print("Disengaging Turbine")
    
    for turbine, _ in pairs(turbines) do
        if component.invoke(turbine, "getActive") then 
            component.invoke(turbine, "setActive", false)
            component.invoke(turbine, "setInductorEngaged", false)
            return
        end
    end
end

function tuneReactor()
    reactor.setAllControlRodLevels(0)
    
    while not reactorStable() do
        --nothing
    end

    local requiredSteam = reactor.getHotFluidProducedLastTick()

    --set control rod levels
    local reactorRodRemovalLevel = math.ceil(requiredSteam / reactorPercentProduction)

    reactor.setAllControlRodLevels(100 - reactorRodRemovalLevel)

    return


end

function tuneTurbine(address, index)
    print("Tuning Turbine " .. index)
    component.invoke(address, "setActive",true)
    component.invoke(address, "setInductorEngaged",false)
    component.invoke(address, "setFluidFlowRateMax", 2000)

    local speed = 0
    while speed < 1750 or speed > 1800 do
        speed = component.invoke(address, "getRotorSpeed")

        if speed < 1750 then
            component.invoke(address, "setInductorEngaged", false)
        end

        if speed > 1800 then
            component.invoke(address, "setInductorEngaged", true)
        end
    end

    component.invoke(address, "setInductorEngaged", true)
    
    turbineMaxOutputs[index] = component.invoke(address, "getEnergyProducedLastTick")
    print("Finished Tuning Turbine " .. index)
    return
end


function initialTune()
    print("Initial Tune in Progress")
    print("Initial Tuning Reactor")
    --calculate fluid production per percentage
    reactor.setAllControlRodLevels(99)
    local turbineThreads = {}
    
    while not reactorStable() do
        --nothing
    end

    reactorPercentProduction = reactor.getHotFluidProducedLastTick()

    reactor.setAllControlRodLevels(0)

    print("Initial Tuning Turbines")
    local index = 1
    for address, _ in pairs(turbines) do
        table.insert(turbineThreads, thread.create(tuneTurbine,address,index))
        index = index + 1
    end
    

    thread.waitForAll(turbineThreads)

    

    print("Finished Initial Tuning Turbines")

    tuneReactor()

    print("Finished Initial Tuning")
    return
end

function quit(_,_,_,ch)
    if ch == keyboard.keys.b then
        loo = false
    end
end

function reactorStable()
    local last = reactor.getHotFluidProducedLastTick()
    local current = reactor.getHotFluidProducedLastTick()

    return math.abs(current - last) < 2
end
    


function countEntries(tabl)
    local count = 0

    for _,_ in pairs(tabl) do
        count = count + 1
    end

    return count
end

--main
event.register("key_down", quit)

initialTune()

while loo do
    
    activeTurbines = {}
    
    for turbine,_ in pairs(turbines) do
        if component.invoke(turbine, "getActive") then
            table.insert(activeTurbines, turbine)
        end
    end
    
    if capacitor.getAverageOutputPerTick() < totalEnergyProduced() then
        if capacitor.getAverageOutputPerTick() > totalEnergyProduced(activeTurbines) - component.invoke(activeTurbines[1],"getEnergyProducedLastTick") then
            --do nothing
        else
            disengageSingleTurbine()
            tuneReactor()
        end
    end
    
    if capacitor.getAverageOutputPerTick() > totalEnergyProduced(activeTurbines) and countEntries(activeTurbines) < countEntries(turbines) then
        engageSingleTurbine()
        tuneReactor()
    end
    
    
    
    updateScreen()
    
    
    os.sleep(5)
    term.clear()
end	