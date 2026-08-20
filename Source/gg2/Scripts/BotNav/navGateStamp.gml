/// navGateStamp(gateGrid, w, h, code)
/// Writes one gate instance's footprint into the gate grid as `code`. Call from
/// inside a with(SomeGate) block - it reads bbox_* from whichever instance is `self`,
/// the way a GML script inherits its caller's scope.
///
/// The footprint is dilated up by NAV_BOX_H - 1 rows and left by NAV_BOX_W - 1
/// columns, because what the grid has to answer is not "is this cell gate" but "would
/// a character anchored at this cell be standing in the gate". A nav anchor is the
/// top-left of a NAV_BOX_W x NAV_BOX_H body, so a body overlaps rows t..b exactly when
/// its anchor row is in t - (NAV_BOX_H - 1) .. b, and likewise for columns. See
/// navMarkInstances' header for why being generous here is the safe direction.

var gateGrid, w, h, code, gl, gt, gr, gb;
gateGrid = argument0;
w = argument1;
h = argument2;
code = argument3;

gl = max(0, floor(bbox_left / NAV_CELL_SIZE) - (NAV_BOX_W - 1));
gt = max(0, floor(bbox_top / NAV_CELL_SIZE) - (NAV_BOX_H - 1));
gr = min(w - 1, floor(bbox_right / NAV_CELL_SIZE));
gb = min(h - 1, floor(bbox_bottom / NAV_CELL_SIZE));

// A gate sitting entirely off the mask - possible on a multi-area map, where
// basicRoomSetup leaves the other stages' instances alone outside the active y-band -
// clamps to an inverted region, which is not a write ds_grid_set_region should be
// asked to make.
if(gl > gr or gt > gb)
    exit;

ds_grid_set_region(gateGrid, gl, gt, gr, gb, code);
