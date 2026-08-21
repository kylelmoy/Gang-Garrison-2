/// botFindAlly(char, range)
/// Picks the teammate a Medic bot should have its beam on, or noone. Scored rather than
/// simply nearest: the hurt come first, and between two equally healthy teammates the
/// tougher one wins, because a Medic's job is to keep the biggest body in the fight
/// alive rather than to top up whoever is closest.
///
/// score = 1000 * hp/maxHp + distance - maxHp
///
/// so a Heavy at half health (1000*0.5 + d - 200) outscores a Scout at half health
/// (1000*0.5 + d - 125) by exactly the difference in what they can absorb, and anyone
/// actually wounded outscores anyone who is not by far more than distance can make up.
///
/// Line of sight uses the same Obstacle-typed collision_line the Medigun itself uses to
/// validate a heal target, not collision_line_bulletblocking: a heal beam is stopped by
/// walls the same way a bullet is, but the two predicates are not the same object set
/// and the beam's is the one that decides whether the heal actually connects.

var char, range, queue, ally, candidate, best;

char = argument0;
range = argument1;
queue = ds_priority_create();

with(Character)
{
    if(id != char and team == char.team and hp > 0)
    {
        var dist;
        dist = point_distance(x, y, char.x, char.y);
        if(dist <= range)
            ds_priority_add(queue, id, 1000 * hp / maxHp + dist - maxHp);
    }
}

ally = noone;
while(ally == noone and !ds_priority_empty(queue))
{
    candidate = ds_priority_delete_min(queue);
    if(!collision_line(char.x, char.y, candidate.x, candidate.y, Obstacle, true, true))
        ally = candidate;
}

ds_priority_destroy(queue);
return ally;
