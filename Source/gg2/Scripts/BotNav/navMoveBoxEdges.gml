/// navMoveBoxEdges(freeGrid, nodeGrid, gateGrid, nodes, w, h)
/// Appends one edge per MoveBoxUp/Down/Left/Right instance in the room: walking into
/// it accelerates the character while inside its bounding box, exactly as
/// Character's own collision code does it (Collision with MoveBoxUp/Down/Left/Right.xml
/// add pushPower to vspeed/hspeed every tick of overlap), and ordinary gravity carries
/// it the rest of the way once it leaves the box. Simulated the same way jump edges
/// are (F35): step the real per-tick update and sample the clearance grid, rather than
/// fit a closed form - there is no closed form here, since the accelerated interval's
/// length depends on the box's own size, not a fixed launch impulse.
///
/// Entry is approximated as the node directly under the box's horizontal centre - a
/// bot walking up to the box along the ground, which is how every shipped use of
/// MoveBox is placed. One edge per box; MoveBox's own footprint is small enough that a
/// takeoff fan is not worth it (unlike navJumpEdges, there is exactly one place a
/// character can enter from).
///
/// This is a single-shot pass over room instances, not a chunked one: there are at
/// most a handful of MoveBox instances on any shipped map, against hundreds of nodes,
/// so it costs nothing next to the stages either side of it.
///
/// gateGrid may be -1, and `nodes` may be -1 with it. When both are supplied the
/// simulated path is sampled for gate cells the same way navJumpEdges samples an arc,
/// so a boost that carries a character through a gate is offered only to whoever may
/// pass it. `nodes` is needed only to read the entry node's own gate code, so that a
/// box standing inside a gate does not charge every edge leaving it.
///
/// Cost is charged in ticks alone, no jump-style penalty - F24 lists these among the
/// map's "free traversal edges", so a route through one should not be punished
/// relative to walking the same ground.

var freeGrid, nodeGrid, gateGrid, nodes, w, h;
var maxY, entryX, entryY, entryNode, pushX, pushY, boxL, boxT, boxR, boxB;
var vx, vy, wx, wy, t, cx, cy, landed, blocked, cost, srcGate, arcGate, cellGate;

freeGrid = argument0;
nodeGrid = argument1;
gateGrid = argument2;
nodes = argument3;
w = argument4;
h = argument5;

maxY = h - NAV_BOX_H;

with(MoveBox)
{
    pushX = 0;
    pushY = 0;
    if(object_index == MoveBoxUp)
        pushY = -pushPower;
    else if(object_index == MoveBoxDown)
        pushY = pushPower;
    else if(object_index == MoveBoxLeft)
        pushX = -pushPower;
    else if(object_index == MoveBoxRight)
        pushX = pushPower;

    boxL = bbox_left;
    boxR = bbox_right;
    boxT = bbox_top;
    boxB = bbox_bottom;

    entryX = max(0, min(w - NAV_BOX_W, round((boxL + boxR) / 2 / NAV_CELL_SIZE)));

    // Find the nearest standable row at or below the box's top - the box may sit
    // flush with the floor or float a little above it.
    entryNode = -1;
    entryY = max(0, floor(boxT / NAV_CELL_SIZE));
    while(entryY <= maxY)
    {
        if(ds_grid_get(freeGrid, entryX, entryY) != 1)
            break;
        entryNode = ds_grid_get(nodeGrid, entryX, entryY);
        if(entryNode >= 0)
            break;
        entryY += 1;
    }

    if(entryNode >= 0)
    {
        srcGate = NAV_GATE_NONE;
        if(nodes >= 0)
            srcGate = ds_grid_get(nodes, NAV_NODE_GATE, entryNode);
        arcGate = NAV_GATE_NONE;

        vx = 0;
        vy = 0;
        wx = entryX * NAV_CELL_SIZE + NAV_CELL_SIZE / 2;
        wy = entryY * NAV_CELL_SIZE;
        landed = -1;
        blocked = false;

        for(t = 1; t <= NAV_JUMP_MAX_TICKS; t += 1)
        {
            vy += NAV_JUMP_GRAVITY;

            // The push applies for every tick the character's current position
            // overlaps the box, mirroring the collision event firing every step of
            // overlap rather than once on entry.
            if(wx >= boxL and wx <= boxR and wy >= boxT and wy <= boxB)
            {
                vx += pushX;
                vy += pushY;
            }

            vx = max(-15, min(15, vx));
            vy = max(-15, min(15, vy));
            wx += vx;
            wy += vy;

            cx = round(wx / NAV_CELL_SIZE);
            cy = round(wy / NAV_CELL_SIZE);

            if(cx < 0 or cx > w - NAV_BOX_W or cy > maxY)
            {
                blocked = true;
                break;
            }

            // Above the top of the walkmask is open sky, not a ceiling (F38) - only
            // sample once the arc is back over the mask.
            if(cy >= 0)
            {
                if(ds_grid_get(freeGrid, cx, cy) != 1)
                {
                    blocked = true;
                    break;
                }

                // Separate if, never folded into a condition beside the handle test
                // (F40).
                if(arcGate == NAV_GATE_NONE and gateGrid >= 0)
                {
                    cellGate = ds_grid_get(gateGrid, cx, cy);
                    if(cellGate != NAV_GATE_NONE and cellGate != srcGate)
                        arcGate = cellGate;
                }

                landed = ds_grid_get(nodeGrid, cx, cy);
                if(landed >= 0 and landed != entryNode and vy >= 0)
                    break;
                landed = -1;
            }
        }

        if(!blocked and landed >= 0)
        {
            cost = max(1, t);
            if(arcGate == NAV_GATE_NONE and nodes >= 0)
                arcGate = ds_grid_get(nodes, NAV_NODE_GATE, landed);
            navEdgeAdd(entryNode, landed, NAV_EDGE_MOVEBOX, 0, t, cost, arcGate);
        }
    }
}
