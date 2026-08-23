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
    // Three conditions, and the middle one is the change. `target == noone` was the whole
    // test, which is wrong in both directions: botCombatUpdate keeps a target for 30 ticks
    // after the sightline breaks (M7 3.8), so a Heavy that has just lost sight of someone
    // is "in a fight" for a second by this test and eats nothing - and a Heavy already on
    // the end of a Medic's beam wastes the sandvich on healing it is getting for free.
    //
    // So: hurt, nobody is actually healing it, and nothing VISIBLE to shoot at. char.healer
    // is the field the Medigun sets to its own ownerPlayer and clears back to -1, so the
    // test is `< 0` and NOT `!healer` - -1 is perfectly true in GML and that spelling would
    // read every unhealed Heavy as healed. serverEatSandvich re-checks its own
    // preconditions, so a wrong guess here is ignored rather than harmful.
    if(char.hp <= char.maxHp * BOT_EAT_HP_FRACTION
       and char.healer < 0
       and (target == noone or !player.botVisible))
        serverEatSandvich(player, playerId);
}
