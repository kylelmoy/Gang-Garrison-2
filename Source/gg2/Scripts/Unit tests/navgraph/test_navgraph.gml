// void test_navgraph()
// Nav graph runtime unit test.
//
// This suite used to test the graph *builder*: it wrote walkmasks with
// ds_grid_set_region, ran navSolidityBuild / navClearanceBuild / navNodesExtract /
// navEdgesBuild over them, and asserted on the nodes and edges that came out. That
// builder is gone from the game - it lives in the gg2-nav-gen tool now, which has its
// own suite - so everything downstream of "here is a finished graph" is what is left,
// and that is what this file covers:
//
//   the cache file, which is now the only way a graph enters the game
//   the two indices navCacheLoad derives from it (navEdgeIndex, navRowIndex)
//   resolving a world position to a node (navAnchorCol, navColWorldX, navNodeFromWorld)
//   A* over the result (navFindPath), including gates, blacklists and occupancy
//   the goal layer that sits on top of it (botGoalSpot)
//
// Fixtures are therefore hand-built node and edge grids rather than generated ones.
// That is a gain and not just a consequence: the graphs below say what they are in
// eight lines instead of being the output of two thousand lines of generator that this
// suite would then be pinning by accident. Anything about *how a graph is derived from
// terrain* belongs in gg2-nav-gen/test/verify.js, not here.
//
// Geometry throughout is in mask cells: 1 cell = 6 world px, and the character box is
// NAV_BOX_W x NAV_BOX_H cells, which covers Heavy (F24). Rows are written as
// expressions in NAV_BOX_H where they depend on it, because NAV_BOX_H has changed once
// already - 7 to 6 in 8e30e213 - and took 54 hand-computed assertions with it.
//
// Nothing here depends on instance ids, current_time, fps, a loaded map or a running
// server (F33), except the cache cases, which write into working_directory and delete
// what they wrote, and the cache-key case, which saves and restores what it touches.

test_unit_begin();

var nodes, edges, w, h, i;
var oldMap, oldMd5, oldArea, oldSetup;
var path, oldNodes, oldEdges, oldCount, oldEdgeCount, oldReady, testIdx, oldIdx;
var djNodes, djEdges, djIdx;
var oldRowStart, oldRowFor, oldRowForCount, testRow;

// This suite may run against a server with a live nav graph. Every case below installs
// a fixture over the running graph book-keeping, so save it all now and put it back at
// the end, or a passing test run leaves the server pathing against nonsense.
oldNodes = -1;
oldEdges = -1;
oldCount = 0;
oldEdgeCount = 0;
oldReady = false;
oldIdx = -1;
oldRowStart = -1;
oldRowFor = -1;
oldRowForCount = 0;
if(variable_global_exists("navNodes"))
    oldNodes = global.navNodes;
if(variable_global_exists("navEdges"))
    oldEdges = global.navEdges;
if(variable_global_exists("navNodeCount"))
    oldCount = global.navNodeCount;
if(variable_global_exists("navEdgeCount"))
    oldEdgeCount = global.navEdgeCount;
if(variable_global_exists("navReady"))
    oldReady = global.navReady;
if(variable_global_exists("navEdgeIdx"))
    oldIdx = global.navEdgeIdx;
if(variable_global_exists("navRowStart"))
    oldRowStart = global.navRowStart;
if(variable_global_exists("navRowFor"))
    oldRowFor = global.navRowFor;
if(variable_global_exists("navRowForCount"))
    oldRowForCount = global.navRowForCount;

// ---------------------------------------------------------------------------
// navAnchorCol and navColWorldX are inverses, to a cell's rounding.
//
// A node's x-span is in anchor columns - the left edge of the body box - and a
// Character's x is the centre of its sprite, so the two are half a box apart. Nothing
// is allowed to convert between them by hand, which only means anything if the pair
// actually round-trips.
// ---------------------------------------------------------------------------
for(i = 0; i < 40; i += 1)
    test_assert_equals(i, navAnchorCol(navColWorldX(i)));

// ---------------------------------------------------------------------------
// The fixture the pathing cases run on: three surfaces, each one mask row above the
// last, adjacent left to right, walk connected end to end.
//
//   n0  cols  0..11        n1  cols 15..25        n2  cols 30..39
//
// Chosen so that no two nodes are within navNodeFromWorld's dx tolerance of each
// other, which is what makes "the spot resolves back to the node it came from"
// meaningful below rather than accidentally true.
//
// The edge list is sorted by NAV_EDGE_FROM, because that is what navEdgeIndex requires
// and what the cache file guarantees. Costs are the horizontal distance each walk
// covers, in cells, which is what the generator charges and what keeps the
// straight-line heuristic admissible.
// ---------------------------------------------------------------------------
w = 44;
h = 24;

nodes = ds_grid_create(NAV_NODE_FIELDS, 3);
ds_grid_clear(nodes, 0);
ds_grid_set(nodes, NAV_NODE_Y, 0, 17 - NAV_BOX_H);
ds_grid_set(nodes, NAV_NODE_X0, 0, 0);
ds_grid_set(nodes, NAV_NODE_X1, 0, 11);
ds_grid_set(nodes, NAV_NODE_Y, 1, 16 - NAV_BOX_H);
ds_grid_set(nodes, NAV_NODE_X0, 1, 15);
ds_grid_set(nodes, NAV_NODE_X1, 1, 25);
ds_grid_set(nodes, NAV_NODE_Y, 2, 15 - NAV_BOX_H);
ds_grid_set(nodes, NAV_NODE_X0, 2, 30);
ds_grid_set(nodes, NAV_NODE_X1, 2, 39);

