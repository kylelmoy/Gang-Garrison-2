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
// navNodesExtract takes -1 for the platform, lethal and door grids here: those come
// from map instances rather than the walkmask, and a suite that builds bare terrain
// has none of them. The platform, door and movebox cases below supply their own -
// the movebox case is the only one that creates a real instance, since pushPower
// lives on the object rather than in any grid.

test_unit_begin();

var solidGrid, freeGrid, platformGrid, lethalGrid, doorGrid, gateGrid, nodeGrid, nodes, edges, w, h;
var oldMap, oldMd5, oldArea, oldSetup, gateInst, gl, gt, gr, gb;
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
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, -1, -1, w, h);

test_assert_equals(1, global.navNodeCount);
test_assert_equals(8, ds_grid_get(nodes, NAV_NODE_Y, 0));
test_assert_equals(0, ds_grid_get(nodes, NAV_NODE_X0, 0));
test_assert_equals(w - NAV_BOX_W, ds_grid_get(nodes, NAV_NODE_X1, 0));

// A lone surface has nothing to connect to, and both its ends run off the map.
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, -1, w, h);
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
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, -1, -1, w, h);

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
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, -1, w, h);

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
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, -1, w, h);

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
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, -1, -1, w, h);

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
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, -1, w, h);

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
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, -1, w, h);

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
nodes = navNodesExtract(freeGrid, solidGrid, platformGrid, -1, -1, -1, w, h);

// The ground surface, plus the platform surface standing on nothing but platform.
test_assert_equals(2, global.navNodeCount);

// The platform-supported run is flagged; the ground run is not. Ordering is by y,
// so the platform surface - higher up, smaller y - comes first.
test_assert_equals(1, ds_grid_get(nodes, NAV_NODE_FLAGS, 0));
test_assert_equals(0, ds_grid_get(nodes, NAV_NODE_FLAGS, 1));

edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, -1, w, h);
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
nodes = navNodesExtract(freeGrid, solidGrid, -1, lethalGrid, -1, -1, w, h);
test_assert_equals(0, global.navNodeCount);

ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(lethalGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// Two nodes split on the very same row (a terrain/platform kind change, F39) still
// have to be walkable into each other - it is one continuous floor. Before same-row
// walk edges existed, navWalkEdges only ever looked at the row below, so this pair
// had no edge between them at all despite being physically touching ground.
//
// Left half (x 0..14) is solid terrain; right half (x 15..29) is platform-supported.
// Both at row 15, so the run only splits because the support kind changes, not
// because of height.
// ---------------------------------------------------------------------------
w = 30;
h = 20;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 15, 14, h - 1, 1);

platformGrid = ds_grid_create(w, h);
ds_grid_clear(platformGrid, 0);
ds_grid_set_region(platformGrid, 15, 15, w - 1, 15, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, platformGrid, -1, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, -1, w, h);

test_assert_equals(2, global.navNodeCount);
test_assert_equals(0, ds_grid_get(nodes, NAV_NODE_FLAGS, 0));
test_assert_equals(1, ds_grid_get(nodes, NAV_NODE_FLAGS, 1));

// Same height, same row: a walk both ways and nothing else - no ledge to fall from,
// no gap to jump.
test_assert_equals(2, global.navEdgeCount);
test_assert_equals(2, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_WALK));

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(platformGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A LeftDoor cell splits a run and blocks only the leftward crossing.
//
// Same flat floor as the very first case, but doorGrid marks x 13..14 (at the
// anchor row, y=8) as NAV_DOOR_LEFT - "blocks players trying to go left"
// (Character.events/Collision with LeftDoor.xml fires only on hspeed < 0). That
// isolates the door's own footprint as its own node between the two halves of the
// floor, and the rightward pair of same-row walk edges should exist, the leftward
// pair should not.
//
// navJumpEdges is not door-aware, and does not need to be: node 0 and node 2 are not
// touching (node 1, the door, sits between them), so its own "already covered by a
// walk edge" skip does not fire, and it happily offers a same-row jump straight past
// the door in both directions. That is a real gap - a bot could plan a jump that
// hops over a door it is not allowed to cross - but a deliberately accepted one: real
// collision still enforces the door regardless of how the character got there
// (Character's own Collision with LeftDoor.xml fires on any hspeed < 0, airborne or
// not), so the worst case is the same "walked into something solid" stuck state
// milestone 5's re-planning already has to handle for far more mundane reasons.
// Teaching every edge generator about every barrier type is not worth it for a
// two-cell door; this suite exists to pin the actual count so that stops being true
// silently rather than to pretend the gap does not exist.
// ---------------------------------------------------------------------------
w = 30;
h = 20;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 15, w - 1, h - 1, 1);

