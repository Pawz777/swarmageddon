require "util"
require "ammo"

local attack = defines.command.attack
local attack_area = defines.command.attack_area
local compound = defines.command.compound
local logical_or = defines.compound_command.logical_or

local LOGGER = require("__stdlib__/stdlib/misc/logger").new("Swarmageddon", "swarmageddon", true)

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
        queueEnemies(event.entity, event.cause)
    end
)

script.on_event(
    defines.events.on_tick,
    function(event)
        spawnEnemies()
    end
)

-- Sets up list of units to spawn
function setup()
    if not global.swarmQueue then
        global.swarmQueue = {}
    end
    if not global.swarmDefinitions then
        global.swarmDefinitions = {}
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

-- Add enemies to the queue to be spawned
function queueEnemies(enemy, cause)
    local first_player = game.players[1]
    local evoFactor = game.forces["enemy"].evolution_factor
    local name = enemy.name
    if (enemy.type == "unit-spawner") then
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
            if numberOfSpawns > 0 then
                for i = 1, numberOfSpawns do
                    table.insert(
                        global.swarmQueue,
                        {
                            surface = enemy.surface,
                            name = k,
                            position = enemy.position,
                            force = enemy.force,
                            cause = cause
                        }
                    )
                end
            end
        end
    end
end

-- Check the global queue of enemies to spawn this tick, and spawn them
function spawnEnemies()
    if #(global.swarmQueue) > 0 then
        local spawnstodo = math.min(settings.global["spawns-per-tick"].value, #(global.swarmQueue))
        for i = 1, spawnstodo do
            newEnemy = table.remove(global.swarmQueue, 1)
            local subEnemyPosition =
                newEnemy.surface.find_non_colliding_position(newEnemy.name, newEnemy.position, 4, 0.5)
            if subEnemyPosition then
                local spawned =
                    newEnemy.surface.create_entity(
                    {name = newEnemy.name, position = subEnemyPosition, force = newEnemy.force}
                )
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
