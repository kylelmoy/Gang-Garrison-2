/// navEdgeAdd(from, to, type, bucket, ticks, cost)
/// Appends one directed edge to the open accumulator, doubling its capacity when it
/// runs out. Every edge is directed: falls, drop-throughs and one-way doors genuinely
/// are, so the symmetric cases simply add two.

var from, to, type, bucket, ticks, cost, at;
from = argument0;
to = argument1;
type = argument2;
bucket = argument3;
ticks = argument4;
cost = argument5;

if(global.navAccCount >= global.navAccCap)
{
    global.navAccCap *= 2;
    ds_grid_resize(global.navAccEdges, NAV_EDGE_FIELDS, global.navAccCap);
}

at = global.navAccCount;
ds_grid_set(global.navAccEdges, NAV_EDGE_FROM, at, from);
ds_grid_set(global.navAccEdges, NAV_EDGE_TO, at, to);
ds_grid_set(global.navAccEdges, NAV_EDGE_TYPE, at, type);
ds_grid_set(global.navAccEdges, NAV_EDGE_BUCKET, at, bucket);
ds_grid_set(global.navAccEdges, NAV_EDGE_TICKS, at, ticks);
ds_grid_set(global.navAccEdges, NAV_EDGE_COST, at, cost);
global.navAccCount = at + 1;
