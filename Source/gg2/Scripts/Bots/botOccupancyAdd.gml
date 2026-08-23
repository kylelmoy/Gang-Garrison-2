/// botOccupancyAdd(player, delta)
/// Adds (delta = 1) or removes (delta = -1) this bot's installed route from its team's
/// edge occupancy counts. Idempotent in both directions: adding a route that is already
/// counted does nothing, and so does removing one that is not.
///
/// That idempotence is the whole reason this is a script rather than two loops inlined at
/// the call sites. The route is added in exactly one place (botPathPlan, once a search has
/// succeeded) but *removed* in three - botPathFree on every re-plan, arrival and death;
/// botNavRelease when the bot leaves; and botPathPlan itself, which takes its own route out
/// of the counts before searching. Without the flag, the first two would double-decrement
/// after the third, and a count that goes negative makes an edge *cheaper* the more bots
/// are on it, which is the exact opposite of the point.
///
/// WARNING: botPathPlan removes this bot's own contribution before it searches, and that is not
/// an optimisation - it is what makes a route stable across re-plans. A bot that can see
/// its own route in the occupancy counts is charged extra for the path it is already
/// walking, so every re-plan tries to move it somewhere else and the whole team churns
/// lanes every BOT_REPLAN_TICKS. Measured offline on ctf_truefort: with self excluded, 2
/// of 16 re-plans changed a route; with a node-keyed penalty (which cannot exclude self
/// cleanly, since the bot stands on its own nodes) it was 15 of 16.
///
/// The route behind the bot is not trimmed as it advances, and does not need to be: a
/// re-plan re-installs the route from wherever the bot is standing now, so the tail drops
/// out of the counts on its own every BOT_REPLAN_TICKS.
///
/// WARNING: a removal uses botOccupiedTeam - the team the route was counted against -
/// rather than player.team, and the two genuinely come apart. ServerBalanceTeams switches
/// the lowest-scoring player on the larger team mid-round and can perfectly well pick a
/// bot, and botReteamAll reassigns every bot on a map change; both write player.team
/// directly. Reading player.team on the way out would then subtract from the map the bot
/// has just joined and leave its old team's counts raised forever - an edge nothing is
/// walking that every future search on that team is charged extra for.

var player, delta, occ, team, i, size, path, from, to, key, was, had;

player = argument0;
delta = argument1;

// No route means nothing to count, and the flag must come off with it - a flag left set
// against a route that no longer exists would make the next add a no-op and leave the
// bot permanently invisible to its team-mates' searches.
if(player.botPath < 0)
{
    player.botOccupied = false;
    player.botOccupiedTeam = -1;
    exit;
}

// Already in the state being asked for.
if(delta > 0 and player.botOccupied)
    exit;
if(delta < 0 and !player.botOccupied)
    exit;

// Adding counts against the team the bot is on now; removing counts against whichever
// team the route was added under, which is not necessarily the same one.
if(delta > 0)
    team = player.team;
else
    team = player.botOccupiedTeam;

occ = botOccupancyMap(team);
if(occ < 0)
    exit;

path = player.botPath;
size = ds_list_size(path);
for(i = 1; i < size; i += 1)
{
    from = ds_list_find_value(path, i - 1);
    to = ds_list_find_value(path, i);
    key = navEdgeKey(from, to);

    had = ds_map_exists(occ, key);
    was = 0;
    if(had)
        was = ds_map_find_value(occ, key);

    was += delta;
    // A count that has fallen to nothing is deleted rather than left at zero, so the map
    // stays the size of what is actually being walked rather than growing to the size of
    // every edge any bot has ever used on this map.
    if(was <= 0)
    {
        if(had)
            ds_map_delete(occ, key);
    }
    else if(had)
        ds_map_replace(occ, key, was);
    else
    {
        // WARNING: ds_map_add, not ds_map_replace. GM8's ds_map_replace only replaces a key
        // that is already there and does NOTHING when it is absent - it does not insert the
        // way the GameMaker Studio function of the same name does. Every count here starts
        // absent, so a bare replace left both maps permanently empty while every bot still
        // reported its route as counted: the flag is set outside this branch, so the
        // bookkeeping looked perfectly healthy and no route was ever charged for. Measured
        // live - 1200 frames, twelve bots, ds_map_size stuck at 0.
        ds_map_add(occ, key, was);
    }
}

player.botOccupied = (delta > 0);
if(delta > 0)
    player.botOccupiedTeam = player.team;
else
    player.botOccupiedTeam = -1;
