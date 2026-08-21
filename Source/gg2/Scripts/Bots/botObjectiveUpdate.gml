/// botObjectiveUpdate(player)
/// Decides where a bot should be heading based on the current game mode's objective -
/// the "where" that milestone 5's botSetGoal only ever answered by hand, mirroring the
/// same instance_exists cascade basicRoomSetup.gml uses to pick a mode, since the mode
/// itself is never stored anywhere (F25).
///
/// CTF/Invasion and every ControlPoint-family mode (KOTH, DKOTH, Arena, A/D,
/// symmetrical CP) get real objective-seeking. TDM has no landmark at all, so bots keep
/// the pre-milestone-6 behaviour of only fighting whatever wanders into range.
///
/// Milestone 7 tier 3 added five things on top, and they compose in this order:
///
///   class    a Medic's goal is a moving *instance* - the ally it is following - rather
///            than a world point at all (M7 6.2), so it is decided first and returns
///            early. Before tier 3 this script had zero references to `class`.
///   role     botRole splits the team (botRoleAssign). A defender's anchor is its *own*
///            objective rather than the enemy's - the same cascade, mirrored. Before
///            this every bot in every mode ran at the enemy objective and nothing was
///            ever behind them.
///   held     once the objective is ours, a defender takes ground overlooking it (M7
///            5.2) and an attacker walks out toward the enemy spawn and holds *that*
///            ground (M7 2.2), instead of either of them standing on the point.
///   spot     for a goal that is "a place from which I can do X" rather than "this
///            point", botGoalSpot picks the node (M7 6.3, 5.2). Two cases use it: a
///            firing position on a Generator, which is *shot* rather than stood on - at
///            maxHp 2100 that is a sustained-fire job from range, and standing on it was
///            never the goal - and the defender's overlook above.
///   spread   a per-bot lateral offset (botSpreadX) so a team does not converge on one
///            pixel and then stand in each other's line of fire (M7 2.4).
///
/// Reissuing the goal is deliberately cheap to skip: botSetGoal forces an immediate
/// re-plan (M5), so calling it every tick with an unchanged destination would fight the
/// replan timer the path follower was built around. botSetGoalNode owns that test - a
/// goal is only reissued when the bot does not have one yet or the target moved further
/// than BOT_GOAL_RETARGET_DIST, so a stationary objective is set once and then left alone.
///
/// ⚠️ The hold-ground trigger is a *distance* to the objective, not player.botArrived,
/// and that is not a detail. botArrived is cleared by botSetGoal, so a trigger keyed to
/// it flips off the moment it fires: bot arrives, takes high ground, botArrived clears,
/// next objective tick it no longer qualifies, walks back to the point, arrives, and
/// oscillates between the two forever at 30-tick intervals. A distance test is stable
/// because the spot it chooses is itself inside the radius that chose it.

var player, char, wx, wy, found, anchorX, anchorY, useSpot, held;
var spotMin, spotMax, spotHigh, spotNode, snapNode, spreadX;
var ownBase, enemyFlag, targetGen, enemyPoint, bestDist, cpTarget, zoneCp, defending;
var ally, foe, spawn, pushLen, pushX, pushY;

player = argument0;
char = player.object;
if(char == -1)
    exit;

// A spot goal is chosen without checking reachability (see botGoalSpot's header), so a
// spot in another component presents as a goal that never plans. Notice that here - the
// one place that can - and stop trying spots for a while rather than leaving the bot
// standing at spawn wanting something it cannot walk to. botHasGoal is what separates
// "planning failed" from "arrived": arrival clears the goal and frees the path together.
if(player.botGoalIsSpot and player.botHasGoal and player.botPath < 0)
    player.botSpotBanUntil = GameServer.frame + 300;

