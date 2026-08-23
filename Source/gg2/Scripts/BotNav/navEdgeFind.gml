/// navEdgeFind(fromNode, toNode)
/// The row index in global.navEdges of the edge from fromNode to toNode, or -1 if the
/// graph has no such edge.
///
/// Reads the prebuilt adjacency index, so this is a scan of one node's outgoing edges
/// rather than of the whole list - a handful of reads, which is what makes it cheap
/// enough for a path follower to ask every tick what kind of move it is currently
/// making.
///
/// Where two edges connect the same pair (a walk and a jump between neighbouring
/// ledges, say), the first is returned. The generator emits walks before jumps, so
/// that is the cheaper one, which is also the one A* would have chosen.

var fromNode, toNode, eStart, eCount, i;
fromNode = argument0;
toNode = argument1;

if(!global.navReady)
    return -1;
if(fromNode < 0 or fromNode >= global.navNodeCount)
    return -1;

eStart = ds_grid_get(global.navEdgeIdx, 0, fromNode);
if(eStart < 0)
    return -1;
eCount = ds_grid_get(global.navEdgeIdx, 1, fromNode);

for(i = eStart; i < eStart + eCount; i += 1)
{
    if(ds_grid_get(global.navEdges, NAV_EDGE_TO, i) == toNode)
        return i;
}

return -1;
