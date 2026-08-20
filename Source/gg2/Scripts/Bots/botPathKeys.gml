/// botPathKeys(player)
/// One tick of path following. Returns the movement key bits (LEFT/RIGHT/JUMP/DOWN)
/// this bot should press, and keeps its route, its stuck detector and its blacklist up
/// to date on the way.
///
/// Runs every tick, unlike target selection, which re-decides only every 15 (M3).
/// Aiming may lag and look human; steering may not - a jump missed by one tick is a
/// bot standing at the edge of a gap forever.
///
/// The shape is Surfacer's surface_navigator plus Quake III's think loop (F35):
///
///   1. Note whether we moved at all since last tick - the stuck detector's only input.
///   2. Plan, if there is no route or the re-plan timer is up.
///   3. Find which node we are standing on and advance along the route to it. Failing
///      to find ourselves on the route at all, for long enough, is an interruption.
///   4. Steer along the current edge according to what kind of move it is.
///   5. If we pressed keys and nothing moved for BOT_STUCK_TICKS, give up on this edge:
///      blacklist it and re-plan.
///
/// Only the edge *types* the graph can produce are handled here, and each is steered by
/// the geometry the corresponding generator used, not by a general rule - a fall leaves
/// past the end of a surface, a drop-through goes down through its middle, a jump needs
/// its takeoff at the right end and at speed. Getting those from the same numbers the
/// build used is what keeps the follower honest about what it planned.
///
/// Jump is edge-triggered, not held. Character's Begin Step jumps on pressedKeys & $80
/// (a rising edge), so a bot holding JUMP down jumps exactly once and then never again;
/// botJumpHeld alternates so a bot that still wants to jump gets a fresh press every
/// other tick until it leaves the ground.

var player, char, keys, here, size, cur, nxt, i, edgeRow, edgeType, found, moved;
var mx, targetCol, tx, gx, n0, n1, c0, c1, takeoffCol, wantJump, dirToNext;

player = argument0;
char = player.object;
keys = 0;

if(char == -1)
{
    botPathFree(player);
    return 0;
}

if(!player.botHasGoal)
    return 0;

// Half a pixel, not zero: good_move_contact_solid works at 1/8 pixel precision (F24),
// so a bot grinding against a wall can jitter by a fraction without going anywhere.
moved = (abs(char.x - player.botLastX) > 0.5) or (abs(char.y - player.botLastY) > 0.5);
player.botLastX = char.x;
player.botLastY = char.y;

// Bots simply do not path until the graph is up (F31). A cold build is a few seconds
// on the largest map, once per map ever, and standing still is a better failure than
// walking off a cliff on a guess.
if(!global.navReady)
    return 0;

// Planning is on the timer even when it fails, which is the whole reason this is one
// condition and not "plan whenever we have no route". A goal that is genuinely
// unreachable - behind an enemy gate, across a gap nothing spans - makes every search
// fail, and retrying it every tick is a full A* per bot per frame that can never
// succeed. Event-driven re-plans set botReplanAt to 0 rather than calling in here.
if(GameServer.frame >= player.botReplanAt)
    botPathPlan(player);

if(player.botPath < 0)
    return 0;

size = ds_list_size(player.botPath);

// Where are we on the route? Searched forward from where we last were, never back: a
// bot only advances along its own route, and looking backwards would let a long
// surface that the route touches twice pull it into a loop.
here = navNodeFromWorld(char.x, char.y);
found = false;
if(here >= 0)
{
    for(i = player.botPathAt; i < size; i += 1)
    {
        if(ds_list_find_value(player.botPath, i) == here)
        {
            player.botPathAt = i;
            found = true;
            break;
        }
    }
}

// Standing on a surface the route does not mention is not a delay to ride out, it is a
// finished move that went somewhere else, and waiting BOT_OFFPATH_TICKS to admit it is
// how a bot walks somewhere it cannot get back from. So that case re-plans at once,
// from wherever it actually is.
//
// Not knowing where we are at all is the different case, and it does get the timer:
// mid-jump there is no node under the bot, and a 28-tick arc would otherwise read as a
// 28-tick interruption every single time (F24). char.onground is what tells the two
// apart, and navNodeFromWorld resolving to a node while airborne is not to be trusted -
// it deliberately tolerates being a couple of cells off a surface.
if(found)
    player.botOffPathTicks = 0;
