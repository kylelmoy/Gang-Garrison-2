/// botPathPlan(player)
/// Works out a fresh route from where the bot is now to its goal, and installs it.
/// Returns true if it found one.
///
/// Re-planning is both event-driven and on a slow timer (F35). Surfacer can be purely
/// event-driven because its destinations do not move; a shooter's do, and Quake III
/// re-evaluates on every think. So this is called on interruption - stuck, off-path, a
/// vanished edge, a new goal - and otherwise every BOT_REPLAN_TICKS, staggered per bot
/// by its own id so a server full of them does not do all of its searching on one
/// frame.
///
/// The anti-thrash check lives here rather than in the stuck detector because it is
/// about re-planning, not about failing outright: two re-plans within BOT_THRASH_DIST
/// of each other means the bot is going round in a circle at one spot, whatever the
/// immediate cause, and the edge it keeps being handed is the one to take away (F35).
/// The stuck detector catches the blunt case where nothing moves at all; this catches
/// the case where the bot is technically moving - shuffling back and forth across a
/// ledge - and getting nowhere.
///
/// Expired blacklist entries are swept here, off the front of the insertion-ordered
/// list. This is the only moment a stale one could affect anything, so it needs no
/// timer of its own.

var player, char, startNode, goalNode, thrash, edgeKey, expiry, prevFrom, prevTo;
player = argument0;
char = player.object;

// Read the edge being attempted before botPathFree clears it - that is the one the
// anti-thrash check below wants to take away, and clearing it first would leave the
// blacklist permanently empty while looking like it worked.
prevFrom = player.botEdgeFrom;
prevTo = player.botEdgeTo;

botPathFree(player);

// Stagger by id so a full server spreads its searches over the re-plan window instead
// of bunching them onto whichever frame the bots happened to be added on.
player.botReplanAt = GameServer.frame + BOT_REPLAN_TICKS + (player mod BOT_REPLAN_TICKS);

if(char == -1)
    return false;
if(!player.botHasGoal)
    return false;
if(!global.navReady)
    return false;

// Going round in circles at one spot: take away the edge it keeps trying.
thrash = point_distance(char.x, char.y, player.botLastReplanX, player.botLastReplanY);
if(thrash < BOT_THRASH_DIST)
    player.botReplanNear += 1;
else
    player.botReplanNear = 0;
player.botLastReplanX = char.x;
player.botLastReplanY = char.y;

if(player.botReplanNear >= 2)
{
    botBlacklistEdge(player, prevFrom, prevTo, "thr");
    player.botReplanNear = 0;
}

// Expiries are non-decreasing along the list, so the front is always the next one due
// and the first entry still in date ends the sweep.
if(player.botBlacklist >= 0)
{
    while(ds_list_size(player.botBlacklistQ) > 0)
    {
        edgeKey = ds_list_find_value(player.botBlacklistQ, 0);
        expiry = ds_map_find_value(player.botBlacklist, edgeKey);
        if(expiry > GameServer.frame)
            break;
        ds_list_delete(player.botBlacklistQ, 0);
        ds_map_delete(player.botBlacklist, edgeKey);
    }
}

startNode = navNodeFromWorld(char.x, char.y);
if(startNode < 0)
    return false;

goalNode = navNodeFromWorld(player.botGoalX, player.botGoalY);
if(goalNode < 0)
    return false;
player.botGoalNode = goalNode;

// botRouteSeed is this bot's own idea of what edges cost (M7 1.4) - non-zero only for
// bots, so a hand-issued or test query still gets the plain deterministic search.
player.botPath = navFindPath(startNode, goalNode, player.team, char.intel,
                             player.botBlacklist, player.botRouteSeed);
player.botPathAt = 0;
player.botReplans += 1;

return (player.botPath >= 0);
