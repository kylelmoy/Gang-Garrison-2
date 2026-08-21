/// botFindTarget(char, range)
/// Picks the enemy this bot should shoot at, or noone. Same ds_priority-then-line-of-
/// sight shape as SentryTurret's own target selection, with no firing-arc restriction
/// and a per-class radius, but scored by threat rather than by raw distance.
///
///     threat = distance - 300*carrying the intel
///                      - 120*Medic - 60*Engineer
///                      - 100*already wounded
///
/// Every term is in pixels, which is what makes them comparable: taking the intel
/// carrier means being willing to walk 300 px past someone harmless to reach them, and a
/// Medic is worth 120 px of that because leaving one alive undoes everything else the
/// bot is about to do. ("threat", not "score": score is a built-in GM8 global, and a var
/// that shadows one is a compilation error that takes the whole game down at startup.)
/// Finishing the wounded is worth less than either but more than
/// nothing, since a target already at low health is the cheapest kill available.
///
/// Threat values are floored at 1 rather than allowed to go negative, only because
/// ds_priority_delete_min is happy with any real and a negative one reads like a bug
/// to whoever prints one.
///
/// Line of sight is checked when a candidate is popped rather than when it is pushed, so
/// the collision_line runs once for the best candidate instead of once per enemy on the
/// map. collision_line_bulletblocking is safe to call from AI code: it is object-typed
/// rather than solid-typed, so the per-frame solidity toggling does not affect it.

var char, range, queue, target, candidate, threat;

char = argument0;
range = argument1;
queue = ds_priority_create();

with(Character)
{
    if(id != char and !cloak and team != char.team and hp > 0)
    {
        var dist;
        dist = point_distance(x, y, char.x, char.y);
        if(dist <= range)
        {
            threat = dist;
            if(intel)
                threat -= 300;
            if(player.class == CLASS_MEDIC)
                threat -= 120;
            else if(player.class == CLASS_ENGINEER)
                threat -= 60;
            if(hp <= maxHp * 0.4)
                threat -= 100;
            ds_priority_add(queue, id, max(1, threat));
        }
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
