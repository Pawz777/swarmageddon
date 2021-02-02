require "util"
require "ammo"

local attack = defines.command.attack
local attack_area = defines.command.attack_area
local compound = defines.command.compound
local logical_or = defines.compound_command.logical_or
local max_deaths = 25

script.on_init(
    function()
        setup()
    end
)
script.on_configuration_changed(
    function()
        setup()
    end
)

script.on_event(
    defines.events.on_entity_died,
    function(event)
        queueEnemiesOnDeath(event.entity, event.cause)
    end
)

script.on_event(
    defines.events.on_tick,
    function(event)
        spawnEnemiesPerTick()
        local enabledMitigation = settings.startup["enable-mitigation"].value
        if(enableMitigation) then
            updatePlayerUnitsKilled(event)
        end
    end
)

-- Sets up list of units to spawn
function setup()
    max_deaths = settings.startup["player-dying-mitigation"].value
    if not global.swarmQueue then
        global.swarmQueue = {}
    end
    if not global.swarmDefinitions then
        global.swarmDefinitions = {}
    end

    if not global.swarmKills then
        global.swarmKills = 0
    end

    local setupTable = {}

    for k, unit in pairs(game.entity_prototypes) do
        if (unit.type == "unit" and unit.subgroup.name == "enemies") then
            -- Find the ammo type, get the damage from it, check the rate of fire (cooldown)
            if (unit.attack_parameters and unit.attack_parameters.ammo_type) then
                local ammo_type = unit.attack_parameters.ammo_type
                local action = ammo_type.action
                local damageType = Ammo.get_damage_type_from_actionset(action)
                local damage = 0
                local type = ""
                for k, v in pairs(damageType) do
                    type = k
                    damage = v
                    break
                end
                local cat = "default"
                if (string.find(unit.name, "rampant")) then
                    i, j = string.find(unit.name, "-biter")
                    if j ~= nil then
                        cat = string.sub(unit.name, 0, j)
                    end
                    i, j = string.find(unit.name, "-spitter")
                    if j ~= nil then
                        cat = string.sub(unit.name, 0, j)
                    end
                elseif (string.find(unit.name, "creative")) then
                    cat = "creative"
                else
                    i, j = string.find(unit.name, "-biter")
                    if j ~= nil then
                        cat = "biter"
                    end
                    i, j = string.find(unit.name, "-spitter")
                    if j ~= nil then
                        cat = "spitter"
                    end
                end

                --Need a table with an entry for each
                table.insert(
                    setupTable,
                    {
                        name = unit.name,
                        max_health = unit.max_health,
                        damage = damage,
                        damage_type = type,
                        category = cat
                    }
                )
            end
        end
    end

    -- sort by type and then reverse max hp
    table.sort(
        setupTable,
        function(a, b)
            if (a.category == b.category) then
                return a.max_health > b.max_health
            else
                return a.category < b.category
            end
        end
    )
    for i, unit in ipairs(setupTable) do
        local hpToUse = unit.max_health / 2
        local spawntable = {}
        for k, child in ipairs(setupTable) do
            if (child.category == unit.category and child.max_health < hpToUse) then
                while (hpToUse > child.max_health) do
                    if (spawntable[child.name]) then
                        spawntable[child.name] = spawntable[child.name] + 1
                    else
                        spawntable[child.name] = 1
                    end
                    hpToUse = hpToUse - child.max_health
                end
            end
        end

        global.swarmDefinitions[unit.name] = spawntable
    end
end

-- Track the number of player units getting killed

function updatePlayerUnitsKilled(event)
    local ticksWait = 60 -- change this to change update speed
    local timer = event.tick % ticksWait
    if (timer == 0) then
        local stats = game.forces["enemy"].kill_count_statistics

        local deathsInTheLastMinute = 0
        for k, v in pairs(stats.input_counts) do
            if (not string.find(k, ("tree")) and not string.find(k, ("wall"))) then
                local deaths =
                    stats.get_flow_count {
                    name = k,
                    precision_index = defines.flow_precision_index.one_minute,
                    input = true
                }
                deathsInTheLastMinute = deathsInTheLastMinute + (deaths or 0)
            end
        end
        global.swarmKills = deathsInTheLastMinute or 0
    end
end

-- Add enemies to the queue to be spawned
function queueEnemiesOnDeath(deadUnit, cause)
    local evoFactor = game.forces["enemy"].evolution_factor
    local name = deadUnit.name

    if (deadUnit.type == "unit-spawner") then
        if (evoFactor < 0.3) then
            name = "medium-biter"
        end
        if (evoFactor > 0.3 and evoFactor < 0.7) then
            name = "big-biter"
        end
        if (evoFactor > 0.7) then
            name = "behemoth-biter"
        end
    end

    local spawn = global.swarmDefinitions[name]
    if (spawn) then
        for k, v in pairs(spawn) do
            numberOfSpawns = round(v / 2 + (v * evoFactor))
            -- modify number of spawns if player is getting smashed
            if (global.swarmKills and global.swarmKills > 0) then
                adjustmentFactor = global.swarmKills / max_deaths
                if (adjustmentFactor > 1) then
                    adjustmentFactor = 1
                end
                --100% adjustment means no spawns
                numberOfSpawns = numberOfSpawns - (numberOfSpawns * adjustmentFactor)
            end

            if numberOfSpawns > 0 then
                for i = 1, numberOfSpawns do
                    table.insert(
                        global.swarmQueue,
                        {
                            surface = deadUnit.surface,
                            name = k,
                            position = deadUnit.position,
                            force = deadUnit.force,
                            cause = cause
                        }
                    )
                end
            end
        end
    end
end

-- Check the global queue of enemies to spawn this tick, and spawn them
function spawnEnemiesPerTick()
    if #(global.swarmQueue) > 0 then
        local spawnstodo = math.min(settings.startup["spawns-per-tick"].value, #(global.swarmQueue))
        local recentDeaths = global.swarmKills

        for i = 1, spawnstodo do
            newEnemy = table.remove(global.swarmQueue, 1)
            local subEnemyPosition = newEnemy.surface.find_non_colliding_position(newEnemy.name, newEnemy.position, 4, 0.5)
            if subEnemyPosition then
                local spawned = newEnemy.surface.create_entity({name = newEnemy.name, position = subEnemyPosition, force = newEnemy.force})
                if spawned and newEnemy.command and spawned.valid then
                    local cause = newEnemy.cause
                    local position = newEnemy.position
                    local command = create_attack_command(position, cause)
                    spawned.set_command(newEnemy.command)
                end
            end
        end
        --After all the spawns we tried process, we clear the queue
        --This prevents mass destruction weapons (nukes) from feeling
        --useless
        global.swarmQueue = {}
    end
end

--Create an attack command, either on the target, or attack anything within a radius
function create_attack_command(position, target)
    local command = {type = attack_area, destination = position, radius = 20}
    if target and target.valid then
        command = {
            type = compound,
            structure_type = logical_or,
            commands = {
                {type = attack, target = target},
                command
            }
        }
    end
    return command
end

--- Round a number.
function round(x)
    return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
end
