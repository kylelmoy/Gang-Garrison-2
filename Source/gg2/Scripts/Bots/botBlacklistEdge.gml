/// botBlacklistEdge(player, fromNode, toNode)
/// Marks one edge unusable for this bot for the next BOT_BLACKLIST_TICKS, and counts
/// the fact for diagnostics.
///
/// This is Surfacer's anti-thrash downgrade (F35). A bot that cannot actually traverse
/// an edge the graph believes in - wedged on a doorframe, shoved by another player,
/// standing where a moving platform used to be - will otherwise re-plan, be handed the
/// identical route, and fail again on the same tick, forever. Taking the edge away for
/// a few seconds forces A* to find the way round, and expiry means a one-off
/// obstruction does not cost the bot that route for the rest of the round.
///
/// Two structures, because a ds_map alone cannot be iterated safely in GM8 -
/// ds_map_find_next has no reliable end-of-map answer here, since GM8 has no
/// is_undefined. The map answers "is this edge blacklisted" in one lookup, which is
/// what navFindPath needs per expansion; the list carries the same keys in insertion
/// order, which is what botPathPlan needs to expire them. Re-blacklisting an edge that
/// is already listed does nothing at all rather than extending it, which is what keeps
/// the two exactly in step and the list's expiries non-decreasing.

var player, fromNode, toNode, edgeKey;
player = argument0;
fromNode = argument1;
toNode = argument2;

if(fromNode < 0 or toNode < 0)
    exit;

if(player.botBlacklist < 0)
{
    player.botBlacklist = ds_map_create();
    player.botBlacklistQ = ds_list_create();
}

edgeKey = navEdgeKey(fromNode, toNode);
if(ds_map_exists(player.botBlacklist, edgeKey))
    exit;

ds_map_add(player.botBlacklist, edgeKey, GameServer.frame + BOT_BLACKLIST_TICKS);
ds_list_add(player.botBlacklistQ, edgeKey);
player.botBlacklistFires += 1;
