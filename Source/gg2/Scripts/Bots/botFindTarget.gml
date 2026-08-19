/// botFindTarget(char)
/// Picks the nearest visible living enemy Character within range, using the same
/// ds_priority-by-distance shape as SentryTurret's own target selection, but with no
/// firing-arc restriction and a flat combat radius.

var char, range, queue, target, candidate;
char = argument0;
range = 375;
queue = ds_priority_create();

with(Character)
{
    if(id != char and !cloak and team != char.team and hp > 0)
    {
        var dist;
        dist = distance_to_object(char);
        if(dist <= range)
            ds_priority_add(queue, id, dist);
    }
}

target = noone;
while(target == noone and !ds_priority_empty(queue))
{
    candidate = ds_priority_delete_min(queue);
    if(!collision_line_bulletblocking(char.x, char.y, candidate.x, candidate.y))
        target = candidate;
}

ds_priority_destroy(queue);
return target;
