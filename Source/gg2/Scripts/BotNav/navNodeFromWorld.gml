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
/// Only seven mask rows can ever pass the dy test below - the feet row plus three either
/// side - so the search goes through navRowStart, which gives the first node on a row
/// directly, rather than reading every node on the map to reject almost all of them.
///
/// This used to be a linear scan over every node, on the grounds that "a few hundred
/// nodes is nothing at the cadence bots re-plan at". The cadence was the wrong thing to
/// look at. botNodeSnap calls this once per 6px step over a 900px fall, so one snap was
/// up to 151 whole-graph scans, and botObjectiveUpdate makes up to three snaps per bot
/// per second. Measured live on ctf_truefort with 687 nodes and twelve bots: 0.65ms a
/// call, 28.9ms for a typical botNodeSnap and 93.8ms for one that finds nothing, against
/// a 33.3ms frame - which is the periodic hitch, not a re-plan cost at all.
///
/// Nodes are emitted sorted by y then x, so the nodes of one row are contiguous and a row
/// ends at the first node whose y differs. Walking the rows in ascending order therefore
/// visits exactly the nodes the old scan would have accepted, in the same index order, so
/// the strict `<` below still resolves a tie to the same node it always did.
///
/// navRowStart is derived by navCacheLoad, not stored in the cache file: it is one entry
/// per mask row, so rebuilding it on load costs a rounding error against the parse that
/// just happened and keeping it costs the same against the graph it indexes.
///
/// ⚠️ It is used only when navRowFor says it was built from the node grid that is installed
/// right now, and the linear scan below is what runs otherwise. That guard is not
/// paranoia: the nav unit tests install a fixture straight onto global.navNodes and set
/// navReady by hand, without going anywhere near a build, so an index left over from a
/// real graph would still be sitting there indexing rows that no longer exist. A stale
/// index does not fail loudly - it returns a node, just the wrong one - so the cost of
/// getting this wrong is silently mis-resolved positions everywhere downstream, which is
/// worth two comparisons a call to rule out. Anything that installs nodes without an
/// index gets the old behaviour and nothing worse.

var wx, wy, mx, my, i, ny, nx0, nx1, best, bestScore, dx, dy, rank, anchor;
var rowIdx, rowLo, rowHi, rowH;

wx = argument0;
wy = argument1;

if(!global.navReady)
    return -1;

mx = navAnchorCol(wx);
my = round((wy + 23) / NAV_CELL_SIZE);

best = -1;
bestScore = 999999;

// Nested ifs rather than one and-chain: GM8 evaluates both sides of and/or
// unconditionally, so `variable_global_exists(...) and global.navRowStart >= 0` reads the
// global even when it does not exist.
rowIdx = -1;
if(variable_global_exists("navRowStart"))
    rowIdx = global.navRowStart;
if(rowIdx >= 0)
{
    if(!variable_global_exists("navRowFor"))
        rowIdx = -1;
}
if(rowIdx >= 0)
{
    // Built from the nodes that are installed now, or not to be trusted. See the header.
    if(global.navRowFor != global.navNodes or global.navRowForCount != global.navNodeCount)
        rowIdx = -1;
}

if(rowIdx >= 0)
{
    rowH = ds_grid_height(rowIdx);

    // The rows whose feet land within dy of the character's, clamped to the index. A
    // window entirely off the end leaves rowLo > rowHi and the loop simply does not run,
    // which is the -1 the old scan would have returned anyway.
    rowLo = my - NAV_BOX_H - 3;
    rowHi = my - NAV_BOX_H + 3;
    if(rowLo < 0)
        rowLo = 0;
    if(rowHi > rowH - 1)
        rowHi = rowH - 1;

    for(ny = rowLo; ny <= rowHi; ny += 1)
    {
        i = ds_grid_get(rowIdx, 0, ny);
        if(i < 0)
            continue;

        // Constant across the row, so it is hoisted out of the walk.
        anchor = ny + NAV_BOX_H;
        dy = abs(anchor - my);

        while(i < global.navNodeCount)
        {
            if(ds_grid_get(global.navNodes, NAV_NODE_Y, i) != ny)
                break;

            nx0 = ds_grid_get(global.navNodes, NAV_NODE_X0, i);
            nx1 = ds_grid_get(global.navNodes, NAV_NODE_X1, i);
            dx = 0;
            if(mx < nx0)
                dx = nx0 - mx;
            else if(mx > nx1)
                dx = mx - nx1;

            if(dx <= 2)
            {
                rank = dy * 4 + dx;
                if(rank < bestScore)
                {
                    bestScore = rank;
                    best = i;
                }
            }

            i += 1;
        }
    }

    return best;
}

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
