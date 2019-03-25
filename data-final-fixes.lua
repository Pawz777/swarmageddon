for k, corpse in pairs(data.raw["corpse"]) do
    if (string.find(corpse.name, "biter") or string.find(corpse.name, "spitter")) then
        if (corpse.time_before_removed ~= nil) then
            data.raw.corpse[k].time_before_removed = settings.startup["corpse-ttl"].value * 60
        end
    end
end
