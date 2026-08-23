/// navCacheLoad(key)
/// Loads a nav graph previously written by navCacheSave. Returns true if a usable
/// cache was found, in which case global.navNodes, global.navEdges,
/// global.navNodeCount, global.navEdgeCount, global.navMaskW and global.navMaskH are
/// all populated and the caller owns the two grids.
///
/// Returns false - having allocated nothing - if the file is absent, was written by a
/// different NAV_CACHE_VERSION, or does not deserialise to the shape the header
/// promised. A miss is completely ordinary (first ever visit to a map), so this stays
/// quiet rather than erroring.
///
/// Success is judged by the dimensions ds_grid_read leaves behind rather than by its
/// return value: in GM8 it is a procedure, and treating it as a predicate would read
/// every load as a failure.

var key, path, f, header, dims, nodes, edges, nodeCount, edgeCount, maskW, maskH, ok;
key = argument0;

path = working_directory + "\botnav\" + key + ".txt";
if(!file_exists(path))
    return false;

f = file_text_open_read(path);
if(f < 0)
    return false;

header = file_text_read_string(f);
file_text_readln(f);
if(header != "navgraph " + string(NAV_CACHE_VERSION))
{
    file_text_close(f);
    return false;
}

dims = file_text_read_string(f);
file_text_readln(f);
maskW = real(navToken(dims, 1));
maskH = real(navToken(dims, 2));
nodeCount = real(navToken(dims, 3));
edgeCount = real(navToken(dims, 4));

if(file_text_eof(f))
{
    file_text_close(f);
    return false;
}

nodes = ds_grid_create(NAV_NODE_FIELDS, max(nodeCount, 1));
ds_grid_read(nodes, file_text_read_string(f));
file_text_readln(f);

edges = ds_grid_create(NAV_EDGE_FIELDS, max(edgeCount, 1));
if(!file_text_eof(f))
{
    ds_grid_read(edges, file_text_read_string(f));
    file_text_readln(f);
}
file_text_close(f);

// The header and the payload have to agree, or the columns do not mean what the
// field constants say they mean.
ok = true;
if(ds_grid_width(nodes) != NAV_NODE_FIELDS or ds_grid_height(nodes) < nodeCount)
    ok = false;
if(ds_grid_width(edges) != NAV_EDGE_FIELDS or ds_grid_height(edges) < edgeCount)
    ok = false;

if(!ok)
{
    ds_grid_destroy(nodes);
    ds_grid_destroy(edges);
    return false;
}

global.navNodes = nodes;
global.navEdges = edges;
global.navNodeCount = nodeCount;
global.navEdgeCount = edgeCount;
global.navMaskW = maskW;
global.navMaskH = maskH;

// A cached graph needs the same adjacency index a freshly built one gets, or every
// search on a cache hit would read an index belonging to the previous map.
global.navEdgeIdx = navEdgeIndex(edges, edgeCount, nodeCount);

// And the same row index, for the same reason: navNodeFromWorld reads it on every lookup
// and falls back to scanning the whole node list without it, so a cache hit would quietly
// be an order of magnitude slower to path on than a cold build of the same map. The cache
// does not store it - it is derived from the nodes in a single pass, and the file format
// is unchanged by this, so NAV_CACHE_VERSION stays where it is and every cache already on
// disk stays valid.
global.navRowStart = navRowIndex(nodes, nodeCount, maskH);
global.navRowFor = nodes;
global.navRowForCount = nodeCount;
return true;
