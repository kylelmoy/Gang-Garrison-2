/// botPathFree(player)
/// Drops whatever route this bot was following, leaving its goal alone.
///
/// Called on every re-plan and whenever the bot's Character goes away, so a respawned
/// bot works out a fresh route from wherever it came back rather than resuming one
/// from where it died. GM8 has no GC, so the ds_list has to go back explicitly or a
/// busy server leaks one per re-plan - which is every few seconds, per bot.

var player;
player = argument0;

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
