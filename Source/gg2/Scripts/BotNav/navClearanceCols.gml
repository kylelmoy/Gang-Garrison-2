/// navClearanceCols(hfree, freeGrid, w, h, fromX, toX)
/// Pass 2 of the clearance dilation, over columns fromX .. toX-1: sets freeGrid
/// wherever NAV_BOX_H consecutive rows of hfree are all set, which is exactly "a
/// character box anchored here is clear of terrain".
///
/// Split out of navClearanceBuild so the build can be chunked across frames.
/// Requires pass 1 (navClearanceRows) to have completed over the whole grid first -
/// a column's answer depends on rows this band does not own.

var hfree, freeGrid, w, h, fromX, toX, cx, cy, count, lastX, lastY, colSum;
hfree = argument0;
freeGrid = argument1;
w = argument2;
h = argument3;
fromX = argument4;
toX = argument5;

if(w < NAV_BOX_W or h < NAV_BOX_H)
    exit;

lastX = w - NAV_BOX_W;
lastY = h - NAV_BOX_H;
if(toX > lastX + 1)
    toX = lastX + 1;

for(cx = fromX; cx < toX; cx += 1)
{
    // A column with no horizontal clearance anywhere can never hold the box, and one
    // that is clear top to bottom always can - both settle in a single native sum
    // instead of h interpreted reads.
    colSum = ds_grid_get_sum(hfree, cx, 0, cx, h - 1);
    if(colSum == 0)
        continue;
    if(colSum == h)
    {
        ds_grid_set_region(freeGrid, cx, 0, cx, lastY, 1);
        continue;
    }

    count = 0;
    for(cy = 0; cy < NAV_BOX_H; cy += 1)
        count += ds_grid_get(hfree, cx, cy);

    for(cy = 0; cy <= lastY; cy += 1)
    {
        if(count == NAV_BOX_H)
            ds_grid_set(freeGrid, cx, cy, 1);

        if(cy + NAV_BOX_H < h)
        {
            count -= ds_grid_get(hfree, cx, cy);
            count += ds_grid_get(hfree, cx, cy + NAV_BOX_H);
        }
    }
}