else if(char.onground)
{
    if(here >= 0)
    {
        // The edge in progress is the one that just deposited the bot somewhere the
        // route does not go, so take it away for a few seconds the same way the stuck
        // detector does. Without this, A* hands back the identical route from the
        // node the bot drifted onto, it walks back, and the pair of surfaces becomes a
        // loop the bot never leaves - and unlike the wedged case the anti-thrash
        // distance check never fires, because the bot is genuinely covering ground.
        // botPathFree has already zeroed botEdgeFrom/To if there was no edge running,
        // and botBlacklistEdge ignores negative nodes.
        player.botOffRouteFires += 1;
        player.botOffPathTicks = 0;
        botBlacklistEdge(player, player.botEdgeFrom, player.botEdgeTo);
        botPathPlan(player);
        return 0;
    }
    player.botOffPathTicks += 1;
}

if(player.botOffPathTicks > BOT_OFFPATH_TICKS)
{
    botPathPlan(player);
    return 0;
}

// On the last node of the route: walk the rest of the way to the goal itself, along
// the surface. The goal is clamped into the node's own span, since navNodeFromWorld
// resolves a goal that is near a surface rather than exactly on it.
if(player.botPathAt >= size - 1)
{
    player.botEdgeFrom = -1;
    player.botEdgeTo = -1;

    cur = ds_list_find_value(player.botPath, size - 1);
    c0 = ds_grid_get(global.navNodes, NAV_NODE_X0, cur);
    c1 = ds_grid_get(global.navNodes, NAV_NODE_X1, cur);
    gx = max(navColWorldX(c0), min(navColWorldX(c1), player.botGoalX));

    // Being within tolerance of the goal is not the same as stopping there. A bot
    // arrives at a run - often still falling onto the last surface - and GG2 keeps a
    // character's horizontal speed for about ten ticks after the keys come off, so
    // declaring arrival on position alone and then pressing nothing coasts the bot
    // thirty to forty pixels past the thing it was sent to. Measured on all three legs
    // of the gg_debug walk; the last one slid into the left wall.
    //
    // So inside the tolerance band the bot brakes rather than coasts, and only counts
    // as arrived once it is on the ground and actually stopped. Braking is a press
    // against the motion, which is also how a player stops; the speed floor is what
    // keeps that from becoming a press back the other way.
    if(abs(char.x - gx) <= BOT_ARRIVE_TOL)
    {
        if(char.onground and abs(char.hspeed) < 1)
        {
            player.botArrived = true;
            player.botHasGoal = false;
            botPathFree(player);
            return 0;
        }

        if(char.hspeed > 1)
            keys = KEY_LEFT;
        else if(char.hspeed < -1)
            keys = KEY_RIGHT;

        // Not stuck: standing still inside the band with nothing to brake is the
        // whole point, and the airborne case is waiting on a landing, not wedged.
        player.botStuckTicks = 0;
        return keys;
    }

    if(char.x < gx)
        keys = KEY_RIGHT;
    else
        keys = KEY_LEFT;

    if(!moved)
        player.botStuckTicks += 1;
    else
        player.botStuckTicks = 0;
    if(player.botStuckTicks >= BOT_STUCK_TICKS)
    {
        player.botStuckFires += 1;
        botPathPlan(player);
        return 0;
    }
    return keys;
}

cur = ds_list_find_value(player.botPath, player.botPathAt);
nxt = ds_list_find_value(player.botPath, player.botPathAt + 1);
player.botEdgeFrom = cur;
player.botEdgeTo = nxt;

// The graph is rebuilt on every map change, and a route planned against the old one
// names nodes that no longer connect - or no longer exist.
edgeRow = navEdgeFind(cur, nxt);
if(edgeRow < 0)
{
    botPathPlan(player);
    return 0;
}
edgeType = ds_grid_get(global.navEdges, NAV_EDGE_TYPE, edgeRow);

