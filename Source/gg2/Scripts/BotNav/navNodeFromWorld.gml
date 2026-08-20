/// navNodeFromWorld(wx, wy)
/// Returns the node a character standing at world (wx, wy) is on, or -1.
///
/// A Character's origin sits at its chest, with the feet about 23px below (F24), and
/// a node is the anchor of a box whose bottom rests on the surface. So the search
/// starts from the cell the feet are in and looks a little way up and down: exactly
/// which row matches depends on the class, since NAV_BOX_H is the conservative Heavy
/// box and most classes are shorter.
///
/// Linear over nodes rather than using the cell grid, because that grid is build
/// scaffolding and is freed once the graph is done. A few hundred nodes is nothing at
/// the cadence bots re-plan at.

var wx, wy, mx, my, i, ny, nx0, nx1, best, bestDist, d, anchor;
wx = argument0;
wy = argument1;

if(!global.navReady)
    return -1;

mx = floor(wx / NAV_CELL_SIZE);
my = floor((wy + 23) / NAV_CELL_SIZE);

best = -1;
bestDist = 999999;

for(i = 0; i < global.navNodeCount; i += 1)
{
    ny = ds_grid_get(global.navNodes, NAV_NODE_Y, i);
    nx0 = ds_grid_get(global.navNodes, NAV_NODE_X0, i);
    nx1 = ds_grid_get(global.navNodes, NAV_NODE_X1, i);

    if(mx < nx0 or mx > nx1)
        continue;

    // Where this node's feet are: the row just under the box.
    anchor = ny + NAV_BOX_H;
    d = abs(anchor - my);
    if(d <= 3 and d < bestDist)
    {
        bestDist = d;
        best = i;
    }
}

return best;