edges = ds_grid_create(NAV_EDGE_FIELDS, 4);
ds_grid_clear(edges, 0);
ds_grid_set(edges, NAV_EDGE_FROM, 0, 0);
ds_grid_set(edges, NAV_EDGE_TO,   0, 1);
ds_grid_set(edges, NAV_EDGE_TYPE, 0, NAV_EDGE_WALK);
ds_grid_set(edges, NAV_EDGE_COST, 0, 15);
ds_grid_set(edges, NAV_EDGE_FROM, 1, 1);
ds_grid_set(edges, NAV_EDGE_TO,   1, 0);
ds_grid_set(edges, NAV_EDGE_TYPE, 1, NAV_EDGE_WALK);
ds_grid_set(edges, NAV_EDGE_COST, 1, 15);
ds_grid_set(edges, NAV_EDGE_FROM, 2, 1);
ds_grid_set(edges, NAV_EDGE_TO,   2, 2);
ds_grid_set(edges, NAV_EDGE_TYPE, 2, NAV_EDGE_WALK);
ds_grid_set(edges, NAV_EDGE_COST, 2, 15);
ds_grid_set(edges, NAV_EDGE_FROM, 3, 2);
ds_grid_set(edges, NAV_EDGE_TO,   3, 1);
ds_grid_set(edges, NAV_EDGE_TYPE, 3, NAV_EDGE_WALK);
ds_grid_set(edges, NAV_EDGE_COST, 3, 15);

global.navNodes = nodes;
global.navEdges = edges;
global.navNodeCount = 3;
global.navEdgeCount = 4;
global.navMaskW = w;
global.navMaskH = h;
// navFindPath and navEdgeFind read a prebuilt adjacency index rather than deriving one
// per call, and navNodeFromWorld reads a row index, so a stand-in graph has to supply
// both or they read the ranges of whatever map is actually loaded.
testIdx = navEdgeIndex(edges, 4, 3);
global.navEdgeIdx = testIdx;
testRow = navRowIndex(nodes, 3, h);
global.navRowStart = testRow;
global.navRowFor = nodes;
global.navRowForCount = 3;
global.navReady = true;

// ---------------------------------------------------------------------------
// navEdgeIndex groups a sorted edge list by from-node, and navEdgeFind reads it.
//
// This is the index navCacheLoad derives on every load, so it is the one thing between
// a file on disk and A* being able to expand a node at all.
// ---------------------------------------------------------------------------
test_assert_equals(0, ds_grid_get(testIdx, 0, 0));
test_assert_equals(1, ds_grid_get(testIdx, 1, 0));
test_assert_equals(1, ds_grid_get(testIdx, 0, 1));
test_assert_equals(2, ds_grid_get(testIdx, 1, 1));
test_assert_equals(3, ds_grid_get(testIdx, 0, 2));
test_assert_equals(1, ds_grid_get(testIdx, 1, 2));

test_assert_equals(0, navEdgeFind(0, 1));
test_assert_equals(2, navEdgeFind(1, 2));
// Not every pair is connected, and a missing edge is -1 rather than the nearest thing.
test_assert_equals(-1, navEdgeFind(0, 2));
test_assert_equals(-1, navEdgeFind(99, 0));

// ---------------------------------------------------------------------------
// navRowIndex, and the two paths through navNodeFromWorld agreeing.
//
// The index maps a mask row to the first node on it, so navNodeFromWorld can read the
// seven rows that could possibly match instead of every node on the map. It is derived
// on load rather than stored, and it is guarded by navRowFor - the guard exists because
// a fixture installed straight onto global.navNodes (this suite, exactly) would
// otherwise be resolved through an index describing the previous map.
//
// The fallback linear scan is not dead code, so it is worth pinning that it answers the
// same thing: disown the guard's stamp and the same query has to come back with the
// same node, or one of the two is wrong and nothing says which.
// ---------------------------------------------------------------------------
test_assert_equals(0, ds_grid_get(testRow, 0, 17 - NAV_BOX_H));
test_assert_equals(1, ds_grid_get(testRow, 0, 16 - NAV_BOX_H));
test_assert_equals(2, ds_grid_get(testRow, 0, 15 - NAV_BOX_H));
test_assert_equals(-1, ds_grid_get(testRow, 0, 0));

var probeX, probeY, probeIdx, viaRow, viaScan;
for(probeIdx = 0; probeIdx < 3; probeIdx += 1)
{
    probeX = navColWorldX((ds_grid_get(nodes, NAV_NODE_X0, probeIdx) + ds_grid_get(nodes, NAV_NODE_X1, probeIdx)) div 2);
    probeY = (ds_grid_get(nodes, NAV_NODE_Y, probeIdx) + NAV_BOX_H) * NAV_CELL_SIZE - 23;

    viaRow = navNodeFromWorld(probeX, probeY);
    test_assert_equals(probeIdx, viaRow);

    // The same query with the index disowned, which is what sends it down the scan.
    global.navRowFor = -1;
    viaScan = navNodeFromWorld(probeX, probeY);
    global.navRowFor = nodes;
    test_assert_equals(viaRow, viaScan);
}

// Nowhere near any surface is -1, not the least bad answer. botNodeSnap walks a fall
// 6px at a time asking this, and a "nearest node" answer several rows away would have
// it believe it had landed.
test_assert_equals(-1, navNodeFromWorld(navColWorldX(20), 0));

// ---------------------------------------------------------------------------
// A* over the fixture.
//
// navFindPath reads the graph from globals rather than taking it as arguments, since
// there is one graph per server.
// ---------------------------------------------------------------------------
path = navFindPath(0, 2, TEAM_RED, false, -1, -1);
test_assert_equals(true, path >= 0);
test_assert_equals(3, ds_list_size(path));
test_assert_equals(0, ds_list_find_value(path, 0));
test_assert_equals(1, ds_list_find_value(path, 1));
test_assert_equals(2, ds_list_find_value(path, 2));
ds_list_destroy(path);

// A path to itself is one node, not zero and not a loop.
path = navFindPath(1, 1, TEAM_RED, false, -1, -1);
test_assert_equals(1, ds_list_size(path));
ds_list_destroy(path);

// Out of range asks are refused rather than clamped.
test_assert_equals(-1, navFindPath(0, 99, TEAM_RED, false, -1, -1));
test_assert_equals(-1, navFindPath(-1, 0, TEAM_RED, false, -1, -1));

