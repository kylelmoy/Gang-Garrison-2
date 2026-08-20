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
/// Linear over nodes rather than using the cell grid, because that grid is build
/// scaffolding and is freed once the graph is done. A few hundred nodes is nothing at
/// the cadence bots re-plan at.

var wx, wy, mx, my, i, ny, nx0, nx1, best, bestScore, dx, dy, rank, anchor;
wx = argument0;
wy = argument1;

if(!global.navReady)
    return -1;

mx = navAnchorCol(wx);
my = floor((wy + 23) / NAV_CELL_SIZE);

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
