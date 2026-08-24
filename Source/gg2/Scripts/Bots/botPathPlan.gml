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
/// WARNING: the search runs *before* the old route is given up, and a failed search keeps
/// it. This is the "bots momentarily stop moving (no path)" report, and the stall was
/// structural rather than occasional: the old order was free-then-search, so between a goal
/// changing and a route existing the bot had nothing to follow and botPathKeys returned no
/// keys at all. A search that succeeds hides that in one tick; a search that fails - an
/// unreachable objective, a goal snapped to a node in another component, a carrier standing
/// somewhere the graph does not reach - left the bot standing still until the re-plan timer
/// came round again, and then again. Keeping the old route means a bot whose new goal cannot
/// be planned for keeps walking the last route that worked, which is what a person does and
/// is visibly better than stopping dead in the open.
///
/// botPlanFailUntil is what stops that from becoming expensive. Once a failed search leaves
/// a route installed, every event-driven caller in botPathKeys would otherwise fire again on
/// the very next tick - a full A* per bot per frame, for a goal that cannot be reached from a
/// pixel away either. So a failure parks the search for one re-plan window. It applies only
/// while a route is actually installed: a bot with nothing to follow has to keep trying, and
/// for that case the timer at the top of botPathKeys is the throttle, exactly as before.
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

var player, char, startNode, goalNode, thrash, edgeKey, expiry, prevFrom, prevTo, newPath, canRocket;
player = argument0;
char = player.object;

// The edge being attempted is what the anti-thrash check below wants to take away, and it
// stays live now that the route is not freed up front.
prevFrom = player.botEdgeFrom;
prevTo = player.botEdgeTo;

// Stagger by id so a full server spreads its searches over the re-plan window instead
// of bunching them onto whichever frame the bots happened to be added on.
player.botReplanAt = GameServer.frame + BOT_REPLAN_TICKS + (player mod BOT_REPLAN_TICKS);

if(char == -1)
{
    botPathFree(player);
    return false;
}
if(!player.botHasGoal)
    return false;
if(!global.navReady)
    return false;

// A search that just failed will fail again from a pixel away - but only skip it while
// there is still something to follow in the meantime.
if(player.botPath >= 0 and GameServer.frame < player.botPlanFailUntil)
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
{
    player.botPlanFailUntil = GameServer.frame + BOT_REPLAN_TICKS;
    return false;
}

goalNode = navNodeFromWorld(player.botGoalX, player.botGoalY);
if(goalNode < 0)
{
    player.botPlanFailUntil = GameServer.frame + BOT_REPLAN_TICKS;
    return false;
}

// Take this bot's own route out of the team's occupancy counts before searching, and put
// it back if the search fails. Route variety comes from being charged extra for edges
// team-mates are already walking (navFindPath's header has the measurements), and a bot
// that can see its *own* route in those counts is charged extra for the path it is already
// on - so every re-plan would try to move it somewhere else and the whole team would swap
// lanes every BOT_REPLAN_TICKS. With self excluded, 2 of 16 re-plans changed a route in the
// offline model; without, a comparable node-keyed penalty churned 15 of 16.
//
// This runs before the search and before botPathFree below, which is the only ordering that
// works: botPathFree is what destroys player.botPath, and the counts can only be undone
// while the route they were built from still exists to be walked.
botOccupancyAdd(player, -1);

// The blacklist and the team's occupancy map are the two per-query inputs. The blacklist is
// private to this bot; the occupancy map is deliberately shared, because what it models -
// bots bunching up - is a property of the team rather than of any one member of it.
// canDoublejump is read off the Character rather than tested against CLASS_SCOUT,
// because it is the field the game itself gates the second jump on (Character's Begin
// Step) and Scout's Create event is the only thing that sets it. A class list here would
// be a second copy of that fact, and the two would disagree the first time a class gained
// or lost the ability.
//
// canRocket is the same idea one step further on. It is read off the WEAPON rather than
// the class for the reason the paragraph above gives about canDoublejump - firing a rocket
// at your own feet is a thing a Rocketlauncher does, not a thing a CLASS_SOLDIER does, and
// a class list here would be a second copy of that fact - and it carries an hp test as
// well, because a rocket jump costs NAV_RJ_DAMAGE and a bot that cannot survive one must
// not be routed over it.
//
// Strictly greater, not >=: the damage is dealt before the bot lands, so equal health is
// a bot that dies in mid-air on an edge it was told to fly. There is no margin beyond
// that on purpose - a rocket jump taken at 31hp is a real thing a player does, and the
// point of these edges is a bot that reads like a player.
//
// The `!= -1` is not belt-and-braces. GM8's -1 is the constant for `self`, so
// instance_exists(-1) is TRUE and char.currentWeapon.object_index on a -1 sentinel
// silently reads the CALLER's object_index - which would be Player here, never
// Rocketlauncher, so it would fail quietly in the safe direction today and stop doing so
// the moment this is copied somewhere else. GG2 uses -1 as its "nothing" sentinel
// throughout (see gg2-agent/GML.md); instance_exists cannot substitute for the test.
// Separate ifs throughout because GM8's `and` does not short-circuit.
canRocket = false;
if(char.currentWeapon != -1)
{
    if(instance_exists(char.currentWeapon))
    {
        if(char.currentWeapon.object_index == Rocketlauncher)
        {
            if(char.hp > NAV_RJ_DAMAGE)
                canRocket = true;
        }
    }
}

newPath = navFindPath(startNode, goalNode, player.team, char.intel,
                      player.botBlacklist, botOccupancyMap(player.team),
                      char.canDoublejump, canRocket);
player.botReplans += 1;

if(newPath < 0)
{
    // The old route is still installed and still being followed, so it goes back into the
    // counts it came out of - otherwise a bot whose goal cannot be planned for would walk
    // its route invisibly, and its team-mates would plan straight down it.
    botOccupancyAdd(player, 1);
    player.botPlanFailUntil = GameServer.frame + BOT_REPLAN_TICKS;
    return false;
}

// Only now is the old route given up. botPathFree is what zeroes the follower's per-route
// state - the edge in progress, the off-route and stuck counters - and all of that belongs
// to the route being replaced, so it has to happen here and not before the search.
botPathFree(player);
player.botGoalNode = goalNode;
player.botPath = newPath;
player.botPathAt = 0;
player.botPathStale = false;
player.botPlanFailUntil = 0;

// Only once the new route is installed, since this reads it off the player.
botOccupancyAdd(player, 1);

return true;
