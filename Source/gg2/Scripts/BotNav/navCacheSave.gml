/// navCacheSave(key, nodes, nodeCount, edges, edgeCount, maskW, maskH)
/// Writes a built nav graph to botnav/<key>.txt beside the game, so the next visit to
/// this map is a file read instead of a rebuild. Returns true on success.
///
/// Map rotations repeat constantly, so in practice this makes the expensive path run
/// once per map ever rather than once per rotation (F31).
///
/// Only the node and edge grids are stored. The solidity and clearance grids are
/// build scaffolding - much larger and trivially rederivable - and keeping them would
/// turn a ~100KB cache into several MB for no gain.
///
/// The first line carries NAV_CACHE_VERSION. Bump that constant whenever the node or
/// edge field layout changes, or every server with a warm cache silently loads a
/// graph whose columns mean something else.

var key, nodes, nodeCount, edges, edgeCount, maskW, maskH, f, dir;
key = argument0;
nodes = argument1;
nodeCount = argument2;
edges = argument3;
edgeCount = argument4;
maskW = argument5;
maskH = argument6;

dir = working_directory + "\botnav";
if(!directory_exists(dir))
    directory_create(dir);

f = file_text_open_write(dir + "\" + key + ".txt");
if(f < 0)
    return false;

file_text_write_string(f, "navgraph " + string(NAV_CACHE_VERSION));
file_text_writeln(f);
file_text_write_string(f, string(maskW) + " " + string(maskH) + " " + string(nodeCount) + " " + string(edgeCount));
file_text_writeln(f);
file_text_write_string(f, ds_grid_write(nodes));
file_text_writeln(f);
file_text_write_string(f, ds_grid_write(edges));
file_text_writeln(f);
file_text_close(f);
return true;
