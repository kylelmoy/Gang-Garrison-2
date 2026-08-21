/// botServerActions(player, char, target, dist)
/// The half of a class's behaviour that is not a key at all. Zoom, build and eat are
/// client *commands* rather than bits in the input byte (F19), so a bot performs them by
/// calling the same server-side scripts the network path calls - serverToggleZoom,
/// serverBuildSentry, serverEatSandvich - each of which re-checks its own preconditions.
///
/// target may be noone, and two of the three behaviours are specifically about that
/// case: an Engineer builds when nothing is shooting at it, and a Heavy eats when it is
/// hurt and out of the fight. Called on the target-search cadence rather than every
/// tick, because all three are toggles or one-shots and none of them is a reflex.

var player, char, target, dist, playerId;

player = argument0;
char = argument1;
target = argument2;
dist = argument3;

playerId = ds_list_find_index(global.players, player);
if(playerId < 0)
    exit;

if(player.class == CLASS_SNIPER)
{
    // Zoom is worth its movement penalty at range and is a liability up close, so the
    // two thresholds are apart: a target between them leaves the zoom as it is rather
    // than toggling it every time someone crosses one line.
    if(!char.zoomed and target != noone and dist >= BOT_ZOOM_RANGE)
        serverToggleZoom(player, playerId);
    else if(char.zoomed and (target == noone or dist <= BOT_UNZOOM_RANGE))
        serverToggleZoom(player, playerId);
}
else if(player.class == CLASS_ENGINEER)
{
    // Where to build is a strategy question the plan leaves to v2; building at all,
    // when there is a lull and the metal is there, is most of the value.
    if(target == noone)
        serverBuildSentry(player, playerId);
}
else if(player.class == CLASS_HEAVY)
{
    if(target == noone and char.hp <= char.maxHp * BOT_EAT_HP_FRACTION)
        serverEatSandvich(player, playerId);
}