doorGrid = ds_grid_create(w, h);
ds_grid_clear(doorGrid, NAV_DOOR_NONE);
ds_grid_set_region(doorGrid, 13, 8, 14, 8, NAV_DOOR_LEFT);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, doorGrid, -1, w, h);

test_assert_equals(3, global.navNodeCount);
test_assert_equals(NAV_DOOR_NONE, ds_grid_get(nodes, NAV_NODE_DOOR, 0));
test_assert_equals(NAV_DOOR_LEFT, ds_grid_get(nodes, NAV_NODE_DOOR, 1));
test_assert_equals(NAV_DOOR_NONE, ds_grid_get(nodes, NAV_NODE_DOOR, 2));
test_assert_equals(13, ds_grid_get(nodes, NAV_NODE_X0, 1));
test_assert_equals(14, ds_grid_get(nodes, NAV_NODE_X1, 1));

edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, -1, w, h);

// Rightward across both boundaries, never leftward - plus the two same-row jump
// edges (both directions) that leapfrog the door, per the note above.
test_assert_equals(4, global.navEdgeCount);
test_assert_equals(2, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_WALK));
test_assert_equals(2, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_JUMP));

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(doorGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// A MoveBoxDown instance pushes a character from a drop-through platform down to
// the ground below it, faster and by a more direct route than gravity alone.
//
// Both surfaces span the full map width, so neither has an edge to fall off, and the
// platform (row 7) sits directly above the ground (row 20) - the only bare
// connection between them is navDropEdges' straight drop through the platform's own
// middle. A real MoveBoxDown instance (42x42 world px, read live off a running game
// rather than guessed - GM8 has no way to ask a sprite's size without one) sits at
// the platform's surface; while a character's simulated position is inside it,
// pushPower (5) adds to vspeed every tick on top of gravity (0.6), the same as
// Character's own Collision with MoveBoxDown.xml. Hand-traced tick by tick: vspeed
// saturates at the 15px/tick cap (F24) after 3 ticks, still inside the box; two more
// ticks of coasting at the cap after leaving it lands exactly on the ground node's
// anchor row at tick 6. Only the movebox pass is exercised here (not
// navEdgesBuild's full set), so the pre-existing drop-through edge cannot be
// mistaken for the one this test is actually checking.
// ---------------------------------------------------------------------------
w = 20;
h = 24;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 20, w - 1, h - 1, 1);

platformGrid = ds_grid_create(w, h);
ds_grid_clear(platformGrid, 0);
ds_grid_set_region(platformGrid, 0, 7, w - 1, 7, 1);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, platformGrid, -1, -1, -1, w, h);

test_assert_equals(2, global.navNodeCount);
test_assert_equals(0, ds_grid_get(nodes, NAV_NODE_Y, 0));
test_assert_equals(13, ds_grid_get(nodes, NAV_NODE_Y, 1));

instance_create(48, 0, MoveBoxDown);

nodeGrid = navNodeGrid(nodes, global.navNodeCount, w, h);
navEdgesBegin();
navMoveBoxEdges(freeGrid, nodeGrid, -1, -1, w, h);
ds_grid_resize(global.navAccEdges, NAV_EDGE_FIELDS, max(global.navAccCount, 1));
edges = navEdgesSortByFrom(global.navAccEdges, global.navAccCount, global.navNodeCount);
ds_grid_destroy(global.navAccEdges);
global.navAccEdges = -1;
global.navEdgeCount = global.navAccCount;
global.navAccCount = 0;

test_assert_equals(1, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_MOVEBOX));
test_assert_equals(0, ds_grid_get(edges, NAV_EDGE_FROM, 0));
test_assert_equals(1, ds_grid_get(edges, NAV_EDGE_TO, 0));
test_assert_equals(6, ds_grid_get(edges, NAV_EDGE_TICKS, 0));

with(MoveBoxDown)
    instance_destroy();

ds_grid_destroy(edges);
ds_grid_destroy(nodeGrid);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(platformGrid);
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
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, -1, -1, w, h);
edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, -1, w, h);

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

path = navFindPath(0, 2, TEAM_RED, false, -1);
test_assert_equals(true, path >= 0);
test_assert_equals(3, ds_list_size(path));
test_assert_equals(0, ds_list_find_value(path, 0));
test_assert_equals(2, ds_list_find_value(path, 2));
ds_list_destroy(path);

// A path to itself is one node, not zero and not a loop.
path = navFindPath(1, 1, TEAM_RED, false, -1);
test_assert_equals(1, ds_list_size(path));
ds_list_destroy(path);

// Out of range asks are refused rather than clamped.
test_assert_equals(-1, navFindPath(0, 99, TEAM_RED, false, -1));
test_assert_equals(-1, navFindPath(-1, 0, TEAM_RED, false, -1));

