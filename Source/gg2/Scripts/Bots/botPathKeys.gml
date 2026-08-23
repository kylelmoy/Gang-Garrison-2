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
/// past the end of a surface, a drop-through goes down through its middle, a jump leaves
/// from a searched column and then flies a specific arc. Getting those from the same
/// numbers the build used is what keeps the follower honest about what it planned.
///
/// Jump is edge-triggered, not held. Character's Begin Step jumps on pressedKeys & $80
/// (a rising edge), so a bot holding JUMP down jumps exactly once and then never again;
/// botJumpHeld alternates so a bot that still wants to jump gets a fresh press every
/// other tick until it leaves the ground.

var player, char, keys, here, size, cur, nxt, i, edgeRow, edgeType, found, moved;
var mx, targetCol, tx, gx, n0, n1, c0, c1, takeoffCol, wantJump, dirToNext;
var needVx, braking, tracking, flightTicks, jumpDist, jumpDir, jumpWantX, vAlong;

player = argument0;
char = player.object;
keys = 0;

// Cleared up front and set only by the in-flight branch below, so every early return
// leaves it false. botInputUpdate's evasion behaviours read it: a bot part-way through a
// jump edge is flying a position-per-tick trajectory the generator validated, and an
// extra jump or a step in the air permanently ruins it (M6 part 5).
player.botFlyingEdge = false;

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
//
// ⚠️ Only while standing on something. navNodeFromWorld tolerates being a couple of cells
// off a surface, so an arc passing over its own landing resolves to that node ~15px before
// the feet reach it - and advancing there hands the follower the *next* edge while the bot
// is still in the air. Everything after that is wrong in the same breath: botAirTicks is
// the old arc's, so the new edge's tracker thinks the bot is already far behind its plan,
// and if that edge goes back the way this one came the bot brakes and flies backwards out
// of an arc that was going to land. Measured on ctf_truefort, both bases, the two stacked
// jumps every attacker takes (n273 -> n238 -> n125 and its mirror): the bot took off, was
// switched onto the return leg at the apex, landed back where it started and did it again
// - a whole team pacing at the enemy door for the rest of the round. It is also what the
// truefort-spawn-to-intel scenario had been failing on since the harness was written.
//
// Landing is the moment the question can honestly be answered, so it is the only moment it
// gets asked. An arc that ends somewhere the route does not mention still reads as off
// route on the tick it touches down, which is what the branch below is for.
here = -1;
if(char.onground)
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
// standing in a gap between two runs is a bot that has to re-plan, and a 28-tick arc is
// not - which is why the timer lives inside the onground branch and an airborne bot
// touches neither counter. It is flying a trajectory with its own end; the tick it lands
// is the tick either branch above has anything true to say.
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
        //
        // But not on the first miss. Since jump takeoffs became a search, a lot of real
        // edges are marginal - a three-column ledge reached by a slow steep arc - and
        // those are flown stochastically rather than deterministically. Banning one for
        // BOT_BLACKLIST_TICKS the first time it is missed costs five seconds of wandering
        // for an edge that is perfectly good, which measured as ~250 frames to complete a
        // hop that takes about 30: fifteen off-route events produced fifteen blacklists,
        // and the blacklist was the whole delay. So the same edge gets one retry, and
        // only a second consecutive failure takes it away. Two surfaces still cannot
        // become a loop, which is what the blacklist is for - it just costs one more
        // attempt to prove it.
        player.botOffRouteFires += 1;
        player.botOffPathTicks = 0;
        if(player.botEdgeFrom == player.botFailFrom and player.botEdgeTo == player.botFailTo)
            player.botFailCount += 1;
        else
        {
            player.botFailFrom = player.botEdgeFrom;
            player.botFailTo = player.botEdgeTo;
            player.botFailCount = 1;
        }
        if(player.botFailCount >= 2)
        {
            botBlacklistEdge(player, player.botEdgeFrom, player.botEdgeTo, "off");
            player.botFailCount = 0;
        }
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
    //
    // botPathStale disables the whole band. The route being followed is then one to a goal
    // that has already been replaced - kept only so the bot keeps moving until a plan for the
    // new goal exists (botSetGoal) - and its last node is somewhere the bot was sent before.
    // Reaching the end of it is not an arrival at anything, and declaring one would clear
    // botHasGoal and throw away the objective the bot had just been given.
    if(abs(char.x - gx) <= BOT_ARRIVE_TOL and !player.botPathStale)
    {
        if(char.onground and abs(char.hspeed) < 1)
        {
            player.botArrived = true;
            // The tick it arrived on, beside the other four diagnostics counters. Read
            // against the tick the goal was issued, this is how long the leg took - the
            // one number a navigation change can be compared on. Sampling it from outside
            // cannot recover it: arrival clears the goal, so a bot that has arrived and a
            // bot that never had a goal look identical a moment later, and the bot is free
            // to walk away in between.
            player.botArrivedAt = GameServer.frame;
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

// A new edge gets a fresh takeoff budget: BOT_TAKEOFF_PATIENCE is about one jump refusing
// to happen, not about how long the bot has been walking.
if(cur != player.botEdgeFrom or nxt != player.botEdgeTo)
    player.botTakeoffTicks = 0;

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
braking = false;
tracking = false;
needVx = 0;
jumpWantX = 0;

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
    // carries that column on the edge, exactly as a jump carries its takeoff. Which end
    // it was cannot be re-derived here: "the column just past the run is inside the
    // landing node" is true of BOTH ends wherever the landing surface reaches under the
    // whole run, which is what a platform standing on a wider ledge looks like, and the
    // old test picked the right-hand end whenever it was ambiguous. On ctf_avanti that
    // walked n92's bot into the solid block against its right end and wedged it there
    // (stuck, edge blacklisted, ~1100 ticks for a leg the graph priced at 545) when the
    // fall it wanted was off the left.
    //
    // The fallback is for a graph loaded from a cache written before falls carried a
    // takeoff: same guess as before, which is right whenever only one end works.
    takeoffCol = ds_grid_get(global.navEdges, NAV_EDGE_TAKEOFF, edgeRow);
    if(takeoffCol < 0)
    {
        if(c1 + 1 >= n0 and c1 + 1 <= n1)
            takeoffCol = c1 + 1;
        else
            takeoffCol = c0 - 1;
    }

    if(takeoffCol > c1)
        targetCol = c1 + BOT_ENTRY_LEAD;
    else
        targetCol = c0 - BOT_ENTRY_LEAD;

    // Off the edge, the modelled trajectory is a STRAIGHT VERTICAL DROP from the takeoff
    // column - navFallEdges swept straight down from it and credited whatever surface it
    // met - so the bot's job in the air is to hold that column, exactly the way a jump
    // holds its arc. Without this a fall is the one edge kind flown with no plan at all:
    // the bot walks off at whatever speed it had, keeps it (GG2 bleeds hspeed slowly),
    // and sails past any landing narrower than the drift. Found on cp_dirtbowl by the
    // blacklist log - `off:186>193`, a 12px step down onto a two-column ledge that the
    // bot walked off at ~6px/tick and overshot by two columns.
    //
    // The column is the one the edge carries, which is why this could not be written
    // before falls started carrying it: c1 + BOT_ENTRY_LEAD is a walk-off hint, deliberately
    // past the edge, and holding THAT would aim the drop a cell wide of the sweep that
    // proved it.
    if(!char.onground)
    {
        jumpWantX = navColWorldX(takeoffCol);
        tracking = true;
        // Same reason as a jump: a bot part-way through an edge the generator validated
        // must not be given an evasive hop that ruins it.
        player.botFlyingEdge = true;
    }
}
else if(edgeType == NAV_EDGE_JUMP or edgeType == NAV_EDGE_DOUBLEJUMP)
{
    // The takeoff column is carried on the edge, because navJumpTakeoff searched for
    // it rather than assuming it. It is usually the end of the run facing the landing,
    // but where the landing surface is also what ends the run - climbing onto a crate -
    // the body is flush against it there and the only flyable arcs start a few cells
    // back. Re-deriving c1/c0 here would jump from a column the build already rejected
    // and quietly turn those edges back into fictions.
    takeoffCol = ds_grid_get(global.navEdges, NAV_EDGE_TAKEOFF, edgeRow);
    if(takeoffCol < 0)
    {
        if(dirToNext >= 0)
            takeoffCol = c1;
        else
            takeoffCol = c0;
    }

    // A jump edge is flown as a *trajectory*, not as a speed. The generator validated
    // one specific arc - leave the takeoff column, cover NAV_EDGE_BUCKET px of ground a
    // tick, be over the landing when the arc comes back down - and every cell it
    // checked for clearance, and every surface it ruled out as landing somewhere else,
    // is about that arc and no other. So the bot's job in the air is to be where the
    // plan says it should be by now, and the two things it needs for that are the
    // planned speed and how long it has been flying.
    //
    // Holding a speed instead is what this used to do, and it is not the same thing:
    // the bot starts from a standstill and takes four or five ticks to reach a slow
    // arc's speed, which is most of a cell of ground lost with nothing to make it back,
    // and any nudge in the air is permanent. Tracking a position corrects both, because
    // being behind is a reason to press and being ahead is a reason to brake. Measured
    // over every class, rise, ledge width and run-up: 12-19% of jumps landed on the node
    // they were aimed at before, 100% after. (Both halves of that number matter - the
    // other half is navJumpFlight no longer handing out arcs that were never going to
    // land there anyway.)
    //
    // Ticks are counted rather than read off char.vspeed, which would otherwise give
    // the phase of the arc for free: vspeed pins at 10 once the fall reaches terminal
    // velocity, and every phase after that reads as the same tick.
    needVx = ds_grid_get(global.navEdges, NAV_EDGE_BUCKET, edgeRow);
    flightTicks = ds_grid_get(global.navEdges, NAV_EDGE_TICKS, edgeRow);
    jumpDist = needVx * flightTicks;

    // The generator's own direction, not the one inferred from node midpoints: it is
    // the side of the takeoff column the landing is on, and a wide surface can straddle
    // the midpoint test.
    jumpDir = dirToNext;
    if(n0 > takeoffCol)
        jumpDir = 1;
    else if(n1 < takeoffCol)
        jumpDir = -1;

    // Speed *along the jump*, not speed. This is the whole of the run-up problem: the old
    // gate was abs(hspeed) <= needVx + 1, which is satisfied by a bot drifting the wrong
    // way at 2px/tick, so it left the ground with backwards momentum and the tracker spent
    // the arc trying to undo it - and GG2 gives almost no authority in the air. Reported
    // from play at ctf_truefort 4470,840: "the bot has momentum going left, and can't gain
    // enough speed going right to make the jump to the right stairs. Bot needs to go
    // further left for a running start." That is exactly the fix below, and it is the same
    // shape as the n616 -> n575 wedge on the same map.
    vAlong = char.hspeed * jumpDir;

    if(char.onground)
    {
        if(abs(mx - takeoffCol) <= BOT_JUMP_LEAD)
        {
            // At the gate. Three ways this can go, and only one of them is a jump.
            //
            // The budget counts ticks spent *here*, refusing to leave, and nothing but a
            // takeoff or a change of edge clears it - deliberately, because the failure it
            // exists for is a bot that shuffles between the gate and its run-up forever.
            // Counting the approach as well would spend it on a long walk and fire a jump
            // from the middle of the run, which is what broke valley-spawn-to-point the
            // first time this was written.

            // The rule is "not moving away from the jump", not "moving at exactly the arc's
            // speed", and the difference is measured. GG2 applies the same controlFactor in
            // the air as on the ground (Character.Begin Step sets it from moveStatus, not
            // from onground), so a bot that leaves slow can be pressed back up to the arc's
            // speed within two or three ticks by the in-flight tracker below - which is why
            // slow takeoffs were already landing. A bot that leaves with speed *against* the
            // jump cannot: it spends those ticks undoing the drift and covers a good ten
            // pixels the wrong way first, on an arc whose height is already fixed.
            //
            // Demanding the full speed at the gate instead was tried, and it costs a lot for
            // nothing: every leg between two jumps became a series of run-ups and brakes,
            // 647 -> 868 and 674 -> 997 ticks on the valley scenarios, with no more arrivals
            // to show for it.
            //
            // The upper tolerance is not slop. A steep arc can want less than 0.3px/tick and
            // a braking character oscillates either side of zero by about that much.
            if(vAlong >= 0 and vAlong <= needVx + BOT_JUMP_VTOL)
            {
                wantJump = true;
                player.botAirTicks = 0;
                player.botTakeoffTicks = 0;
            }
            // Faster than the arc allows. Worth bleeding off even though the tracker can
            // correct it: with no key held GG2 sheds horizontal speed by only about 13% a
            // tick, so a bot arriving at 9 is still over 3 some eight ticks later.
            else if(vAlong > needVx + BOT_JUMP_VTOL)
                braking = true;
            // Moving away from the jump. Backing up is the only answer that works: pressing
            // forward from here would walk the bot off the end of the run it is standing on,
            // which is usually a ledge, and jumping anyway is what produced the short arcs
            // in the first place - the bot arcs out with its old momentum still on it and
            // lands back where it started. Reported from play at ctf_truefort 4470,840.
            // Clamped into this node's own columns so the run-up never steps off the far end
            // either.
            else
            {
                targetCol = takeoffCol - jumpDir * BOT_RUNUP_CELLS;
                if(targetCol < c0)
                    targetCol = c0;
                if(targetCol > c1)
                    targetCol = c1;
            }

            // ⚠️ The escape hatch, because a gate that can refuse is a gate that can refuse
            // forever - a bot on a run too short to build the speed, or wedged against a
            // wall it cannot back away from, would otherwise work the gate for the rest of
            // the round with every other detector reading it as healthy: it is not stuck
            // (it is moving) and it is not off route (it is standing exactly where the
            // route says). Jump on whatever it has instead. That either works, or it lands
            // back where it started and the off-route machinery already knows what to do
            // with an edge that keeps doing that.
            if(player.botTakeoffTicks >= BOT_TAKEOFF_PATIENCE)
            {
                wantJump = true;
                braking = false;
                player.botAirTicks = 0;
                player.botTakeoffTicks = 0;
            }
        }
        else
        {
            // Approaching. Arrive at about the arc's speed rather than sprinting at the
            // gate and braking on top of it: a bot that arrives at 9 and only then starts
            // shedding speed drifts past the one-cell window while it does, backs up, and
            // comes at it again.
            //
            // ⚠️ Only over the last stretch, and that distance is load-bearing. Bleeding
            // speed for the whole leg makes every walk between two jumps happen at 2-4
            // px/tick instead of 7-9 - measured, it cost 30-50% on all three valley
            // scenarios (647 -> 868 ticks and the like) while changing nothing about
            // whether they arrived. BOT_RUNUP_CELLS does double duty here: the distance a
            // bot needs to build the arc's speed is also the distance it needs to shed it.
            if(vAlong > needVx + BOT_JUMP_VTOL and abs(mx - takeoffCol) <= BOT_RUNUP_CELLS)
                braking = true;
            else
                targetCol = takeoffCol;
        }
    }
    else
    {
        player.botAirTicks += 1;

        // Where the plan says to be now, clamped at the landing so a bot that is late
        // keeps pressing toward it rather than aiming past it.
        jumpWantX = navColWorldX(takeoffCol)
                  + jumpDir * min(jumpDist, needVx * player.botAirTicks);
        tracking = true;
        player.botFlyingEdge = true;
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

// In the air on a jump edge, the planned trajectory replaces the steering entirely:
// steering aims at a column to walk to, and there is no walking to be done. Behind the
// plan is a press forward, ahead of it is a press back, which is a brake and is how a
// player stops drifting too. The tolerance is a pixel because that is roughly what one
// tick of a slow arc covers, and chattering the key either side of the line is exactly
// what holds the average speed where it belongs.
//
// Braking on the ground is the same idea before the arc starts, and both replace the
// steering keys rather than adding to them, so the bot cannot brake and steer in one
// tick.
//
// Neither caps the *approach*. Braking on the way to the takeoff column - so the bot
// arrives already travelling at the arc's speed rather than accelerating into it from a
// stop - sounds better, measured no better on koth_valley (three trials at <90, 273 and
// 277 frames against 220 and 239 without it), and measured no better again in the
// offline model that produced the tracking law. It stays out.
if(braking)
{
    keys = keys & ~(KEY_LEFT | KEY_RIGHT);
    if(char.hspeed > 0)
        keys |= KEY_LEFT;
    else if(char.hspeed < 0)
        keys |= KEY_RIGHT;
}
else if(tracking)
{
    keys = keys & ~(KEY_LEFT | KEY_RIGHT);
    if(char.x < jumpWantX - 1)
        keys |= KEY_RIGHT;
    else if(char.x > jumpWantX + 1)
        keys |= KEY_LEFT;
}

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
    botBlacklistEdge(player, cur, nxt, "stk");
    botPathPlan(player);
    return 0;
}

return keys;