// A blacklisted edge is refused outright, and on a corridor that means no path at all.
// That is the difference between the blacklist and the occupancy penalty below, and it
// is the whole reason a bot that wedges in a doorway stops being handed the same route.
var blkTest;
blkTest = ds_map_create();
ds_map_add(blkTest, navEdgeKey(0, 1), 1);
test_assert_equals(-1, navFindPath(0, 2, TEAM_RED, false, blkTest, -1));
ds_map_destroy(blkTest);

// --- the search is deterministic, and takes no seed ------------------------------------
//
// A per-bot cost jitter used to live here (M7 1.4): navFindPath took a sixth argument that
// multiplied each edge cost by up to NAV_PATH_JITTER, so that two bots with the same goal
// picked different routes to it. It is gone, and the tests that pinned it with it.
//
// It was deleted for the wrong reason, which is worth writing down because the right one is
// a stronger constraint on whatever replaces it. Replaying it offline against the real
// cached graphs showed two things. First, it produced no variety at all: on the full
// ctf_truefort blue leg every bot, seeded with a real Player instance id, got the
// *identical* route, because per-edge noise is mean-reverting and cancels out over sixty
// edges. Second, the closed set was not what returned the bad route - the same reproduction
// gives the same answer with and without the re-open, because under the jittered costs the
// longer route genuinely was cheaper. See navFindPath's header for both measurements.
//
// So what is pinned here is the property actually worth having: the same question gets the
// same answer. Route variety came back as the shared occupancy penalty, pinned below.
var detPath, detPath2, detIdx;

detPath = navFindPath(0, 2, TEAM_RED, false, -1, -1);
test_assert_equals(true, detPath >= 0);
test_assert_equals(0, ds_list_find_value(detPath, 0));
test_assert_equals(2, ds_list_find_value(detPath, ds_list_size(detPath) - 1));

detPath2 = navFindPath(0, 2, TEAM_RED, false, -1, -1);
test_assert_equals(ds_list_size(detPath), ds_list_size(detPath2));
for(detIdx = 0; detIdx < ds_list_size(detPath); detIdx += 1)
    test_assert_equals(ds_list_find_value(detPath, detIdx), ds_list_find_value(detPath2, detIdx));
ds_list_destroy(detPath);
ds_list_destroy(detPath2);

// --- botGoalSpot: "a place from which I can do X" (M7 tier 3) --------------------------
//
// The goal layer's contract has two halves and only one of them is about geometry:
//
//   1. whatever node comes back, the position published alongside it must resolve *back*
//      to that same node through navNodeFromWorld. Everything downstream depends on it -
//      botSetGoalNode issues the goal from that position, botPathPlan resolves it to a
//      goal node, and the follower checks arrival against it. A spot that resolves to a
//      neighbouring node is a bot that walks to the wrong surface and never arrives.
//   2. the spot is inside the band it was asked for. That is what makes it a *firing*
//      position rather than just a nearby node.
//
// needLOS is false throughout, because line of sight is a room-collision question and
// this fixture is two ds_grids with no room behind them (F33).
var spotNode, spotAnchorX, spotAnchorY, spotIdx, spotCol, spotX, spotY, spotD;

spotAnchorX = navColWorldX((ds_grid_get(nodes, NAV_NODE_X0, 1) + ds_grid_get(nodes, NAV_NODE_X1, 1)) div 2);
spotAnchorY = (ds_grid_get(nodes, NAV_NODE_Y, 1) + NAV_BOX_H) * NAV_CELL_SIZE - 23;

spotNode = botGoalSpot(id, spotAnchorX, spotAnchorY, 0, 100000, false, 0);
test_assert_equals(true, spotNode >= 0);
test_assert_equals(spotNode, navNodeFromWorld(global.botSpotX, global.botSpotY));

// The band is a filter at *both* ends, and it is asked here one node at a time: for each
// node, work out where botGoalSpot would stand on it and how far that is from the anchor,
// then ask for a band one pixel either side of exactly that distance. Every such band is
// non-empty by construction, and what comes back must be inside it.
//
// Written this way rather than with a hard-coded threshold on purpose. The first version
// asserted "further than 60px" against this fixture and failed, because a node's span is
// in *anchor* columns - narrower than the solid run under it by most of NAV_BOX_W - so the
// three platforms sit closer together than their solid extents suggest. Deriving the band
// from the graph tests the contract instead of the fixture's arithmetic, and it also stays
// correct if the platforms above are ever moved.
for(spotIdx = 0; spotIdx < global.navNodeCount; spotIdx += 1)
{
    spotCol = navAnchorCol(spotAnchorX);
    if(spotCol < ds_grid_get(nodes, NAV_NODE_X0, spotIdx))
        spotCol = ds_grid_get(nodes, NAV_NODE_X0, spotIdx);
    else if(spotCol > ds_grid_get(nodes, NAV_NODE_X1, spotIdx))
        spotCol = ds_grid_get(nodes, NAV_NODE_X1, spotIdx);
    spotX = navColWorldX(spotCol);
    spotY = (ds_grid_get(nodes, NAV_NODE_Y, spotIdx) + NAV_BOX_H) * NAV_CELL_SIZE - 23;
    spotD = point_distance(spotX, spotY, spotAnchorX, spotAnchorY);

    spotNode = botGoalSpot(id, spotAnchorX, spotAnchorY, max(0, spotD - 1), spotD + 1, false, 0);
    test_assert_equals(true, spotNode >= 0);
    test_assert_equals(true,
        abs(point_distance(global.botSpotX, global.botSpotY, spotAnchorX, spotAnchorY) - spotD) <= 1);
    test_assert_equals(spotNode, navNodeFromWorld(global.botSpotX, global.botSpotY));
}

// An empty band answers -1 rather than the nearest thing to it. The caller's whole
// fallback path (botObjectiveUpdate walking to the objective itself) hangs on this being
// a refusal and not a best effort.
test_assert_equals(-1, botGoalSpot(id, spotAnchorX, spotAnchorY, 100000, 200000, false, 0));

// A degenerate band is refused rather than clamped, for the same reason.
test_assert_equals(-1, botGoalSpot(id, spotAnchorX, spotAnchorY, 100, 100, false, 0));

