/// navEdgeAdd(from, to, type, bucket, ticks, cost, gate)
/// Appends one directed edge to the open accumulator, doubling its capacity when it
/// runs out. Every edge is directed: falls, drop-throughs and one-way doors genuinely
/// are, so the symmetric cases simply add two.
///
/// `gate` is the NAV_GATE_* code of the first gate this edge's traversal has to get
/// through, or NAV_GATE_NONE. It is the one field the graph cannot resolve at build
/// time (F26) - navFindPath asks navGatePassable about it per query, with the team and
/// intel carriage of whoever is searching. It lives on the edge rather than only on
/// the destination node because an arc can cross a gate without landing on it: a jump
/// straight over a spawn gate's doorway samples free clearance the whole way, and with
/// only a node-level code every gate on every flat floor in the game would be
/// leapfroggable.

var from, to, type, bucket, ticks, cost, gate, at;
from = argument0;
to = argument1;
type = argument2;
bucket = argument3;
ticks = argument4;
cost = argument5;
gate = argument6;

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
ds_grid_set(global.navAccEdges, NAV_EDGE_GATE, at, gate);
global.navAccCount = at + 1;
