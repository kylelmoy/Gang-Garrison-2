/// botNavRelease(player)
/// Releases everything the navigation layer allocated for one bot: its current route
/// and its anti-thrash blacklist. Call when the bot leaves for good.
///
/// Separate from botPathFree because the blacklist deliberately outlives individual
/// routes - that is the whole point of it - so the two have different lifetimes and
/// only removal ends both.

var player;
player = argument0;

botPathFree(player);

if(player.botBlacklist >= 0)
{
    ds_map_destroy(player.botBlacklist);
    player.botBlacklist = -1;
    ds_list_destroy(player.botBlacklistQ);
    player.botBlacklistQ = -1;
}

player.botHasGoal = false;
player.botGoalNode = -1;
