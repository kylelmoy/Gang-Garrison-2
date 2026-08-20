// void test_navgraph()
// Nav graph builder unit test.
//
// Every case builds its own walkmask with ds_grid_set_region rather than reading
// terrain, so the suite needs no map loaded, no server, and is fully deterministic
// (F33). Nothing here depends on instance ids, current_time, fps or global.currentMap
// except the cache-key case, which saves and restores what it touches.
//
// Geometry throughout is in mask cells: 1 cell = 6 world px, and the character box is
// NAV_BOX_W x NAV_BOX_H = 4 x 7 cells, which covers Heavy (F24).
//
// navNodesExtract takes -1 for the platform and lethal grids here: those come from
// map instances rather than the walkmask, and a suite that builds bare terrain has
// neither. The platform case below supplies its own.

test_unit_begin();

var solidGrid, freeGrid, platformGrid, lethalGrid, nodes, edges, w, h;
var oldMap, oldMd5, oldArea;
var path, oldNodes, oldEdges, oldCount, oldEdgeCount, oldReady, testIdx, oldIdx;

// This suite may run against a server with a live nav graph. navNodesExtract and
// navEdgesBuild both report their results through globals, so every case below
// overwrites the running graph book-keeping. Save it all now and put it back at the
// end, or a passing test run leaves the server pathing against nonsense.
oldNodes = -1;
oldEdges = -1;
oldCount = 0;
oldEdgeCount = 0;
oldReady = false;
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

// ---------------------------------------------------------------------------
// A single flat floor produces exactly one surface.
//
// 20x20, solid from row 15 down. The character box needs 7 clear rows, so the only
// standable anchor row is y = 8: rows 8..14 are clear and row 15 (just under the box)
// is solid. y = 9 would put the box's bottom row inside the floor.
// ---------------------------------------------------------------------------
w = 20;
h = 20;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 15, w - 1, h - 1, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, w, h);

test_assert_equals(1, global.navNodeCount);
test_assert_equals(8, ds_grid_get(nodes, NAV_NODE_Y, 0));
test_assert_equals(0, ds_grid_get(nodes, NAV_NODE_X0, 0));
test_assert_equals(w - NAV_BOX_W, ds_grid_get(nodes, NAV_NODE_X1, 0));

// A lone surface has nothing to connect to, and both its ends run off the map.
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, w, h);
test_assert_equals(0, global.navEdgeCount);

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// Clearance rejects a gap the character cannot fit through.
//
// Same floor, but a ceiling slab four rows above it leaves only a 4-cell corridor
// where the box needs 7. There is nowhere to stand at all.
// ---------------------------------------------------------------------------
w = 20;
h = 20;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 15, w - 1, h - 1, 1);
ds_grid_set_region(solidGrid, 0, 0, w - 1, 10, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, w, h);

test_assert_equals(0, global.navNodeCount);

ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A one-cell step is walkable in both directions.
//
// 30x24. Left platform solid from row 16, right platform from row 15 - exactly one
// mask cell (6 world px) higher, which characterHitObstacle steps up for free (F24).
// The two surfaces come out as y=8 spanning x 12..26 and y=9 spanning x 0..11, which
// touch horizontally, so they get one bidirectional walk connection.
// ---------------------------------------------------------------------------
w = 30;
h = 24;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 16, 14, h - 1, 1);
ds_grid_set_region(solidGrid, 15, 15, w - 1, h - 1, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, w, h);

test_assert_equals(2, global.navNodeCount);
test_assert_equals(8, ds_grid_get(nodes, NAV_NODE_Y, 0));
test_assert_equals(9, ds_grid_get(nodes, NAV_NODE_Y, 1));

// Two walk edges, one each way for the step, plus a one-way fall off the upper
// surface left end down onto the lower one.
test_assert_equals(3, global.navEdgeCount);
test_assert_equals(2, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_WALK));
test_assert_equals(1, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_FALL));

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A two-cell step is NOT walkable - it needs a jump edge, which is not generated yet.
// Same map as above with the right platform one cell higher again.
// ---------------------------------------------------------------------------
w = 30;
h = 24;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 16, 14, h - 1, 1);
ds_grid_set_region(solidGrid, 15, 14, w - 1, h - 1, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, w, h);

test_assert_equals(2, global.navNodeCount);

// Too tall to step, so no walk edge - but a character can still walk off the upper
// ledge and drop, which is one-way until jump edges exist to supply the return.
test_assert_equals(0, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_WALK));
test_assert_equals(1, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_FALL));

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A map smaller than the character box yields nothing rather than erroring.
// ---------------------------------------------------------------------------
w = 3;
h = 3;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, w, h);