// On a -1 the published position is the anchor itself, not whatever the previous call
// left behind: a caller that ignores the return value gets something usable rather than
// a stale spot from a different query.
test_assert_equals(spotAnchorX, global.botSpotX);
test_assert_equals(spotAnchorY, global.botSpotY);

// --- the occupancy penalty reaches the cost function ----------------------------------
//
// The contract navFindPath advertises: an edge listed in the occupancy map is charged
// (1 + BOT_OCCUPANCY_COST * count) times its honest cost. The fixture above is three
// surfaces in a row, so there is only one route from node 0 to node 2 - the wrong shape
// for testing *which* route comes back, and the right shape for testing that a crowded
// edge is still taken when it is the only way through.
var occTest, occPath;

occTest = ds_map_create();
ds_map_add(occTest, navEdgeKey(0, 1), 4);

// The penalty biases a choice; it never refuses one. That is what separates it from the
// blacklist, which does refuse, and it is why a bot on a corridor map still gets a route.
occPath = navFindPath(0, 2, TEAM_RED, false, -1, occTest);
test_assert_equals(true, occPath >= 0);
test_assert_equals(0, ds_list_find_value(occPath, 0));
test_assert_equals(2, ds_list_find_value(occPath, ds_list_size(occPath) - 1));
ds_list_destroy(occPath);

// An empty map is the same as no map at all.
ds_map_clear(occTest);
occPath = navFindPath(0, 2, TEAM_RED, false, -1, occTest);
test_assert_equals(true, occPath >= 0);
ds_list_destroy(occPath);
ds_map_destroy(occTest);

// ---------------------------------------------------------------------------
// The cache file is now the only way a graph enters the game, so it is pinned here
// end to end: write one, load it, and check the graph and both derived indices.
//
// The file is written by hand rather than through a navCacheSave script, because there
// is no longer such a script - gg2-nav-gen writes these files. What that means for this
// test is that the format is now a contract between two repositories, and the four
// lines below are the whole of it: a version header, a dimensions line, and the two
// grids as ds_grid_write strings.
// ---------------------------------------------------------------------------
var cacheKey, cacheDir, cachePath, cacheF, loadedNodes, loadedEdges, loadedIdx, loadedRow;

cacheKey = "zz_test_navcache_a1";
cacheDir = working_directory + "\botnav";
cachePath = cacheDir + "\" + cacheKey + ".txt";
if(!directory_exists(cacheDir))
    directory_create(cacheDir);

cacheF = file_text_open_write(cachePath);
file_text_write_string(cacheF, "navgraph " + string(NAV_CACHE_VERSION));
file_text_writeln(cacheF);
file_text_write_string(cacheF, string(w) + " " + string(h) + " 3 4");
file_text_writeln(cacheF);
file_text_write_string(cacheF, ds_grid_write(nodes));
file_text_writeln(cacheF);
file_text_write_string(cacheF, ds_grid_write(edges));
file_text_writeln(cacheF);
file_text_close(cacheF);

test_assert_equals(true, navCacheLoad(cacheKey));

// The load allocates its own grids and hands ownership over, so they are freed here and
// the fixture's own are still the ones the rest of this section uses.
loadedNodes = global.navNodes;
loadedEdges = global.navEdges;
loadedIdx = global.navEdgeIdx;
loadedRow = global.navRowStart;

test_assert_equals(3, global.navNodeCount);
test_assert_equals(4, global.navEdgeCount);
test_assert_equals(w, global.navMaskW);
test_assert_equals(h, global.navMaskH);
test_assert_equals(17 - NAV_BOX_H, ds_grid_get(loadedNodes, NAV_NODE_Y, 0));
test_assert_equals(11, ds_grid_get(loadedNodes, NAV_NODE_X1, 0));
test_assert_equals(30, ds_grid_get(loadedNodes, NAV_NODE_X0, 2));
test_assert_equals(2, ds_grid_get(loadedEdges, NAV_EDGE_TO, 2));
test_assert_equals(15, ds_grid_get(loadedEdges, NAV_EDGE_COST, 2));

// Both indices come back derived, and the row index comes back *stamped* with the node
// grid it describes. Without that stamp navNodeFromWorld would fall back to a linear
// scan on every cache hit, which is the difference between two comparisons and a
// whole-graph read per call.
test_assert_equals(1, ds_grid_get(loadedIdx, 0, 1));
test_assert_equals(2, ds_grid_get(loadedIdx, 1, 1));
test_assert_equals(0, ds_grid_get(loadedRow, 0, 17 - NAV_BOX_H));
test_assert_equals(loadedNodes, global.navRowFor);
test_assert_equals(3, global.navRowForCount);

// And it paths, which is the only claim that matters.
path = navFindPath(0, 2, TEAM_RED, false, -1, -1);
test_assert_equals(true, path >= 0);
test_assert_equals(3, ds_list_size(path));
ds_list_destroy(path);

ds_grid_destroy(loadedRow);
ds_grid_destroy(loadedIdx);
ds_grid_destroy(loadedEdges);
ds_grid_destroy(loadedNodes);

// Put the fixture back before asking anything else, since the load replaced it.
global.navNodes = nodes;
global.navEdges = edges;
global.navNodeCount = 3;
global.navEdgeCount = 4;
global.navEdgeIdx = testIdx;
global.navRowStart = testRow;
global.navRowFor = nodes;
global.navRowForCount = 3;

// A file from a different NAV_CACHE_VERSION is refused rather than read as though its
// columns still meant what they mean now. That refusal is the entire reason the version
// is in the file: a graph whose fields have shifted by one loads perfectly and paths
// nonsense.
cacheF = file_text_open_write(cachePath);
file_text_write_string(cacheF, "navgraph " + string(NAV_CACHE_VERSION - 1));
file_text_writeln(cacheF);
file_text_write_string(cacheF, string(w) + " " + string(h) + " 3 4");
file_text_writeln(cacheF);
file_text_write_string(cacheF, ds_grid_write(nodes));
file_text_writeln(cacheF);
file_text_write_string(cacheF, ds_grid_write(edges));
file_text_writeln(cacheF);
file_text_close(cacheF);

