/// navNodeFromWorld(wx, wy)
/// Returns the node a character standing at world (wx, wy) is on, or -1.
///
/// A Character's origin sits at its chest, with the feet about 23px below (F24), and a
/// node is the anchor of a box whose bottom rests on the surface. So the search starts
/// from the cell the feet are in and looks a little way up and down: exactly which row
/// matches depends on the class, since NAV_BOX_H is the conservative Heavy box and most
/// classes are shorter. Horizontally it goes through navAnchorCol, because a node's
/// x-span is in anchor columns and a Character's x is the centre of its body.
///
/// Neither axis demands an exact hit. A bot mid-step, or standing a cell past the end
/// of a run, still has to resolve to the surface it is plainly on - returning -1 there
/// would make the path follower think it had fallen off the graph and re-plan, which is
/// how a bot ends up thrashing in place. Height is weighted above horizontal distance
/// in the tie-break: two surfaces stacked a few rows apart are a much likelier
/// confusion than two on the same row.
///
/// (The tie-break variable is called `rank` and not the obvious `score` because `score`
/// is a GM8 built-in global, and declaring it with var is a compilation error that only
/// surfaces at startup, as a dialog no log names.)
///
/// ⚠️ The feet row is rounded to the NEAREST row boundary, not floored, and that one word
/// is the difference between a bot that walks a staircase and one that hops up it. A node's
/// feet sit exactly on a row boundary - navSetGoalNode and the scenario runner both derive
/// their stand y as `(ny + NAV_BOX_H) * NAV_CELL_SIZE - 23` - but GG2 rests a Character
/// with its feet a pixel *above* the surface it is standing on, so flooring puts a
/// perfectly stationary bot in the row above the one it is plainly standing in. On a wide
/// floor nothing notices: the node spans dozens of columns and wins on dx anyway. On
/// stepped terrain - a staircase, a 45-degree ramp, anything the mask turns into a chain of
/// one-column nodes - the node one row up is also one column across, so it wins the
/// tie-break, and the bot believes it is standing on the step behind the one it is on.
///
/// Everything downstream inherits that. Measured on ctf_truefort, standing still at the
/// exact stand position of n616 (876, 835): resolving 835 gives n616 and resolving 834 -
/// which is where the engine actually rests the body - gives n608, the step above. The path
/// follower therefore ran the *previous* edge, walked one cell further before the index
/// advanced, and only then fired the jump - from a cell that is 6px lower down the ramp,
/// which is exactly the margin by which the arc then failed to reach its landing (feet at
/// 821 against a surface at 816). It also means a bot on a staircase is forever one step
/// behind its own route, which is what "bots always jump at the staircases" looks like from
/// the outside.
///
/// Linear over nodes rather than using the cell grid, because that grid is build
/// scaffolding and is freed once the graph is done. A few hundred nodes is nothing at
/// the cadence bots re-plan at.

var wx, wy, mx, my, i, ny, nx0, nx1, best, bestScore, dx, dy, rank, anchor;
wx = argument0;
wy = argument1;

if(!global.navReady)
    return -1;

mx = navAnchorCol(wx);
my = round((wy + 23) / NAV_CELL_SIZE);

best = -1;
bestScore = 999999;

for(i = 0; i < global.navNodeCount; i += 1)
{
    ny = ds_grid_get(global.navNodes, NAV_NODE_Y, i);

    // Where this node's feet are: the row just under the box.
    anchor = ny + NAV_BOX_H;
    dy = abs(anchor - my);
    if(dy > 3)
        continue;

    nx0 = ds_grid_get(global.navNodes, NAV_NODE_X0, i);
    nx1 = ds_grid_get(global.navNodes, NAV_NODE_X1, i);
    dx = 0;
    if(mx < nx0)
        dx = nx0 - mx;
    else if(mx > nx1)
        dx = mx - nx1;
    if(dx > 2)
        continue;

    rank = dy * 4 + dx;
    if(rank < bestScore)
    {
        bestScore = rank;
        best = i;
    }
}

return best;