// --- the Medic's follow-goal (M7 6.2) -------------------------------------------------
//
// This script had zero references to `class` before tier 3, so a Medic pathed to the enemy
// intel exactly like a Soldier and healed whoever happened to be standing near the route
// it walked alone. A Medic is the one class for which *never engaging* is correct play,
// and the thing it should be following is not a fixed world point at all - it is a moving
// instance.
//
// It goes first and returns early, ahead of the whole game-mode cascade, because a Medic
// following a team-mate is doing its job in every mode and the objective is that
// team-mate's problem. With nobody to follow it falls through and behaves like everyone
// else, which is the right thing to do with a Medic that has spawned alone.
//
// BOT_GOAL_RETARGET_DIST gives the re-issue throttle for free: a moving ally naturally
// trips the 48px test, which is exactly the case that check was written for, while an ally
// standing still does not and the goal is left alone.
if(player.class == CLASS_MEDIC and !char.intel)
{
    ally = botFindAlly(char, BOT_MEDIC_FOLLOW_RANGE);
    if(ally != noone)
    {
        wx = ally.x;
        wy = ally.y;

        // Keep the ally between me and the enemy: step to the far side of them from
        // whatever this bot is currently looking at. Horizontal only - the goal is a
        // place to stand, and standing is a one-dimensional choice on a given surface.
        foe = player.botTarget;
        if(foe != noone)
        {
            if(instance_exists(foe))
            {
                if(foe.x > ally.x)
                    wx -= BOT_MEDIC_OFFSET;
                else
                    wx += BOT_MEDIC_OFFSET;
            }
        }

        snapNode = botNodeSnap(wx, wy);
        if(snapNode < 0)
            snapNode = botNodeSnap(ally.x, ally.y);
        if(snapNode >= 0)
        {
            botSetGoalNode(player, snapNode, wx, false);
            exit;
        }
    }
}

found = false;
useSpot = false;
held = false;
anchorX = 0;
anchorY = 0;
spotMin = 0;
spotMax = 0;
spotHigh = 0;
defending = (player.botRole == BOT_ROLE_DEFEND);

