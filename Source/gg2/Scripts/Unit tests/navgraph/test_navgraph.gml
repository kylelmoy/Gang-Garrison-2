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

test_unit_begin();

var solidGrid, freeGrid, nodes, edges, w, h;
var oldMap, oldMd5, oldArea;

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
nodes = navNodesExtract(freeGrid, solidGrid, w, h);

test_assert_equals(1, global.navNodeCount);
test_assert_equals(8, ds_grid_get(nodes, NAV_NODE_Y, 0));
test_assert_equals(0, ds_grid_get(nodes, NAV_NODE_X0, 0));
test_assert_equals(w - NAV_BOX_W, ds_grid_get(nodes, NAV_NODE_X1, 0));

// A lone surface has nothing to connect to.
edges = navWalkEdges(nodes, global.navNodeCount, h);
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
nodes = navNodesExtract(freeGrid, solidGrid, w, h);

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
// touch horizontally, so one bidirectional walk connection = 2 directed edges.
// ---------------------------------------------------------------------------
w = 30;
h = 24;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 16, 14, h - 1, 1);
ds_grid_set_region(solidGrid, 15, 15, w - 1, h - 1, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, w, h);
edges = navWalkEdges(nodes, global.navNodeCount, h);

test_assert_equals(2, global.navNodeCount);
test_assert_equals(8, ds_grid_get(nodes, NAV_NODE_Y, 0));
test_assert_equals(9, ds_grid_get(nodes, NAV_NODE_Y, 1));
test_assert_equals(2, global.navEdgeCount);
test_assert_equals(NAV_EDGE_WALK, ds_grid_get(edges, NAV_EDGE_TYPE, 0));
// Emitted as a pair, so the second edge is the reverse of the first.
test_assert_equals(ds_grid_get(edges, NAV_EDGE_FROM, 0), ds_grid_get(edges, NAV_EDGE_TO, 1));
test_assert_equals(ds_grid_get(edges, NAV_EDGE_TO, 0), ds_grid_get(edges, NAV_EDGE_FROM, 1));

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A two-cell step is NOT walkable - it needs a jump edge, which this milestone does
// not generate yet. Same map as above with the right platform one cell higher again.
// ---------------------------------------------------------------------------
w = 30;
h = 24;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 16, 14, h - 1, 1);
ds_grid_set_region(solidGrid, 15, 14, w - 1, h - 1, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, w, h);
edges = navWalkEdges(nodes, global.navNodeCount, h);

test_assert_equals(2, global.navNodeCount);
test_assert_equals(0, global.navEdgeCount);

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
nodes = navNodesExtract(freeGrid, solidGrid, w, h);

test_assert_equals(0, global.navNodeCount);

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

test_unit_end();
