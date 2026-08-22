/// botBlacklistEdge(player, fromNode, toNode, why)
/// Marks one edge unusable for this bot for the next BOT_BLACKLIST_TICKS, and counts
/// the fact for diagnostics. `why` is a short tag naming the call site - "off" for a
/// move that finished off the route, "stk" for the stuck detector, "thr" for replanning
/// twice in the same spot - and is recorded alongside the endpoints.
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
///
/// botBlacklistFires alone says an edge misled the bot; it does not say WHICH, and a
/// count of two on a 1000-tick leg is a very different bug depending on whether it is
/// the same marginal arc twice or two unrelated ones. botBlacklistLog carries the
/// endpoints, so the answer can be read off a finished scenario and taken straight to
/// `navaudit --node`, with no need to watch the bot. Only the first entries are kept -
/// the string is bounded because every bot in every round has one.

var player, fromNode, toNode, why, edgeKey;
player = argument0;
fromNode = argument1;
toNode = argument2;
why = argument3;

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

if(string_length(player.botBlacklistLog) < 240)
{
    if(player.botBlacklistLog != "")
        player.botBlacklistLog += ",";
    player.botBlacklistLog += why + ":" + string(fromNode) + ">" + string(toNode)
        + "@" + string(GameServer.frame);
}