if(instance_exists(IntelligenceBase) or instance_exists(Intelligence))
{
    if(char.intel)
    {
        // Carrying: get it home. Roles do not apply - there is exactly one thing to do
        // with an enemy intel and it is not "guard something else while holding it".
        if(player.team == TEAM_RED)
            ownBase = IntelligenceBaseRed;
        else
            ownBase = IntelligenceBaseBlue;
        if(instance_exists(ownBase))
        {
            wx = ownBase.x;
            wy = ownBase.y;
            found = true;
        }
    }
    else if(defending)
    {
        // Guard our own flag - the flag object rather than its base marker, because the
        // thing worth standing near is wherever the flag currently *is*, including
        // dropped in the open halfway across the map, which is exactly the moment a
        // defender earns its place.
        if(player.team == TEAM_RED)
            enemyFlag = IntelligenceRed;
        else
            enemyFlag = IntelligenceBlue;
        if(instance_exists(enemyFlag))
        {
            wx = enemyFlag.x;
            wy = enemyFlag.y;
            found = true;
        }
    }
    else
    {
        if(player.team == TEAM_RED)
            enemyFlag = IntelligenceBlue;
        else
            enemyFlag = IntelligenceRed;
        if(instance_exists(enemyFlag))
        {
            wx = enemyFlag.x;
            wy = enemyFlag.y;
            found = true;
        }
    }
}
else if(instance_exists(Generator))
{
    // The objective here is to *destroy* a generator, not to touch one - each team both
    // defends its own and attacks the other's, and a generator is shot from wherever a
    // bot has line of sight to it. So this branch is the goal layer's whole reason for
    // existing: the anchor is the generator, and the goal is a place to shoot it from.
    if(defending)
    {
        if(player.team == TEAM_RED)
            targetGen = GeneratorRed;
        else
            targetGen = GeneratorBlue;
    }
    else
    {
        if(player.team == TEAM_RED)
            targetGen = GeneratorBlue;
        else
            targetGen = GeneratorRed;
    }
    if(instance_exists(targetGen))
    {
        // A Generator's origin is not its middle, and the middle is what range and sight
        // want to be measured to - the same correction the CaptureZone branches below
        // make, and for the same reason.
        wx = (targetGen.bbox_left + targetGen.bbox_right) / 2;
        wy = (targetGen.bbox_top + targetGen.bbox_bottom) / 2;

        // A defender wants to be *near* its own generator rather than lined up on it, so
        // only the attacker's goal is a firing position. BOT_SPOT_BAND keeps that
        // position comfortably inside the weapon's reach instead of on the very edge of
        // it, where a target taking one step is out of range.
        if(!defending)
        {
            anchorX = wx;
            anchorY = wy;
            spotMin = max(botClassMinBand(player.class), 1);
            spotMax = botClassRange(player.class) * BOT_SPOT_BAND;
            spotHigh = 0;
            useSpot = true;
        }
        found = true;
    }
}
else if(instance_exists(KothRedControlPoint) and instance_exists(KothBlueControlPoint))
{
    // DKOTH: each team caps the *other* team's point (F25), so a defender's point is the
    // one its own team is trying to hold.
    if(defending)
    {
        if(player.team == TEAM_RED)
            enemyPoint = KothRedControlPoint;
        else
            enemyPoint = KothBlueControlPoint;
    }
    else
    {
        if(player.team == TEAM_RED)
            enemyPoint = KothBlueControlPoint;
        else
            enemyPoint = KothRedControlPoint;
    }
    if(instance_exists(enemyPoint))
    {
        // Head for the point even while it is still locked (M7 2.5): cpUnlock holds
        // every DKOTH point locked for 900 ticks (30s), during which a bot used to have
        // no goal at all and stood frozen at spawn while a human player would already be
        // walking out to take the ground before it opens.
        wx = enemyPoint.x;
        wy = enemyPoint.y;
        zoneCp = enemyPoint.id;
        with(CaptureZone)
        {
            if(cp == zoneCp)
            {
                // The middle of the zone rather than its top-left origin - see the
                // generic control-point branch below for what standing on the
                // boundary costs.
                wx = (bbox_left + bbox_right) / 2;
                wy = (bbox_top + bbox_bottom) / 2;
            }
        }
        held = (enemyPoint.team == player.team
                and point_distance(char.x, char.y, wx, wy) <= BOT_HOLD_RADIUS);
        found = true;
    }
}
else if(instance_exists(ControlPoint))
{
    // KOTH, Arena, symmetrical CP and A/D all fall through here: everyone heads for
    // whichever unlocked point is nearest to them, which naturally spreads bots across
    // a multi-point map instead of everyone piling onto the same one.
    //
    // Every point is locked for the first 900 ticks (30s) of a KOTH/DKOTH round and 1800
    // (60s) of an Arena round, during which the loop below used to find nothing and leave
    // the bot with no goal at all (M7 2.5) - a human walks out immediately to be standing
    // on the point the moment it opens, so track the nearest point regardless of lock
    // state as a fallback and only fall back to it once no unlocked point exists.
    //
    // A defender prefers a point its own team already holds - the same nearest-point loop
    // with everything that is *not* ours pushed 2000px away, which is more than any map
    // is wide. Penalising the others rather than rewarding ours keeps every d >= 0, which
    // is what lets -1 go on meaning "no point found" in both accumulators below. On a
    // single-point map (every KOTH map) it resolves to the same point either way, and the
    // split then shows up in what a defender does once it is there rather than in where
    // it goes.
    bestDist = -1;
    var bestAnyDist, anyTarget, d, wantTeam;
    bestAnyDist = -1;
    wantTeam = player.team;
    with(ControlPoint)
    {
        d = point_distance(char.x, char.y, x, y);
        if(defending and team != wantTeam)
            d += 2000;
        if(bestAnyDist < 0 or d < bestAnyDist)
        {
            bestAnyDist = d;
            anyTarget = id;
        }
        if(!locked and (bestDist < 0 or d < bestDist))
        {
            bestDist = d;
            cpTarget = id;
        }
    }
    if(bestDist < 0)
    {
        bestDist = bestAnyDist;
        cpTarget = anyTarget;
    }
    if(bestDist >= 0)
    {
        wx = cpTarget.x;
        wy = cpTarget.y;
        zoneCp = cpTarget;
        with(CaptureZone)
        {
            if(cp == zoneCp)
            {
                // The middle of the zone, not its origin. A CaptureZone's origin is its
                // top-left corner, so aiming there asks the follower to stop on the exact
                // boundary of the thing it is trying to stand in - and arrival is only
                // accurate to BOT_ARRIVE_TOL. Measured on koth_valley: the bot climbed
                // the whole four-jump chain, stopped 3px short of the zone's left edge,
                // and captured nothing. The zone is 125px wide; its centre is not a
                // near miss.
                wx = (bbox_left + bbox_right) / 2;
                wy = (bbox_top + bbox_bottom) / 2;
            }
        }
        // Same as the DKOTH branch above (M7 2.1/5.2/2.2).
        held = (cpTarget.team == player.team
                and point_distance(char.x, char.y, wx, wy) <= BOT_HOLD_RADIUS);
        found = true;
    }
}

if(!found)
    exit;

