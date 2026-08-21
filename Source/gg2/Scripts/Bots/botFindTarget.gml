/// botFindTarget(char, range)
/// Picks the thing this bot should shoot at, or noone. Same ds_priority-then-line-of-
/// sight shape as SentryTurret's own target selection, with no firing-arc restriction
/// and a per-class radius, but scored by threat rather than by raw distance.
///
///     threat = distance - 300*carrying the intel
///                      - 120*Medic - 60*Engineer
///                      - 100*already wounded
///                      + range*inside my class's minimum band
///
/// Every term is in pixels, which is what makes them comparable: taking the intel
/// carrier means being willing to walk 300 px past someone harmless to reach them, and a
/// Medic is worth 120 px of that because leaving one alive undoes everything else the
/// bot is about to do. ("threat", not "score": score is a built-in GM8 global, and a var
/// that shadows one is a compilation error that takes the whole game down at startup.)
/// Finishing the wounded is worth less than either but more than
/// nothing, since a target already at low health is the cheapest kill available.
///
/// The last term is M7 3.2's actual defect, and it is a *lock* problem rather than the
/// range problem it was reported as. A Soldier's band is already 110-800 px and it fires
/// throughout - but threat was pure distance, so it always locked whoever was nearest,
/// and botCombatUpdate does not look for a new target while it still holds a valid one.
/// An enemy that closes inside BOT_SPLASH_SAFE therefore pins a Soldier permanently: it
/// keeps the lock, botClassKeys refuses to fire (a rocket at that range kills the
/// shooter), and a second enemy standing at a perfectly shootable 300 px is never
/// considered. Ranking anyone inside this class's own minimum band a full attention
/// radius worse than everyone else breaks the lock without adding a single new rule -
/// with nobody else about, the close target is still chosen and the bot still backs away
/// from it (botInputUpdate); with someone else about, the bot shoots the one it can hurt.
///
/// Threat values are floored at 1 rather than allowed to go negative, only because
/// ds_priority_delete_min is happy with any real and a negative one reads like a bug
/// to whoever prints one.
///
/// The enemy Generator is a candidate too (M7 6.3), and before this it was not: this
/// script iterated with(Character) and nothing else, so in Generator mode a bot had never
/// once considered shooting the thing the entire mode is about. It is added at
/// BOT_GEN_THREAT, which is far past any distance term, so it is only ever chosen when no
/// live enemy is available - a bot that keeps shooting a wall while somebody kills it is
/// worse than one that never shoots the wall at all. At maxHp 2100 the generator is a
/// sustained-fire job, which is why the bot also needs somewhere to *stand* while doing
/// it (botGoalSpot) rather than treating arrival as completion.
///
/// Line of sight is checked when a candidate is popped rather than when it is pushed, so
/// the collision_line runs once for the best candidate instead of once per enemy on the
/// map. collision_line_bulletblocking is safe to call from AI code: it is object-typed
/// rather than solid-typed, so the per-frame solidity toggling does not affect it.

var char, range, queue, target, candidate, threat, minBand, enemyGen, cx, cy;

char = argument0;
range = argument1;
queue = ds_priority_create();

minBand = botClassMinBand(char.player.class);

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
            if(dist < minBand)
                threat += range;
            ds_priority_add(queue, id, max(1, threat));
        }
    }
}

if(instance_exists(Generator))
{
    if(char.team == TEAM_RED)
        enemyGen = GeneratorBlue;
    else
        enemyGen = GeneratorRed;
    with(enemyGen)
    {
        if(hp > 0)
        {
            // Measured to the middle of the body rather than to the origin, which on a
            // large map object is wherever the sprite happens to be anchored.
            cx = (bbox_left + bbox_right) / 2;
            cy = (bbox_top + bbox_bottom) / 2;
            if(point_distance(cx, cy, char.x, char.y) <= range)
                ds_priority_add(queue, id, BOT_GEN_THREAT + point_distance(cx, cy, char.x, char.y));
        }
    }
}

target = noone;
while(target == noone and !ds_priority_empty(queue))
{
    candidate = ds_priority_delete_min(queue);
    cx = candidate.x;
    cy = candidate.y;
    if(candidate.object_index == GeneratorRed or candidate.object_index == GeneratorBlue)
    {
        cx = (candidate.bbox_left + candidate.bbox_right) / 2;
        cy = (candidate.bbox_top + candidate.bbox_bottom) / 2;
    }
    if(!collision_line_bulletblocking(char.x, char.y, cx, cy))
        target = candidate;
}

ds_priority_destroy(queue);
return target;
