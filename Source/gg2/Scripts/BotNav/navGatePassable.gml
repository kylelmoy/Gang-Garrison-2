/// navGatePassable(gateCode, team, hasIntel)
/// Whether a character of the given team, carrying the intel or not, may walk through
/// a node carrying this gate code. NAV_GATE_NONE is always passable.
///
/// This is the whole reason gates are not baked into the nav grid (F26): the answer
/// depends on who is asking, so it has to be evaluated per query rather than per
/// build. One graph therefore serves both teams, carriers and non-carriers alike.
///
/// The rules mirror charSetSolids.gml exactly, which is the only place the engine
/// decides this, and which sets solidity from the *gate's* point of view with the
/// character as `other`:
///
///   TeamGate   solid = (team != other.team or other.intel)
///   IntelGate  solid = (team != other.team and other.intel)
///   ControlPointSetupGate  solid = areSetupGatesClosed()
///
/// Inverted, that is: your own team gate is open unless you are carrying intel out of
/// it; an enemy intel gate is closed only to a carrier; a setup gate is closed during
/// setup, for everyone.
///
/// areSetupGatesClosed() is read live rather than passed in - it is a two-instance
/// check, it changes on its own timer rather than per caller, and a stale copy would
/// mean bots pathing through gates that shut a second ago.

var gateCode, team, hasIntel;
gateCode = argument0;
team = argument1;
hasIntel = argument2;

if(gateCode == NAV_GATE_NONE)
    return true;

if(gateCode == NAV_GATE_TEAM_RED)
    return (team == TEAM_RED and !hasIntel);
if(gateCode == NAV_GATE_TEAM_BLUE)
    return (team == TEAM_BLUE and !hasIntel);

if(gateCode == NAV_GATE_INTEL_RED)
    return (team == TEAM_RED or !hasIntel);
if(gateCode == NAV_GATE_INTEL_BLUE)
    return (team == TEAM_BLUE or !hasIntel);

if(gateCode == NAV_GATE_SETUP)
    return !areSetupGatesClosed();

// An unknown code is a graph built by a newer version than this one, or a corrupt
// cache entry. Refusing passage is the safe answer: a bot that will not walk through
// something is worse behaviour, not a broken game.
return false;
