--[[
Copyright 2018 "Kovus" <kovus@soulless.wtf>

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
may be used to endorse or promote products derived from this software without
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

	Ammo.lua

Functionality related to the handling of Ammo for Fill4Me.

Modified to load the damage into a table and record the damage type as well.
--]]
Ammo = {}

--
-- General-purpose Ammo functions (the ones you probably want to call)

-- Ammo Damage type
--
function Ammo.get_damage_type_from_action(action)
    local damageType = {}
    if action.action_delivery then
        for _, ad in pairs(action.action_delivery) do
            local dt = Ammo.get_action_delivery_damage_type(ad)
            mergeDamageTypes(damageType, dt)
        end
    end
    return damageType
end

function Ammo.get_action_delivery_damage_type(action_delivery)
    local damageType = {}
    if action_delivery.type == "instant" then
        if action_delivery.target_effects then
            for _, te in pairs(action_delivery.target_effects) do
                if te.action then
                    mergeDamageTypes(damageType, Ammo.get_damage_type_from_actionset(te.action))
                end
                if te.type == "damage" then
                    local d = {}
                    d[te.damage.type] = te.damage.amount
                    mergeDamageTypes(damageType, d)
                end
                if te.type == "create-entity" and te.entity_name then
                    mergeDamageTypes(damageType, Ammo.get_entity_attack_damage_type(te.entity_name))
                end
            end
        end
    elseif action_delivery.projectile then
        mergeDamageTypes(damageType, Ammo.get_entity_attack_damage_type(action_delivery.projectile))
    elseif action_delivery.stream then
        mergeDamageTypes(damageType, Ammo.get_entity_attack_damage_type(action_delivery.stream))
    end
    return damageType
end

function Ammo.get_damage_type_from_actionset(actionset)
    local damageType = {}
    for _, act in pairs(actionset) do
        d = {}
        mergeDamageTypes(d, Ammo.get_damage_type_from_action(act))
        if d then
            for k, type in pairs(d) do
                type = type * act.repeat_count
            end
            mergeDamageTypes(damageType, d)
        end
    end
    return damageType
end

function Ammo.get_entity_attack_damage_type(entityName)
    local ent = game.entity_prototypes[entityName]
    local damageType = {}

    if ent then
        if ent.attack_result then
            mergeDamageTypes(damageType, Ammo.get_damage_type_from_actionset(ent.attack_result))
        end
        if ent.final_attack_result then
            mergeDamageTypes(damageType, Ammo.get_damage_type_from_actionset(ent.final_attack_result))
        end
    end
    return damageType
end

function mergeDamageTypes(t1, t2)
    if t2 then
        for k, v in pairs(t2) do
            if not t1[k] then
                t1[k] = v
            else
                t1[k] = t1[k] + t2[k]
            end
        end
    end
end

return Ammo
