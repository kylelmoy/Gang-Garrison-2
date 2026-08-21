/// botEnemySpawn(team, fromX, fromY)
/// Returns the enemy team's spawn point nearest (fromX, fromY), or noone if that team has
/// no spawn points on this map. `team` is the *asking* bot's team, so a red bot gets a
/// blue spawn.
///
/// Maps author up to five spawn points per team (SpawnPointRed, SpawnPointRed1..4, all
/// parented to SpawnPointRed, and the blue mirror), and which of them is "the" enemy spawn
/// depends on where you are standing - on a multi-stage map like cp_dirtbowl they are
/// scattered across the whole level. Nearest-to-the-caller is the answer that means
/// "the direction the enemy is coming from", which is what every caller actually wants.
///
/// This exists for M7 2.2: once your team holds the objective, a player does not stand on
/// it, they walk out toward where the enemy will come from and take that ground. The
/// direction is free - the spawn is already an instance in the room - and the *distance*
/// is deliberately capped by the caller (BOT_PUSH_DIST), because parking outside an enemy
/// spawn is a bad strategy rather than an aggressive one: players retreat inside and heal
/// to full, so the bot gains nothing and gives up the objective it was holding.

var team, fromX, fromY, spawnObj, best, bestDist, d;

team = argument0;
fromX = argument1;
fromY = argument2;

if(team == TEAM_RED)
    spawnObj = SpawnPointBlue;
else if(team == TEAM_BLUE)
    spawnObj = SpawnPointRed;
else
    return noone;

best = noone;
bestDist = -1;
with(spawnObj)
{
    d = point_distance(x, y, fromX, fromY);
    if(bestDist < 0 or d < bestDist)
    {
        bestDist = d;
        best = id;
    }
}

return best;