test_assert_equals(false, navCacheLoad(cacheKey));
// Refused *having allocated nothing* and having installed nothing: a caller that
// ignores the return value must not end up with half a graph, and must certainly not
// end up with the fixture above replaced by a leaked pair of grids.
test_assert_equals(nodes, global.navNodes);
test_assert_equals(3, global.navNodeCount);

file_delete(cachePath);

// An absent file is an ordinary miss, not an error. It is what every map nobody has run
// gg2-nav-gen over yet looks like, and navGraphLoad turns it into "no bots path here"
// rather than into a stall.
test_assert_equals(false, navCacheLoad("zz_test_navcache_absent_a1"));
test_assert_equals(nodes, global.navNodes);

global.navReady = false;
ds_grid_destroy(testRow);
ds_grid_destroy(testIdx);
ds_grid_destroy(edges);
ds_grid_destroy(nodes);

// ---------------------------------------------------------------------------
// The search is OPTIMAL, not merely fast: closed nodes are re-opened.
//
// This is the regression test ROUTEVARIETY.md listed as outstanding, and it needs a
// shape that does not arise in generated geometry: a heuristic that is admissible but
// INCONSISTENT, so a node is closed holding a bad g and a cheaper route to it turns up
// afterwards.
//
// Consistency here is a statement about edge costs, not about the heuristic alone. The
// heuristic is straight-line distance between node midpoints, and straight lines obey the
// triangle inequality, so h(n) <= dist(n, n2) + h(n2) always holds - which means
// h(n) <= cost(n, n2) + h(n2) holds for every edge charged at least the distance it spans,
// and fails for any edge cheaper than the ground it covers. Real graphs have those: a fall
// edge is charged its drop height while also moving sideways, so it spans more distance
// than it is charged for. That is why the re-open fires on honest costs at all - the
// ctf_truefort blue leg went from 68 nodes to 60 when it went in - and why the occupancy
// penalty cannot be assumed safe without it.
//
// The fixture, four nodes:
//
//   n0 (0,2) --10--> n1 (10,0) --20--> n3 (20,0)
//   n0       --1-->  n2 (1,1)  --1-->  n1
//
//   h to n3:    n0 20.10   n1 10   n2 19.03   n3 0
//   true cost:  n0 22      n1 20   n2 21      n3 0
//
// Admissible everywhere (20.10 <= 22, 10 <= 20, 19.03 <= 21) and inconsistent on n2 -> n1,
// where h(n2) = 19.03 is far more than cost 1 + h(n1) = 11.
//
// The search pops n0, then n1 at f = 10 + 10 = 20 - just ahead of n2 at f = 1 + 19.03 =
// 20.03 - and closes n1 holding g = 10. Only then does n2 come off the queue offering n1 at
// g = 2. A search that skips closed neighbours never hears it and answers n0 > n1 > n3 at
// cost 30; the re-open takes it and answers n0 > n2 > n1 > n3 at cost 22.
//
// Delete the re-open in navFindPath and this case fails. That is the whole point of it.
// ---------------------------------------------------------------------------
var optNodes, optEdges, optIdx, optPath;

optNodes = ds_grid_create(NAV_NODE_FIELDS, 4);
ds_grid_clear(optNodes, 0);
// The row, then the x-span - one column wide each, so a node's midpoint is that column.
ds_grid_set(optNodes, NAV_NODE_Y, 0, 2);
ds_grid_set(optNodes, NAV_NODE_X0, 0, 0);
ds_grid_set(optNodes, NAV_NODE_X1, 0, 0);
ds_grid_set(optNodes, NAV_NODE_Y, 1, 0);
ds_grid_set(optNodes, NAV_NODE_X0, 1, 10);
ds_grid_set(optNodes, NAV_NODE_X1, 1, 10);
ds_grid_set(optNodes, NAV_NODE_Y, 2, 1);
ds_grid_set(optNodes, NAV_NODE_X0, 2, 1);
ds_grid_set(optNodes, NAV_NODE_X1, 2, 1);
ds_grid_set(optNodes, NAV_NODE_Y, 3, 0);
ds_grid_set(optNodes, NAV_NODE_X0, 3, 20);
ds_grid_set(optNodes, NAV_NODE_X1, 3, 20);

// Sorted by NAV_EDGE_FROM, which navEdgeIndex requires and the cache file guarantees.
optEdges = ds_grid_create(NAV_EDGE_FIELDS, 4);
ds_grid_clear(optEdges, 0);
ds_grid_set(optEdges, NAV_EDGE_FROM, 0, 0);
ds_grid_set(optEdges, NAV_EDGE_TO,   0, 1);
ds_grid_set(optEdges, NAV_EDGE_COST, 0, 10);
ds_grid_set(optEdges, NAV_EDGE_FROM, 1, 0);
ds_grid_set(optEdges, NAV_EDGE_TO,   1, 2);
ds_grid_set(optEdges, NAV_EDGE_COST, 1, 1);
ds_grid_set(optEdges, NAV_EDGE_FROM, 2, 1);
ds_grid_set(optEdges, NAV_EDGE_TO,   2, 3);
ds_grid_set(optEdges, NAV_EDGE_COST, 2, 20);
ds_grid_set(optEdges, NAV_EDGE_FROM, 3, 2);
ds_grid_set(optEdges, NAV_EDGE_TO,   3, 1);
ds_grid_set(optEdges, NAV_EDGE_COST, 3, 1);

global.navNodes = optNodes;
global.navEdges = optEdges;
global.navNodeCount = 4;
global.navEdgeCount = 4;
optIdx = navEdgeIndex(optEdges, 4, 4);
global.navEdgeIdx = optIdx;
// No row index for this one: its nodes are not real geometry and nothing here resolves a
// world position. Disowning the stamp is what keeps navNodeFromWorld off a stale index if
// anything ever does.
global.navRowFor = -1;
global.navRowForCount = 0;
global.navReady = true;

