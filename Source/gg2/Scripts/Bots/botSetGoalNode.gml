/// botSetGoalNode(player, node, preferX, isSpot)
/// Issues a goal that lands exactly on a nav node, at whichever of that node's columns is
/// nearest preferX. Returns true if a goal was issued, false if it was already there.
///
/// Every objective in the game is an *object* position, and map objects are not anchored
/// the way a Character is (F24: chest, feet +23px) - a capture zone's marker sprite can
/// sit 70px above the floor it belongs to, and there is no fixed offset that generalises.
/// So the rule everywhere in this codebase is: resolve the objective to a node, then
/// re-derive the goal from *that node's own* canonical stand position, which guarantees
/// navNodeFromWorld resolves it back to the same node when the follower asks later. This
/// is that arithmetic, in one place, now that three callers want it.
///
/// Reissuing is deliberately cheap to skip. botSetGoal forces an immediate re-plan (M5),
/// so calling it every tick with an unchanged destination would fight the replan timer the
/// path follower was built around - hence the BOT_GOAL_RETARGET_DIST test rather than an
/// unconditional set. A stationary objective is set once and then left alone.
///
/// isSpot records whether this goal came out of botGoalSpot's "a place from which I can do
/// X" search rather than being the objective itself. botObjectiveUpdate needs to know,
/// because a spot is chosen without checking reachability and a spot that turns out to be
/// in another component has to be given up on rather than retried forever.

var player, node, preferX, isSpot, ny, nx0, nx1, col, wx, wy, moved;

player = argument0;
node = argument1;
preferX = argument2;
isSpot = argument3;

if(node < 0)
    return false;
if(!global.navReady)
    return false;
if(node >= global.navNodeCount)
    return false;

ny = ds_grid_get(global.navNodes, NAV_NODE_Y, node);
nx0 = ds_grid_get(global.navNodes, NAV_NODE_X0, node);
nx1 = ds_grid_get(global.navNodes, NAV_NODE_X1, node);

col = navAnchorCol(preferX);
if(col < nx0)
    col = nx0;
else if(col > nx1)
    col = nx1;

wx = navColWorldX(col);
wy = (ny + NAV_BOX_H) * NAV_CELL_SIZE - 23;

player.botGoalIsSpot = isSpot;

moved = true;
if(player.botHasGoal)
    moved = (point_distance(wx, wy, player.botGoalX, player.botGoalY) > BOT_GOAL_RETARGET_DIST);
if(!moved)
    return false;

botSetGoal(player, wx, wy);
return true;