c0 = ds_grid_get(global.navNodes, NAV_NODE_X0, cur);
c1 = ds_grid_get(global.navNodes, NAV_NODE_X1, cur);
n0 = ds_grid_get(global.navNodes, NAV_NODE_X0, nxt);
n1 = ds_grid_get(global.navNodes, NAV_NODE_X1, nxt);
mx = navAnchorCol(char.x);

dirToNext = 0;
if((n0 + n1) > (c0 + c1))
    dirToNext = 1;
else if((n0 + n1) < (c0 + c1))
    dirToNext = -1;

// Default: head for the near end of the next surface, a couple of cells in, so the bot
// commits to standing on it rather than stopping on the boundary.
if(mx < n0)
    targetCol = min(n1, n0 + BOT_ENTRY_LEAD);
else if(mx > n1)
    targetCol = max(n0, n1 - BOT_ENTRY_LEAD);
else
{
    // Already over the next surface's columns without being on it. Two runs a row
    // apart genuinely overlap here - a node's span is in anchor columns and the body
    // box is NAV_BOX_W wide - so the answer is to keep going its way until
    // navNodeFromWorld agrees we have arrived, not to stand still.
    targetCol = max(n0, min(n1, mx + dirToNext * BOT_ENTRY_LEAD));
}

wantJump = false;

if(edgeType == NAV_EDGE_DROPTHROUGH)
{
    // navDropEdges takes the drop from the middle of the run, and holding DOWN
    // disables the platform entirely - both the standing test and the push-out (F24).
    targetCol = floor((c0 + c1) / 2);
    if(abs(mx - targetCol) <= BOT_ENTRY_LEAD)
        keys |= KEY_DOWN;
}
else if(edgeType == NAV_EDGE_FALL)
{
    // navFallEdges drops straight down from the cell just past one end of the run, and
    // the landing node contains that column - which is what says which end it was.
    if(c1 + 1 >= n0 and c1 + 1 <= n1)
        targetCol = c1 + BOT_ENTRY_LEAD;
    else
        targetCol = c0 - BOT_ENTRY_LEAD;
}
else if(edgeType == NAV_EDGE_JUMP or edgeType == NAV_EDGE_DOUBLEJUMP)
{
    // navJumpEdges takes off from the end of the run facing the landing, at full
    // horizontal speed, so walk to that end first and jump on arrival.
    if(dirToNext >= 0)
        takeoffCol = c1;
    else
        takeoffCol = c0;

    if(char.onground)
    {
        if(abs(mx - takeoffCol) <= BOT_JUMP_LEAD)
            wantJump = true;
        else
            targetCol = takeoffCol;
    }
}

// The target column is a direction hint, not a place to stop. Standing still on top of
// it is the one thing that must not happen: a cell is 6 world px, so a bot can sit
// within any sane tolerance of the column it is steering for and still not be on the
// node that column belongs to - which is exactly what it did the first time this ran,
// parking 4px short of a one-cell step and re-planning the identical route every 45
// ticks forever. So once it is on the target, keep nudging the way the next node lies
// and let navNodeFromWorld be the thing that decides it has arrived.
tx = navColWorldX(targetCol);
if(char.x < tx - BOT_STEER_TOL)
    keys |= KEY_RIGHT;
else if(char.x > tx + BOT_STEER_TOL)
    keys |= KEY_LEFT;
else if(dirToNext > 0)
    keys |= KEY_RIGHT;
else if(dirToNext < 0)
    keys |= KEY_LEFT;

if(wantJump)
{
    if(!player.botJumpHeld)
    {
        keys |= KEY_JUMP;
        player.botJumpHeld = true;
    }
    else
        player.botJumpHeld = false;
}
else
    player.botJumpHeld = false;

// Surfacer's stuck detector, widened from two ticks to BOT_STUCK_TICKS (F35): pressing
// something and going nowhere. Gated on actually pressing something, or a bot standing
// on its target waiting for a jump window would report itself stuck.
if(!moved and keys != 0)
    player.botStuckTicks += 1;
else
    player.botStuckTicks = 0;

if(player.botStuckTicks >= BOT_STUCK_TICKS)
{
    player.botStuckFires += 1;
    botBlacklistEdge(player, cur, nxt);
    botPathPlan(player);
    return 0;
}

return keys;