optPath = navFindPath(0, 3, TEAM_RED, false, -1, -1);
test_assert_equals(true, optPath >= 0);
// Four nodes, not three: the cheap way round rather than the dear direct edge.
test_assert_equals(4, ds_list_size(optPath));
test_assert_equals(0, ds_list_find_value(optPath, 0));
test_assert_equals(2, ds_list_find_value(optPath, 1));
test_assert_equals(1, ds_list_find_value(optPath, 2));
test_assert_equals(3, ds_list_find_value(optPath, 3));
ds_list_destroy(optPath);

// The control: take the n2 -> n1 edge away and the dear direct edge is the only route
// left, so the answer becomes n0 > n1 > n3. That is what confirms the four-node answer
// above was a choice the search made rather than the only thing it could reach.
//
// Dropped by rebuilding the index over the first three edges rather than by retargeting
// the fourth, and the difference is not cosmetic. Pointing n2 -> n1 at n3 instead does not
// remove an alternative, it adds a better one - n0 > n2 > n3 costs 2 against the direct
// route's 30 - so the search rightly took it and the assertion below failed on a graph
// that no longer tested anything. The edges are sorted by NAV_EDGE_FROM, so the n2 edge is
// last and a count of 3 is exactly "every edge except that one".
ds_grid_destroy(optIdx);
optIdx = navEdgeIndex(optEdges, 3, 4);
global.navEdgeIdx = optIdx;

optPath = navFindPath(0, 3, TEAM_RED, false, -1, -1);
test_assert_equals(true, optPath >= 0);
test_assert_equals(3, ds_list_size(optPath));
test_assert_equals(1, ds_list_find_value(optPath, 1));
ds_list_destroy(optPath);

global.navReady = false;
ds_grid_destroy(optIdx);
ds_grid_destroy(optEdges);
ds_grid_destroy(optNodes);

// ---------------------------------------------------------------------------
// navGatePassable's truth table, straight off charSetSolids.gml.
//
// Your own team gate is open unless you are carrying the intel out through it; an
// enemy intel gate is shut only to a carrier; a setup gate is shut for everyone while
// setup is running. Nothing here touches the graph - this is the whole of what the
// generator cannot decide for itself (F26), so it is worth pinning on its own.
// ---------------------------------------------------------------------------
test_assert_equals(true, navGatePassable(NAV_GATE_NONE, TEAM_BLUE, true));

test_assert_equals(true, navGatePassable(NAV_GATE_TEAM_RED, TEAM_RED, false));
test_assert_equals(false, navGatePassable(NAV_GATE_TEAM_RED, TEAM_RED, true));
test_assert_equals(false, navGatePassable(NAV_GATE_TEAM_RED, TEAM_BLUE, false));
test_assert_equals(true, navGatePassable(NAV_GATE_TEAM_BLUE, TEAM_BLUE, false));
test_assert_equals(false, navGatePassable(NAV_GATE_TEAM_BLUE, TEAM_RED, false));

test_assert_equals(true, navGatePassable(NAV_GATE_INTEL_RED, TEAM_BLUE, false));
test_assert_equals(false, navGatePassable(NAV_GATE_INTEL_RED, TEAM_BLUE, true));
test_assert_equals(true, navGatePassable(NAV_GATE_INTEL_RED, TEAM_RED, true));

// An unknown code is shut, not open: a gate the graph carries and this does not
// recognise is a wall, which fails a route rather than walking a bot into a door.
test_assert_equals(false, navGatePassable(99, TEAM_RED, false));

// The setup gate reads live state, so it is only asserted where that state is
// actually determinate: FauxCPHUD overrides global.setupTimer when a CP map is up.
// A non-zero timer means setup is still running, which is when the gates are shut.
if(variable_global_exists("setupTimer") and instance_number(FauxCPHUD) == 0)
{
    oldSetup = global.setupTimer;
    global.setupTimer = 0;
    test_assert_equals(true, navGatePassable(NAV_GATE_SETUP, TEAM_RED, false));
    global.setupTimer = 180;
    test_assert_equals(false, navGatePassable(NAV_GATE_SETUP, TEAM_RED, false));
    global.setupTimer = oldSetup;
}

// ---------------------------------------------------------------------------
// A* refuses to route through a gate for whoever may not pass it.
//
// A team gate across a corridor: floor, gate, floor, connected by four same-row walks
// across the two boundaries, plus the pair of jumps that leapfrog the gate node
// entirely. Those jumps are exactly why the gate code lives on the *edge* rather than
// only on the node - their arcs pass through the gate column at head height, so the
// generator stamps them with its code too and they are refused along with everything
// else. A graph that carried gates only on nodes would let a bot hop the gate.
//
// Entering the gate is gated; leaving it is not, which is what keeps a bot already
// standing in one - anyone who just picked up the intel - from being stranded there.
//
// The leapfrog jump is charged more than the two walks it replaces (the generator adds
// NAV_JUMP_PENALTY), so the route through the gate node is the cheaper one and the
// three-node answer below is a real choice rather than the only thing on offer.
// ---------------------------------------------------------------------------
var gateNodes, gateEdges, gateIdx;

gateNodes = ds_grid_create(NAV_NODE_FIELDS, 3);
ds_grid_clear(gateNodes, 0);
ds_grid_set(gateNodes, NAV_NODE_Y, 0, 15 - NAV_BOX_H);
ds_grid_set(gateNodes, NAV_NODE_X0, 0, 0);
ds_grid_set(gateNodes, NAV_NODE_X1, 0, 12);
ds_grid_set(gateNodes, NAV_NODE_GATE, 0, NAV_GATE_NONE);
ds_grid_set(gateNodes, NAV_NODE_Y, 1, 15 - NAV_BOX_H);
ds_grid_set(gateNodes, NAV_NODE_X0, 1, 13);
ds_grid_set(gateNodes, NAV_NODE_X1, 1, 14);
ds_grid_set(gateNodes, NAV_NODE_GATE, 1, NAV_GATE_TEAM_RED);
ds_grid_set(gateNodes, NAV_NODE_Y, 2, 15 - NAV_BOX_H);
ds_grid_set(gateNodes, NAV_NODE_X0, 2, 15);
ds_grid_set(gateNodes, NAV_NODE_X1, 2, 25);
ds_grid_set(gateNodes, NAV_NODE_GATE, 2, NAV_GATE_NONE);