global.navReady = false;
global.navEdgeIdx = oldIdx;
ds_grid_destroy(testIdx);

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// navGatePassable's truth table, straight off charSetSolids.gml.
//
// Your own team gate is open unless you are carrying the intel out through it; an
// enemy intel gate is shut only to a carrier; a setup gate is shut for everyone while
// setup is running. Nothing here touches the graph - this is the whole of what the
// build cannot decide for itself (F26), so it is worth pinning on its own.
// ---------------------------------------------------------------------------
test_assert_equals(true, navGatePassable(NAV_GATE_NONE, TEAM_BLUE, true));

test_assert_equals(true, navGatePassable(NAV_GATE_TEAM_RED, TEAM_RED, false));
test_assert_equals(false, navGatePassable(NAV_GATE_TEAM_RED, TEAM_RED, true));
test_assert_equals(false, navGatePassable(NAV_GATE_TEAM_RED, TEAM_BLUE, false));
test_assert_equals(true, navGatePassable(NAV_GATE_TEAM_BLUE, TEAM_BLUE, false));
test_assert_equals(false, navGatePassable(NAV_GATE_TEAM_BLUE, TEAM_RED, false));

// An intel gate is a filter on carriers, not on teams: everyone else walks through.
test_assert_equals(true, navGatePassable(NAV_GATE_INTEL_RED, TEAM_BLUE, false));
test_assert_equals(false, navGatePassable(NAV_GATE_INTEL_RED, TEAM_BLUE, true));
test_assert_equals(true, navGatePassable(NAV_GATE_INTEL_RED, TEAM_RED, true));

// A code this build does not know can only be a cache written by a newer version, and
// is refused rather than waved through.
test_assert_equals(false, navGatePassable(99, TEAM_RED, false));

// The setup gate reads live state, so it is only asserted where that state is
// actually determinate: FauxCPHUD overrides global.setupTimer when a CP map is up.
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
// A team gate across a corridor, end to end: node cut, edge annotation, and A*
// refusing to route through it for whoever may not pass.
//
// Same flat floor as the door case, but the gate band is a full-height column at
// x = 13..14 rather than two cells on the anchor row, which is what a real gate stamp
// looks like once navGateStamp has dilated it. That matters: the two-cell version
// would cut the node correctly and still leave navJumpEdges free to hop the gap above
// it.
//
// Three nodes - floor, gate, floor - and six edges: four same-row walks across the two
// boundaries, plus the pair of jumps that leapfrog the gate node entirely. Those jumps
// are exactly why the gate code lives on the edge rather than only on the node; their
// arcs pass through the gate column at head height, so they carry its code too and are
// refused along with everything else.
// ---------------------------------------------------------------------------
w = 30;
h = 20;
solidGrid = ds_grid_create(w, h);
ds_grid_clear(solidGrid, 0);
ds_grid_set_region(solidGrid, 0, 15, w - 1, h - 1, 1);

gateGrid = ds_grid_create(w, h);
ds_grid_clear(gateGrid, NAV_GATE_NONE);
ds_grid_set_region(gateGrid, 13, 0, 14, 8, NAV_GATE_TEAM_RED);

freeGrid = navClearanceBuild(solidGrid, w, h);
nodes = navNodesExtract(freeGrid, solidGrid, -1, -1, -1, gateGrid, w, h);

test_assert_equals(3, global.navNodeCount);
test_assert_equals(NAV_GATE_NONE, ds_grid_get(nodes, NAV_NODE_GATE, 0));
test_assert_equals(NAV_GATE_TEAM_RED, ds_grid_get(nodes, NAV_NODE_GATE, 1));
test_assert_equals(NAV_GATE_NONE, ds_grid_get(nodes, NAV_NODE_GATE, 2));
test_assert_equals(13, ds_grid_get(nodes, NAV_NODE_X0, 1));
test_assert_equals(14, ds_grid_get(nodes, NAV_NODE_X1, 1));

edges = navEdgesBuild(nodes, global.navNodeCount, freeGrid, gateGrid, w, h);

test_assert_equals(6, global.navEdgeCount);
test_assert_equals(4, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_WALK));
test_assert_equals(2, navCountEdgeType(edges, global.navEdgeCount, NAV_EDGE_JUMP));

// Sorted by from-node, insertion order preserved within each group. Entering the gate
// is gated; leaving it is not, which is what keeps a bot already standing in one from
// being stranded there.
test_assert_equals(1, ds_grid_get(edges, NAV_EDGE_TO, 0));
test_assert_equals(NAV_GATE_TEAM_RED, ds_grid_get(edges, NAV_EDGE_GATE, 0));
test_assert_equals(2, ds_grid_get(edges, NAV_EDGE_TO, 1));
test_assert_equals(NAV_EDGE_JUMP, ds_grid_get(edges, NAV_EDGE_TYPE, 1));
test_assert_equals(NAV_GATE_TEAM_RED, ds_grid_get(edges, NAV_EDGE_GATE, 1));
test_assert_equals(0, ds_grid_get(edges, NAV_EDGE_TO, 2));
test_assert_equals(NAV_GATE_NONE, ds_grid_get(edges, NAV_EDGE_GATE, 2));
test_assert_equals(2, ds_grid_get(edges, NAV_EDGE_TO, 3));
test_assert_equals(NAV_GATE_NONE, ds_grid_get(edges, NAV_EDGE_GATE, 3));

