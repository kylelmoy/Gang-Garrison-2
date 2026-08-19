/// navClearanceRows(solidGrid, hfree, w, h, fromY, toY)
/// Pass 1 of the clearance dilation, over rows fromY .. toY-1: sets hfree wherever
/// NAV_BOX_W cells starting at that column are all empty.
///
/// Split out of navClearanceBuild so the build can be chunked across frames. This is
/// the pass that has to be budgeted carefully - clearance costs about 4x the solidity
/// scan per cell (F36), so a frame budget counted in "rows" means these rows, not
/// scan rows.
///
/// hfree must already exist at w x h and be cleared to 0, and the caller is
/// responsible for driving fromY/toY from 0 to h exactly once.

var solidGrid, hfree, w, h, fromY, toY, cx, cy, count, lastX;
solidGrid = argument0;
hfree = argument1;
w = argument2;
h = argument3;
fromY = argument4;
toY = argument5;

if(w < NAV_BOX_W or h < NAV_BOX_H)
    exit;

lastX = w - NAV_BOX_W;

for(cy = fromY; cy < toY; cy += 1)
{
    // Fast path for a row with no terrain in it at all. Real maps are mostly open
    // air - gg_debug is 96% empty - and one native region write beats w interpreted
    // ds_grid_get/set pairs by a wide margin.
    if(ds_grid_get_sum(solidGrid, 0, cy, w - 1, cy) == 0)
    {
        ds_grid_set_region(hfree, 0, cy, lastX, cy, 1);
        continue;
    }

    count = 0;
    for(cx = 0; cx < NAV_BOX_W; cx += 1)
        count += ds_grid_get(solidGrid, cx, cy);

    for(cx = 0; cx <= lastX; cx += 1)
    {
        if(count == 0)
            ds_grid_set(hfree, cx, cy, 1);

        if(cx + NAV_BOX_W < w)
        {
            count -= ds_grid_get(solidGrid, cx, cy);
            count += ds_grid_get(solidGrid, cx + NAV_BOX_W, cy);
        }
    }
}
