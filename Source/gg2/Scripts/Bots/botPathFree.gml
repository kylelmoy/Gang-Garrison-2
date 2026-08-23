/// botPathFree(player)
/// Drops whatever route this bot was following, leaving its goal alone.
///
/// Called on every re-plan and whenever the bot's Character goes away, so a respawned
/// bot works out a fresh route from wherever it came back rather than resuming one
/// from where it died. GM8 has no GC, so the ds_list has to go back explicitly or a
/// busy server leaks one per re-plan - which is every few seconds, per bot.

var player;
player = argument0;

// Give up this bot's share of the team's edge occupancy counts first, because the counts
// are read off the route and the route is about to be destroyed. Idempotent, so the
// botPathPlan path - which takes its own route out of the counts before it searches, and
// then calls in here - decrements once rather than twice.
botOccupancyAdd(player, -1);

if(player.botPath >= 0)
{
    ds_list_destroy(player.botPath);
    player.botPath = -1;
}
player.botPathAt = 0;
player.botEdgeFrom = -1;
player.botEdgeTo = -1;
player.botOffPathTicks = 0;
player.botStuckTicks = 0;
// A run-up belongs to one jump edge on one route. Left set across a re-plan it would
// suppress the off-route detector for a route that no longer has that edge in it.
player.botRunupAt = -1;
