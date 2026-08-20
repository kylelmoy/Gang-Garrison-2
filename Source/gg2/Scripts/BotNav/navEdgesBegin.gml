/// navEdgesBegin()
/// Opens the edge accumulator that the edge generators append to. Edges arrive from
/// several passes - walk, fall, and later jump and drop-through - so they share one
/// growable grid rather than each returning its own for the caller to splice.
///
/// The accumulator is global.navAccEdges, deliberately NOT global.navEdges. Building
/// into the live graph's own variable means any second caller - a test, a future
/// partial rebuild - destroys the edge list the running server is still pointing at,
/// and every later read is "Data structure with index does not exist" once a frame.
/// The scratch grid is separate and short-lived; navEdgesBuild hands back the result
/// for the caller to install wherever it wants.

global.navAccEdges = ds_grid_create(NAV_EDGE_FIELDS, 64);
ds_grid_clear(global.navAccEdges, 0);
global.navAccCount = 0;
global.navAccCap = 64;