// --- the point is already ours: hold it, or push past it ------------------------------
//
// Arrival is a state, not a terminus (M7 2.1). A capture zone never moves, so without
// something here a bot that reaches an already-held point freezes on it forever - botPath
// goes to -1 on arrival and nothing before tier 1 ever re-tasked it. Tier 1 stood a random
// 100px jitter in for this; tier 3 replaces it with the two things a player actually does,
// split by role, which is the first place the role split earns its keep on a mode that has
// only one objective:
//
//   defend (M7 5.2)  take ground that *overlooks* the point rather than standing in the
//                    open on it. Height is what makes a position advantageous and it is
//                    the one part of "a good position" that is cheap to ask for, so
//                    spotHigh is the whole model - no sightline graph, no cover map.
//   attack (M7 2.2)  walk out toward where the enemy will come from and take that ground,
//                    so the point is defended in front of itself rather than on top of
//                    itself. Capped at BOT_PUSH_DIST from the objective on purpose:
//                    loitering outside an enemy spawn is a bad strategy, not an aggressive
//                    one - players retreat inside, heal to full, and walk back out, while
//                    the bot has given up the thing it was holding.
if(held)
{
    if(defending)
    {
        anchorX = wx;
        anchorY = wy;
        spotMin = BOT_ARRIVE_TOL;
        spotMax = BOT_HOLD_RADIUS;
        spotHigh = BOT_SPOT_HIGH_BONUS;
        useSpot = true;
    }
    else
    {
        spawn = botEnemySpawn(player.team, wx, wy);
        if(spawn != noone)
        {
            pushX = (spawn.x - wx) * BOT_PUSH_FRAC;
            pushY = (spawn.y - wy) * BOT_PUSH_FRAC;
            pushLen = point_distance(0, 0, pushX, pushY);
            if(pushLen > BOT_PUSH_DIST)
            {
                pushX = pushX * BOT_PUSH_DIST / pushLen;
                pushY = pushY * BOT_PUSH_DIST / pushLen;
            }
            wx += pushX;
            wy += pushY;
        }
    }
}

// --- the goal layer: a place from which to do something, or the thing itself ----------

if(useSpot and GameServer.frame >= player.botSpotBanUntil)
{
    spotNode = botGoalSpot(char, anchorX, anchorY, spotMin, spotMax, true, spotHigh);
    if(spotNode >= 0)
    {
        botSetGoalNode(player, spotNode, global.botSpotX, true);
        exit;
    }
    // Nothing qualified: fall through to the objective's own node, which is what this
    // script did before the goal layer existed.
}

// A per-bot lateral offset, so a team heading for one objective arrives spread along it
// rather than stacked on one column (M7 2.4), and a defender sits beside what it is
// guarding rather than on top of it.
spreadX = player.botSpreadX;
if(defending)
{
    if(spreadX >= 0)
        spreadX += BOT_DEFEND_RADIUS;
    else
        spreadX -= BOT_DEFEND_RADIUS;
}

// The objective's own node is resolved first and is the answer unless the spread earns
// its way in. That order matters, and getting it the other way round is a defect I
// shipped for one build: botNodeSnap searches *downward*, so snapping an already-offset
// position can land on a floor several storeys below the objective - the offset steps off
// the edge of the platform the intel is on and the search falls all the way to the ground.
// A bot then walks confidently to a place with nothing to do with its objective, which is
// far worse than not spreading at all.
//
// So an offset snap is accepted only when it lands at roughly the same height as the
// objective itself - within a body's height, which is what makes it "the same level"
// rather than "the same surface", so a spread can still cross between two runs that meet
// at a step. Anything else falls back to the objective's node, where botSetGoalNode's own
// clamp still spreads the bot along that node's columns for free.
snapNode = botNodeSnap(wx, wy);
if(snapNode < 0)
    exit;

if(spreadX != 0)
{
    var tryNode;
    tryNode = botNodeSnap(wx + spreadX, wy);
    if(tryNode >= 0)
    {
        if(abs(ds_grid_get(global.navNodes, NAV_NODE_Y, tryNode)
               - ds_grid_get(global.navNodes, NAV_NODE_Y, snapNode)) <= NAV_BOX_H)
            snapNode = tryNode;
        else
            spreadX = 0;
    }
    else
        spreadX = 0;
}

botSetGoalNode(player, snapNode, wx + spreadX, false);