global.navNodes = nodes;
global.navEdges = edges;
testIdx = navEdgeIndex(edges, global.navEdgeCount, global.navNodeCount);
oldIdx = -1;
if(variable_global_exists("navEdgeIdx"))
    oldIdx = global.navEdgeIdx;
global.navEdgeIdx = testIdx;
global.navReady = true;

// A red bot walks its own gate: floor, gate, floor.
path = navFindPath(0, 2, TEAM_RED, false, -1);
test_assert_equals(true, path >= 0);
test_assert_equals(3, ds_list_size(path));
test_assert_equals(1, ds_list_find_value(path, 1));
ds_list_destroy(path);

// The same bot carrying the intel may not take its own gate out, and there is no way
// round on this map.
test_assert_equals(-1, navFindPath(0, 2, TEAM_RED, true, -1));

// Neither may a blue bot - including by the jump that hops the gate node.
test_assert_equals(-1, navFindPath(0, 2, TEAM_BLUE, false, -1));

// But a blue bot that somehow starts inside the gate can still get out of it.
path = navFindPath(1, 2, TEAM_BLUE, false, -1);
test_assert_equals(true, path >= 0);
test_assert_equals(2, ds_list_size(path));
ds_list_destroy(path);

global.navReady = false;
global.navEdgeIdx = oldIdx;
ds_grid_destroy(testIdx);

ds_grid_destroy(edges);
ds_grid_destroy(nodes);
ds_grid_destroy(freeGrid);
ds_grid_destroy(gateGrid);
ds_grid_destroy(solidGrid);

// ---------------------------------------------------------------------------
// navGateStamp dilates a real gate instance up and left by the character box.
//
// The only gate case that creates an instance, because the stamp is derived from
// bbox_*, which only a live instance has. The expected region is computed from that
// instance's own bbox rather than from a guess at the sprite's size, so this pins the
// dilation rule and not the art.
//
// navGateStamp is called directly rather than through navMarkInstances, which would
// also sweep up every gate the running map already has - this suite has to give the
// same answer run from a cold main menu and run mid-game on ctf_truefort, and a real
// spawn gate landing on one of the probe cells below would decide otherwise.
//
// Why dilate at all: a nav anchor is the top-left of a NAV_BOX_W x NAV_BOX_H body, so
// a gate covering only rows an anchor never sits on - one hanging clear of the floor,
// say - would cut no node boundary at all and the graph would let both teams stroll
// through it.
// ---------------------------------------------------------------------------
w = 120;
h = 120;
gateGrid = ds_grid_create(w, h);
ds_grid_clear(gateGrid, NAV_GATE_NONE);

gateInst = instance_create(240, 240, RedTeamGate);
test_assert_equals(TEAM_RED, gateInst.team);
with(gateInst)
{
    gl = floor(bbox_left / NAV_CELL_SIZE);
    gt = floor(bbox_top / NAV_CELL_SIZE);
    gr = floor(bbox_right / NAV_CELL_SIZE);
    gb = floor(bbox_bottom / NAV_CELL_SIZE);
    navGateStamp(gateGrid, w, h, NAV_GATE_TEAM_RED);
}

// The gate's own footprint, and the dilated corner an anchor would stand at.
test_assert_equals(NAV_GATE_TEAM_RED, ds_grid_get(gateGrid, gl, gt));
test_assert_equals(NAV_GATE_TEAM_RED, ds_grid_get(gateGrid, gr, gb));
test_assert_equals(NAV_GATE_TEAM_RED, ds_grid_get(gateGrid, gl - (NAV_BOX_W - 1), gt - (NAV_BOX_H - 1)));

// One cell further out is clear: the dilation is exactly a body, not a blanket.
test_assert_equals(NAV_GATE_NONE, ds_grid_get(gateGrid, gl - NAV_BOX_W, gt));
test_assert_equals(NAV_GATE_NONE, ds_grid_get(gateGrid, gl, gt - NAV_BOX_H));

// Down and right are not dilated - a body below or right of the gate is clear of it.
test_assert_equals(NAV_GATE_NONE, ds_grid_get(gateGrid, gr + 1, gb));
test_assert_equals(NAV_GATE_NONE, ds_grid_get(gateGrid, gr, gb + 1));

with(gateInst)
    instance_destroy();
ds_grid_destroy(gateGrid);

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
