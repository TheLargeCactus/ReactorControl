--Reactor Control Program
--Made for Extreme Reactors/Computronics/OpenComputers
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

    print("Power Consumption: " .. capacitor.getAverageOutputPerTick() .. "RF/t | Power Production: " .. totalEnergyProduced() .. "RF/t | Energy Storage: " .. getEnergyPercent() .. "%" )
end

function getEnergyPercent()
    return capacitor.getEnergyStored() / capacitor.getMaxEnergyStored() * 100
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
    print ("Tuning Reactor")
    
    local active = 0
    for address, _ in pairs(turbines) do
        if component.invoke(address, "getActive") then
            active = active + 1
        end
    end

    local requiredSteam = 2000 * active

    print("Maximum Steam Required: " .. requiredSteam .. "mB | Steam production per fuel rod level: " .. reactorPercentProduction .. "mB")

    --set control rod levels
    local reactorRodRemovalLevel = math.ceil(requiredSteam / reactorPercentProduction)

    reactor.setAllControlRodLevels(100 - reactorRodRemovalLevel)

    print("Setting Control Rods to " .. 100 - reactorRodRemovalLevel .. "% inserted")
    return

    print("Finished Tuning Reactor")
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

    print("Finished Initial Tuning Reactor")
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
    local last = reactor.getFuelTemperature()
    os.sleep(1)
    local current = reactor.getFuelTemperature()

    return math.abs(current-last) < 0.5
    
end

function countEntries(tabl)
    local count = 0

    for _,_ in pairs(tabl) do
        count = count + 1
    end

    return count
end

function checkOverride()
    if capacitor.getEnergyStored() < capacitor.getMaxEnergyStored() * 0.3 then
        override = true
    end

    if capacitor.getEnergyStored() > capacitor.getMaxEnergyStored() * 0.9 then
        override = false
    end
end

function engageAllTurbines()
    for a,i in turbines do
        component.invoke(a, "setActive",true)
        component.invoke(a, "setInductorEngaged", true)
    end

    tuneReactor()
end

--main
event.register("key_down", quit)

initialTune()
override = false

while loo do
    
    activeTurbines = {}
    
    for turbine,_ in pairs(turbines) do
        if component.invoke(turbine, "getActive") then
            table.insert(activeTurbines, turbine)
        end
    end
    
    checkOverride()

    if not override then
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
    else
        engageAllTurbines()
        print("Override Engaged")
    end
    
    
    updateScreen()
    
    
    os.sleep(5)
    term.clear()
end	
