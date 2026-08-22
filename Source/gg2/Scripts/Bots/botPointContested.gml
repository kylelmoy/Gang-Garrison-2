/// botPointContested(point, team)
/// True if an enemy of `team` is standing on this control point, or has already put some
/// capture progress on it. Any ControlPoint-family instance will do - Arena, KOTH, DKOTH
/// and the symmetrical/AD points are all children of ControlPoint and inherit both the
/// presence counters and the capping state from its Step event.
///
/// Presence is the signal that matters, not `capping`. ControlPoint recomputes
/// redPresence/bluePresence every step from the Characters whose cappingPoint is this
/// point, so it is true on the frame an enemy steps inside the zone - while `capping` is a
/// meter that takes a second to become non-zero, and by the time it reads as a capture the
/// point is a third gone. A defender that only reacts to the meter is a defender that
/// arrives after the fight.
///
/// The values are 0 (nobody), 1 (only an ubered enemy, who cannot cap but does deny) and 2
/// (real cappers), and all three of those want the same answer here: an enemy is on our
/// point and standing somewhere else is not a plan.
///
/// `capping` is still consulted, because a capture already under way is contested even in
/// the moment nobody is standing on it - progress decays slowly (one point a tick) and a
/// bot that walks away the instant the zone empties gives the same enemy their progress
/// back for free.

var point, team, enemyPresence;

point = argument0;
team = argument1;

if(point == noone)
    return false;
if(!instance_exists(point))
    return false;

// A locked point cannot be captured by anybody, so nothing about it is contested and a
// defender is better off where its own logic wants to be.
if(point.locked)
    return false;

if(team == TEAM_RED)
    enemyPresence = point.bluePresence;
else
    enemyPresence = point.redPresence;

if(enemyPresence > 0)
    return true;

// Enemy progress on the meter, with nobody currently standing there.
if(point.capping > 0 and point.cappingTeam != team and point.cappingTeam != -1)
    return true;

return false;
