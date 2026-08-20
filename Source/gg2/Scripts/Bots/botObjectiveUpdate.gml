/// botObjectiveUpdate(player)
/// Decides where a bot should be heading based on the current game mode's objective -
/// the "where" that milestone 5's botSetGoal only ever answered by hand, mirroring the
/// same instance_exists cascade basicRoomSetup.gml uses to pick a mode, since the mode
/// itself is never stored anywhere (F25).
///
/// CTF/Invasion and every ControlPoint-family mode (KOTH, DKOTH, Arena, A/D,
/// symmetrical CP) get real objective-seeking. Generator gets "walk to the enemy's
/// generator and fight there", since bots have no way to damage it yet. TDM has no
/// landmark at all, so bots keep the pre-milestone-6 behaviour of only fighting
/// whatever wanders into range.
///
/// Reissuing the goal is deliberately cheap to skip: botSetGoal forces an immediate
/// re-plan (M5), so calling it every tick with an unchanged destination would fight the
/// replan timer the path follower was built around. A goal is only reissued when the
/// bot does not have one yet or the target moved further than BOT_GOAL_RETARGET_DIST -
/// a stationary objective (a capture zone, a base) is set once and then left alone.

var player, char, wx, wy, found;
var ownBase, enemyFlag, enemyGen, enemyPoint, bestDist, cpTarget, zoneCp;
player = argument0;
char = player.object;
if(char == -1)
    exit;

found = false;

if(instance_exists(IntelligenceBase) or instance_exists(Intelligence))
{
    if(char.intel)
    {
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
    if(player.team == TEAM_RED)
        enemyGen = GeneratorBlue;
    else
        enemyGen = GeneratorRed;
    if(instance_exists(enemyGen))
    {
        wx = enemyGen.x;
        wy = enemyGen.y;
        found = true;
    }
}
else if(instance_exists(KothRedControlPoint) and instance_exists(KothBlueControlPoint))
{
    // DKOTH: each team caps the *other* team's point (F25).
    if(player.team == TEAM_RED)
        enemyPoint = KothBlueControlPoint;
    else
        enemyPoint = KothRedControlPoint;
    if(instance_exists(enemyPoint) and !enemyPoint.locked)
    {
        wx = enemyPoint.x;
        wy = enemyPoint.y;
        zoneCp = enemyPoint.id;
        with(CaptureZone)
        {
            if(cp == zoneCp)
            {
                wx = x;
                wy = y;
            }
        }
        found = true;
    }
}
else if(instance_exists(ControlPoint))
{
    // KOTH, Arena, symmetrical CP and A/D all fall through here: everyone heads for
    // whichever unlocked point is nearest to them, which naturally spreads bots across
    // a multi-point map instead of everyone piling onto the same one.
    bestDist = -1;
    with(ControlPoint)
    {
        if(!locked)
        {
            var d;
            d = point_distance(char.x, char.y, x, y);
            if(bestDist < 0 or d < bestDist)
            {
                bestDist = d;
                cpTarget = id;
            }
        }
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
                wx = x;
                wy = y;
            }
        }
        found = true;
    }
}

if(!found)
    exit;

// Map objects are not anchored the way a Character is (F24: chest, feet +23px) - a
// capture zone or a control point's marker sprite can sit well above the floor it
// belongs to, and guessing a fixed offset does not generalise (verified live: it
// happened to work for a dropped/based Intelligence instance and failed outright for
// a KothControlPoint's CaptureZone, off by ~70px). Search downward for the nearest
// resolvable node instead, then re-derive the goal from *that node's own* canonical
// position, so navNodeFromWorld is guaranteed to resolve it the same way again later.
var snapNode, snapY, snapLimit, ny, nx0, nx1, col;
snapNode = -1;
snapLimit = wy + NAV_MAX_FALL * NAV_CELL_SIZE;
for(snapY = wy; snapY <= snapLimit; snapY += NAV_CELL_SIZE)
{
    snapNode = navNodeFromWorld(wx, snapY);
    if(snapNode >= 0)
        break;
}
if(snapNode < 0)
    exit;

ny = ds_grid_get(global.navNodes, NAV_NODE_Y, snapNode);
nx0 = ds_grid_get(global.navNodes, NAV_NODE_X0, snapNode);
nx1 = ds_grid_get(global.navNodes, NAV_NODE_X1, snapNode);
col = navAnchorCol(wx);
if(col < nx0)
    col = nx0;
else if(col > nx1)
    col = nx1;
wx = navColWorldX(col);
wy = (ny + NAV_BOX_H) * NAV_CELL_SIZE - 23;

if(!player.botHasGoal or point_distance(wx, wy, player.botGoalX, player.botGoalY) > BOT_GOAL_RETARGET_DIST)
    botSetGoal(player, wx, wy);
