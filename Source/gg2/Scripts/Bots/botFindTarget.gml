/// botFindTarget(char, range)
/// Picks the thing this bot should shoot at, or noone. Same ds_priority-then-line-of-sight
/// shape as SentryTurret's own target selection, with no firing-arc restriction and a
/// per-class radius, but scored by threat rather than by raw distance.
///
///     threat = distance - 300*carrying the intel
///                      - 150*shot me recently
///                      - 120*Medic - 60*Engineer
///                      - 100*already wounded
///                      + range*inside my class's minimum band
///
/// Every term is in pixels, which is what makes them comparable: taking the intel carrier
/// means being willing to walk 300 px past someone harmless to reach them, and a Medic is
/// worth 120 px of that because leaving one alive undoes everything else the bot is about to
/// do. ("threat", not "score": score is a built-in GM8 global, and a var that shadows one is
/// a compilation error that takes the whole game down at startup.) Finishing the wounded is
/// worth less than either but more than nothing, since a target already at low health is the
/// cheapest kill available.
///
/// BOT_ATTACKER_BONUS is the newest term and the one that reads most like a person: whoever
/// is currently shooting *this* bot is a live threat rather than a scoring opportunity, and
/// answering them is what a player does before anything else. char.lastDamageDealer is a
/// Player rather than a Character (Rocket's User Event 5 and every other damage site set it
/// that way), so the comparison is against the candidate's own player, and Character's
/// Alarm 3 clears it - so this decays on its own and needs no timer here.
///
/// The last term is M7 3.2's actual defect, and it is a *lock* problem rather than the range
/// problem it was reported as. A Soldier's band is already 110-800 px and it fires throughout
/// - but threat was pure distance, so it always locked whoever was nearest, and
/// botCombatUpdate does not look for a new target while it still holds a valid one. An enemy
/// that closes inside BOT_SPLASH_SAFE therefore pins a Soldier permanently: it keeps the
/// lock, botClassKeys refuses to fire (a rocket at that range kills the shooter), and a
/// second enemy standing at a perfectly shootable 300 px is never considered. Ranking anyone
/// inside this class's own minimum band a full attention radius worse than everyone else
/// breaks the lock without adding a single new rule.
///
/// Threat values are floored at 1 rather than allowed to go negative, only because
/// ds_priority_delete_min is happy with any real and a negative one reads like a bug to
/// whoever prints one.
///
/// Two things that are not Characters are candidates as well:
///
///   Sentry     (reported from play: "bots are not shooting at sentries - dies to them")
///              A sentry is a turret with 100 hp that shoots back, and this script iterated
///              Characters and a Generator, so a bot walked into one, got killed by it, and
///              respawned to do it again with no term anywhere in the model for the thing
///              that killed it. BOT_SENTRY_BONUS ranks it a little ahead of a player at the
///              same distance, because a player can be walked away from and a sentry covers
///              its ground until somebody removes it.
///   Generator  (M7 6.3) at BOT_GEN_THREAT, far past any distance term, so it is only ever
///              chosen when nothing live is available - a bot that keeps shooting a wall
///              while somebody kills it is worse than one that never shoots the wall.
///
/// Line of sight is checked when a candidate is popped rather than when it is pushed, so the
/// collision_line runs once for the best candidate instead of once per enemy on the map.
/// collision_line_bulletblocking is safe to call from AI code: it is object-typed rather than
/// solid-typed, so the per-frame solidity toggling does not affect it.
///
/// WARNING: losing every candidate to line of sight does not mean there is nothing to fight,
/// and treating it that way is the "bots walk straight past enemies" report. A bot whose
/// target is behind a crate 80px away has a target; it just cannot see it *from here*. So a
/// blocked search falls back to the nearest candidate inside BOT_BLIND_RANGE and returns it
/// anyway. Nothing downstream has to change to cope: botCombatUpdate already carries an
/// unseen target through the memory window (M7 3.8) with player.botVisible false, holding its
/// aim on the last known position and not refreshing it through the wall - so the bot engages
/// the moment the sightline opens instead of re-paying the whole acquire chain then. The
/// radius is short on purpose; a blind target across the map is a bot aiming at scenery.

var char, range, queue, target, candidate, threat, minBand, enemyGen, cx, cy;
var blindBest, blindDist, dist;

char = argument0;
range = argument1;
queue = ds_priority_create();

minBand = botClassMinBand(char.player.class);

with(Character)
{
    if(id != char and !cloak and team != char.team and hp > 0)
    {
        dist = point_distance(x, y, char.x, char.y);
        if(dist <= range)
        {
            threat = dist;
            if(intel)
                threat -= 300;
            // WARNING: player here is the candidate Character's own player, which is what
            // lastDamageDealer holds. char.player would be the bot's own.
            if(player == char.lastDamageDealer)
                threat -= BOT_ATTACKER_BONUS;
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

with(Sentry)
{
    if(team != char.team and hp > 0)
    {
        dist = point_distance(x, y, char.x, char.y);
        if(dist <= range)
        {
            threat = dist - BOT_SENTRY_BONUS;
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
blindBest = noone;
blindDist = 0;
while(target == noone and !ds_priority_empty(queue))
{
    candidate = ds_priority_delete_min(queue);
    cx = candidate.x;
    cy = candidate.y;
    // A Character is anchored at its chest and that is the right point to shoot at; anything
    // else here is a map object anchored wherever its sprite happens to be, so aim at the
    // middle of the body instead - the same correction botObjectiveUpdate makes.
    if(!botIsCharacter(candidate))
    {
        cx = (candidate.bbox_left + candidate.bbox_right) / 2;
        cy = (candidate.bbox_top + candidate.bbox_bottom) / 2;
    }
    if(!collision_line_bulletblocking(char.x, char.y, cx, cy))
        target = candidate;
    else
    {
        // Best blind candidate: nearest, not best-threat. Threat ranks who is worth killing;
        // this is about which one the bot is close enough to be genuinely in a fight with,
        // and the generator - always last by construction - must never win it.
        dist = point_distance(cx, cy, char.x, char.y);
        if(dist <= BOT_BLIND_RANGE)
        {
            if(blindBest == noone or dist < blindDist)
            {
                blindBest = candidate;
                blindDist = dist;
            }
        }
    }
}

if(target == noone)
    target = blindBest;

ds_priority_destroy(queue);
return target;
