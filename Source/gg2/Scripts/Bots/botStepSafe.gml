/// botStepSafe(char, dir)
/// True if this character can take one step in dir (-1 left, +1 right) and still be standing
/// on something. Two questions, both asked with the character's own mask at the position it
/// would occupy: is there a wall in the way, and is there a floor under it.
///
/// It exists for the engage hold in botInputUpdate, which is the first behaviour in the bot
/// layer that presses a movement key the path follower did not ask for. Everything else that
/// moves a bot horizontally is either following an edge the generator validated or backing
/// off a single step inside its own blast radius; a Pyro closing on a target is neither, so
/// it is walking on ground nothing has checked. On a map with a pit beside the route - which
/// is not hypothetical here, see ctf_truefort - a bot chasing an enemy across a gap walks
/// into a hole it cannot climb out of, and stays there until it dies.
///
/// ⚠️ place_meeting against Obstacle, not place_free. place_free tests the `solid` flag, and
/// this codebase toggles that flag underneath itself - gunSetSolids/gunUnsetSolids bracket
/// every hitscan trace - so what place_free answers depends on where in the frame it is
/// asked. Naming the object is both explicit and stable.
///
/// The drop tolerance is deliberately short. This is not "can the bot get there", which is
/// navFindPath's question and is answered against the graph; it is only "does the ground
/// continue", so a step down to a lower ledge reads as safe and a step over a pit does not.

var char, dir, ahead, safe;

char = argument0;
dir = argument1;

safe = false;

with(char)
{
    ahead = x + dir * BOT_ENGAGE_STEP;

    // A wall where the bot would stand: not unsafe, but not worth pressing into either -
    // the press achieves nothing and the stuck detector in botPathKeys counts it.
    if(!place_meeting(ahead, y, Obstacle))
    {
        if(place_meeting(ahead, y + BOT_ENGAGE_DROP, Obstacle))
            safe = true;
    }
}

return safe;