test_assert_equals(0, global.navNodeCount);

ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A gap inside the jump envelope gets jump edges both ways; one beyond it gets none.
//
// Two platforms at the same height either side of a bottomless pit, so nothing can
// walk across and nothing can fall to a landing - any connection has to be a jump.
//
// The envelope is GG2's own: v0 8.3 against gravity 0.6 gives a flat jump of about
// 27.7 ticks, and at Heavy's 4.53 px/tick that is roughly 125 world px, or 20 cells.
// 13 cells apart is comfortably inside it; 28 cells is comfortably outside.
// ---------------------------------------------------------------------------
w = 60;
h = 24;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 16, 14, h - 1, 1);
ds_grid_set_region(solidGrid, 30, 16, w - 1, h - 1, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, w, h);

test_assert_equals(2, global.navNodeCount);
test_assert_equals(0, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_WALK));
// The pit has no floor, so there is nothing to fall onto either.
test_assert_equals(0, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_FALL));
test_assert_equals(2, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_JUMP));

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

// The same map with the far platform pushed out past the envelope.
w = 80;
h = 24;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 16, 14, h - 1, 1);
ds_grid_set_region(solidGrid, 45, 16, w - 1, h - 1, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, w, h);

test_assert_equals(2, global.navNodeCount);
test_assert_equals(0, global.navEdgeCount);

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A drop-through platform is standable, and can be dropped through.
//
// Ground at row 20, and a platform two rows thick at row 12 floating above it. The
// platform is NOT terrain - a character jumps up through it freely - so it goes in
// its own grid, and the surface it offers is only usable downward by holding DOWN.
// ---------------------------------------------------------------------------
w = 40;
h = 32;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 20, w - 1, h - 1, 1);

platformGrid = ds_grid_create(w, h);
ds_grid_clear(platformGrid, 0);
ds_grid_set_region(platformGrid, 10, 12, 25, 12, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, platformGrid, -1, w, h);

// The ground surface, plus the platform surface standing on nothing but platform.
test_assert_equals(2, global.navNodeCount);

// The platform-supported run is flagged; the ground run is not. Ordering is by y,
// so the platform surface - higher up, smaller y - comes first.
test_assert_equals(1, ds_grid_get(nodes, NAV_NODE_FLAGS, 0));
test_assert_equals(0, ds_grid_get(nodes, NAV_NODE_FLAGS, 1));

edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, w, h);
test_assert_equals(1, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_DROPTHROUGH));

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(platformGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A lethal volume is never offered as somewhere to stand.
//
// The same flat floor as the very first case, but with a killbox lying along it.
// ---------------------------------------------------------------------------
w = 20;
h = 20;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 15, w - 1, h - 1, 1);

lethalGrid = ds_grid_create(w, h);
ds_grid_clear(lethalGrid, 0);
ds_grid_set_region(lethalGrid, 0, 15, w - 1, 15, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, lethalGrid, w, h);
test_assert_equals(0, global.navNodeCount);

ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(lethalGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A* over the built graph.
//
// Three stepped platforms, each one cell above the next, so the whole thing is walk
// connected end to end and a path across it has to pass through the middle.
//
// navFindPath reads the graph from globals rather than taking it as arguments, since
// there is one graph per server, so this stands them up and puts them back.
// ---------------------------------------------------------------------------
w = 44;
h = 24;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 17, 14, h - 1, 1);
ds_grid_set_region(solidGrid, 15, 16, 29, h - 1, 1);
ds_grid_set_region(solidGrid, 30, 15, w - 1, h - 1, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, w, h);

global.navNodes = nodes;
global.navEdges = edges;
// navFindPath reads a prebuilt adjacency index rather than deriving one per call, so
// a stand-in graph has to supply its own or the search walks the live map's ranges.
testIdx = navEdgeIndex(edges, global.navEdgeCount, global.navNodeCount);
oldIdx = -1;
if(variable_global_exists("navEdgeIdx"))
    oldIdx = global.navEdgeIdx;
global.navEdgeIdx = testIdx;
global.navReady = true;

// Three surfaces, and every one reachable from every other.
test_assert_equals(3, global.navNodeCount);

path = navFindPath(0, 2);
test_assert_equals(true, path >= 0);
test_assert_equals(3, ds_list_size(path));
test_assert_equals(0, ds_list_find_value(path, 0));
test_assert_equals(2, ds_list_find_value(path, 2));
ds_list_destroy(path);

// A path to itself is one node, not zero and not a loop.
path = navFindPath(1, 1);
test_assert_equals(1, ds_list_size(path));
ds_list_destroy(path);

// Out of range asks are refused rather than clamped.
test_assert_equals(-1, navFindPath(0, 99));
test_assert_equals(-1, navFindPath(-1, 0));

global.navReady = false;
global.navEdgeIdx = oldIdx;
ds_grid_destroy(testIdx);

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

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
global.navReady = oldReady;

test_unit_end();