gateEdges = ds_grid_create(NAV_EDGE_FIELDS, 6);
ds_grid_clear(gateEdges, 0);
// from 0: into the gate, and over it
ds_grid_set(gateEdges, NAV_EDGE_FROM, 0, 0);
ds_grid_set(gateEdges, NAV_EDGE_TO,   0, 1);
ds_grid_set(gateEdges, NAV_EDGE_TYPE, 0, NAV_EDGE_WALK);
ds_grid_set(gateEdges, NAV_EDGE_COST, 0, 13);
ds_grid_set(gateEdges, NAV_EDGE_GATE, 0, NAV_GATE_TEAM_RED);
ds_grid_set(gateEdges, NAV_EDGE_FROM, 1, 0);
ds_grid_set(gateEdges, NAV_EDGE_TO,   1, 2);
ds_grid_set(gateEdges, NAV_EDGE_TYPE, 1, NAV_EDGE_JUMP);
ds_grid_set(gateEdges, NAV_EDGE_COST, 1, 30);
ds_grid_set(gateEdges, NAV_EDGE_GATE, 1, NAV_GATE_TEAM_RED);
// from 1: out of the gate, both ways, ungated
ds_grid_set(gateEdges, NAV_EDGE_FROM, 2, 1);
ds_grid_set(gateEdges, NAV_EDGE_TO,   2, 0);
ds_grid_set(gateEdges, NAV_EDGE_TYPE, 2, NAV_EDGE_WALK);
ds_grid_set(gateEdges, NAV_EDGE_COST, 2, 13);
ds_grid_set(gateEdges, NAV_EDGE_GATE, 2, NAV_GATE_NONE);
ds_grid_set(gateEdges, NAV_EDGE_FROM, 3, 1);
ds_grid_set(gateEdges, NAV_EDGE_TO,   3, 2);
ds_grid_set(gateEdges, NAV_EDGE_TYPE, 3, NAV_EDGE_WALK);
ds_grid_set(gateEdges, NAV_EDGE_COST, 3, 11);
ds_grid_set(gateEdges, NAV_EDGE_GATE, 3, NAV_GATE_NONE);
// from 2: back into the gate, and back over it
ds_grid_set(gateEdges, NAV_EDGE_FROM, 4, 2);
ds_grid_set(gateEdges, NAV_EDGE_TO,   4, 1);
ds_grid_set(gateEdges, NAV_EDGE_TYPE, 4, NAV_EDGE_WALK);
ds_grid_set(gateEdges, NAV_EDGE_COST, 4, 11);
ds_grid_set(gateEdges, NAV_EDGE_GATE, 4, NAV_GATE_TEAM_RED);
ds_grid_set(gateEdges, NAV_EDGE_FROM, 5, 2);
ds_grid_set(gateEdges, NAV_EDGE_TO,   5, 0);
ds_grid_set(gateEdges, NAV_EDGE_TYPE, 5, NAV_EDGE_JUMP);
ds_grid_set(gateEdges, NAV_EDGE_COST, 5, 30);
ds_grid_set(gateEdges, NAV_EDGE_GATE, 5, NAV_GATE_TEAM_RED);

global.navNodes = gateNodes;
global.navEdges = gateEdges;
global.navNodeCount = 3;
global.navEdgeCount = 6;
gateIdx = navEdgeIndex(gateEdges, 6, 3);
global.navEdgeIdx = gateIdx;
global.navRowFor = -1;
global.navRowForCount = 0;
global.navReady = true;

// Sorted by from-node, insertion order preserved within each group. Pinned because
// navEdgeFind returns the *first* edge between a pair and the follower asks it what kind
// of move it is making: a graph that listed the jump first would have a bot try to fly a
// walk.
test_assert_equals(0, navEdgeFind(0, 1));
test_assert_equals(1, navEdgeFind(0, 2));
test_assert_equals(NAV_GATE_TEAM_RED, ds_grid_get(gateEdges, NAV_EDGE_GATE, navEdgeFind(0, 1)));
test_assert_equals(NAV_GATE_NONE, ds_grid_get(gateEdges, NAV_EDGE_GATE, navEdgeFind(1, 2)));

// A red bot walks its own gate: floor, gate, floor - and not the leapfrog jump, which
// it may also take and which costs more.
path = navFindPath(0, 2, TEAM_RED, false, -1, -1);
test_assert_equals(true, path >= 0);
test_assert_equals(3, ds_list_size(path));
test_assert_equals(1, ds_list_find_value(path, 1));
ds_list_destroy(path);

// The same bot carrying the intel may not take its own gate out, and there is no way
// round on this map - including over the top.
test_assert_equals(-1, navFindPath(0, 2, TEAM_RED, true, -1, -1));

// Neither may a blue bot - including by the jump that hops the gate node.
test_assert_equals(-1, navFindPath(0, 2, TEAM_BLUE, false, -1, -1));

// But a blue bot that somehow starts inside the gate can still get out of it.
path = navFindPath(1, 2, TEAM_BLUE, false, -1, -1);
test_assert_equals(true, path >= 0);
test_assert_equals(2, ds_list_size(path));
ds_list_destroy(path);

global.navReady = false;
ds_grid_destroy(gateIdx);
ds_grid_destroy(gateEdges);
ds_grid_destroy(gateNodes);

// ---------------------------------------------------------------------------
// The class gate: a NAV_EDGE_DOUBLEJUMP edge is offered only to a caller that says it
// can double jump.
//
// One graph serves every class, so the Scout's second jump is carried in it with full
// connectivity and refused per query - the same shape as the team gates above, with the
// class in place of the team. Three nodes in a line: 0 -> 1 is an ordinary walk, 1 -> 2
// is the only way on and it needs two impulses.
//
// The default matters as much as the gate. navFindPath's canDouble is argument6, and GM8
// gives an unpassed argument 0, so every caller written before this - including most of
// the assertions above - asks as a class that cannot. That is the conservative answer and
// this pins it: the six-argument call must NOT find the route.
// ---------------------------------------------------------------------------

