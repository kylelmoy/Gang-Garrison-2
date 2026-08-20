/// navEdgeKey(fromNode, toNode)
/// A single number identifying one directed edge by its endpoints, for use as a
/// ds_map key.
///
/// Keyed on the endpoints rather than on the edge's row index because a row index only
/// means anything to one build of the graph, and the thing that holds these keys - a
/// bot's anti-thrash blacklist - outlives individual searches. Endpoints are no more
/// stable across a rebuild, but a blacklist entry expires in seconds and a rebuild
/// only happens on a map change, which clears the bots' paths anyway.
///
/// The multiplier is comfortably above any node count a real map produces: the largest
/// shipped map, cp_dirtbowl, comes to 833.

return argument0 * 100000 + argument1;