djNodes = ds_grid_create(NAV_NODE_FIELDS, 3);
ds_grid_clear(djNodes, 0);
ds_grid_set(djNodes, NAV_NODE_Y, 0, 15 - NAV_BOX_H);
ds_grid_set(djNodes, NAV_NODE_X0, 0, 0);
ds_grid_set(djNodes, NAV_NODE_X1, 0, 10);
ds_grid_set(djNodes, NAV_NODE_Y, 1, 15 - NAV_BOX_H);
ds_grid_set(djNodes, NAV_NODE_X0, 1, 11);
ds_grid_set(djNodes, NAV_NODE_X1, 1, 20);
ds_grid_set(djNodes, NAV_NODE_Y, 2, 3 - NAV_BOX_H);
ds_grid_set(djNodes, NAV_NODE_X0, 2, 21);
ds_grid_set(djNodes, NAV_NODE_X1, 2, 30);

djEdges = ds_grid_create(NAV_EDGE_FIELDS, 2);
ds_grid_clear(djEdges, 0);
ds_grid_set(djEdges, NAV_EDGE_FROM, 0, 0);
ds_grid_set(djEdges, NAV_EDGE_TO,   0, 1);
ds_grid_set(djEdges, NAV_EDGE_TYPE, 0, NAV_EDGE_WALK);
ds_grid_set(djEdges, NAV_EDGE_COST, 0, 11);
ds_grid_set(djEdges, NAV_EDGE_GATE, 0, NAV_GATE_NONE);
ds_grid_set(djEdges, NAV_EDGE_REJUMP, 0, -1);
ds_grid_set(djEdges, NAV_EDGE_FROM, 1, 1);
ds_grid_set(djEdges, NAV_EDGE_TO,   1, 2);
ds_grid_set(djEdges, NAV_EDGE_TYPE, 1, NAV_EDGE_DOUBLEJUMP);
ds_grid_set(djEdges, NAV_EDGE_COST, 1, 50);
ds_grid_set(djEdges, NAV_EDGE_GATE, 1, NAV_GATE_NONE);
ds_grid_set(djEdges, NAV_EDGE_REJUMP, 1, 14);

global.navNodes = djNodes;
global.navEdges = djEdges;
global.navNodeCount = 3;
global.navEdgeCount = 2;
djIdx = navEdgeIndex(djEdges, 2, 3);
global.navEdgeIdx = djIdx;
global.navRowFor = -1;
global.navRowForCount = 0;
global.navReady = true;

// A Scout gets the whole route.
path = navFindPath(0, 2, TEAM_RED, false, -1, -1, true);
test_assert_equals(true, path >= 0);
test_assert_equals(3, ds_list_size(path));
test_assert_equals(2, ds_list_find_value(path, 2));
ds_list_destroy(path);

// Anything else gets as far as the ledge and no further.
test_assert_equals(-1, navFindPath(0, 2, TEAM_RED, false, -1, -1, false));

// ...but the walk that shares the graph with it is untouched.
path = navFindPath(0, 1, TEAM_RED, false, -1, -1, false);
test_assert_equals(true, path >= 0);
test_assert_equals(2, ds_list_size(path));
ds_list_destroy(path);

// The six-argument call is the pre-existing one, and it must refuse.
test_assert_equals(-1, navFindPath(0, 2, TEAM_RED, false, -1, -1));

// The re-jump tick survives the round trip into the grid, and is -1 on everything that is
// not a double jump. botPathKeys reads that -1 as "no second press", so a 0 here would put
// an extra jump into every ordinary arc in the game.
test_assert_equals(14, ds_grid_get(djEdges, NAV_EDGE_REJUMP, navEdgeFind(1, 2)));
test_assert_equals(-1, ds_grid_get(djEdges, NAV_EDGE_REJUMP, navEdgeFind(0, 1)));

global.navReady = false;
ds_grid_destroy(djIdx);
ds_grid_destroy(djEdges);
ds_grid_destroy(djNodes);

// ---------------------------------------------------------------------------
// The cache key distinguishes internal maps, which all advertise an empty MD5.
// Keying on the MD5 alone would collide every shipped map onto one entry.
// ---------------------------------------------------------------------------
// These are only bound once a map has loaded, and the suite is meant to run from a
// cold main menu as happily as from inside a game, so read them defensively.
oldMap = "";
oldMd5 = "";
oldArea = 1;
if(variable_global_exists("currentMap"))
    oldMap = global.currentMap;
if(variable_global_exists("currentMapMD5"))
    oldMd5 = global.currentMapMD5;
if(variable_global_exists("currentMapArea"))
    oldArea = global.currentMapArea;

global.currentMapMD5 = "";
global.currentMapArea = 1;
global.currentMap = "ctf_truefort";
test_assert_equals("ctf_truefort_a1", navCacheKey());
global.currentMap = "gg_debug";
test_assert_equals("gg_debug_a1", navCacheKey());

// A custom map's MD5 still participates, so a republish under the same name misses.
global.currentMapMD5 = "abc123";
test_assert_equals("gg_debug_a1_abc123", navCacheKey());

// Separate stages of a multi-area map are separate graphs.
global.currentMapMD5 = "";
global.currentMapArea = 2;
test_assert_equals("gg_debug_a2", navCacheKey());

// Anything a filename cannot carry is folded to an underscore.
global.currentMap = "my map/v2";
global.currentMapArea = 1;
test_assert_equals("my_map_v2_a1", navCacheKey());

global.currentMap = oldMap;
global.currentMapMD5 = oldMd5;
global.currentMapArea = oldArea;

// Hand the running graph back exactly as it was found.
global.navNodes = oldNodes;
global.navEdges = oldEdges;
global.navNodeCount = oldCount;
global.navEdgeCount = oldEdgeCount;
global.navEdgeIdx = oldIdx;
global.navRowStart = oldRowStart;
global.navRowFor = oldRowFor;
global.navRowForCount = oldRowForCount;
global.navReady = oldReady;

test_unit_end();
