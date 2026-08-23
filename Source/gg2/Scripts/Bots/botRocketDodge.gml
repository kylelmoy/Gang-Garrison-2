/// botRocketDodge(char)
/// True if jumping right now would take this bot out of the path of a rocket that is
/// otherwise going to hit it. Grounded callers only - it models the jump from a standstill.
///
/// The old test was "is an enemy projectile within 150px", and it was wrong in both
/// directions. It jumped at rockets that were never going to connect, and - reported from
/// play - it jumped *into* the ones fired over the bot's head: a rocket passing above is
/// exactly the case where rising 57px is what creates the collision, so aiming high was a
/// guaranteed hit rather than a miss. Anything that answers this question has to model the
/// arc, because "would it hit" and "does jumping help" have opposite answers depending on
/// where the shot is aimed, and no proximity test can tell them apart.
///
/// The model is small because both bodies are:
///
///   rocket    straight line at constant velocity. GG2 rockets have no gravity and no
///             drag; Create sets alarm[3] and nothing ever touches hspeed/vspeed again.
///             So its position t ticks out is just (x + hspeed*t, y + vspeed*t).
///   bot       horizontally, whatever it is doing now (hspeed carried forward, which is
///             what the follower is holding). Vertically, either standing still or flying
///             the standing jump: rise(t) = NAV_JUMP_V0*t - NAV_JUMP_GRAVITY*t^2/2, the
///             same closed form navJumpHeight uses.
///
/// Both futures are walked tick by tick rather than solved, because the answer wanted is
/// not "when is the closest approach" but "does either box ever contain it", and the two
/// boxes are 26 ticks of a parabola apart. The verdict is:
///
///   jump  <=>  the standing bot is hit at some tick  AND  the jumping bot is hit at none
///
/// which is the whole feature: never jump at a rocket that misses anyway, and never jump
/// into one. A rocket aimed at the feet clears easily (any rise beats it), one aimed at
/// the chest needs ~13px of rise and so about two ticks of warning, and one aimed above
/// the head fails the first half of the test and is left alone - which is the reported bug,
/// stated as a rule rather than patched as a case.
///
/// Splash is deliberately not modelled. A rocket that detonates on the floor underneath a
/// jumping bot still catches it inside blastRadius 65, so counting splash would refuse
/// nearly every dodge; what the jump reliably avoids is the direct hit (25 damage plus the
/// 30 from the explosion centred on the body, plus the knockback), and that is worth having.

var char, found, bodyX, bodyY, rocketX, rocketY, halfW, jumpY, rise;
var t, hitStanding, hitJumping, done;

char = argument0;
found = false;

// The rocket's own size, folded into the body box once here rather than into every test.
halfW = BOT_BODY_HALFW + BOT_ROCKET_RADIUS;

with(Rocket)
{
    if(ownerPlayer.team != char.team
       and point_distance(x, y, char.x, char.y) <= BOT_DODGE_RANGE)
    {
        hitStanding = false;
        hitJumping = false;
        done = false;

        for(t = 1; t <= BOT_DODGE_TICKS; t += 1)
        {
            if(!done)
            {
                rocketX = x + hspeed * t;
                rocketY = y + vspeed * t;
                bodyX = char.x + char.hspeed * t;

                if(abs(rocketX - bodyX) <= halfW)
                {
                    bodyY = char.y;
                    if(rocketY >= bodyY - BOT_BODY_UP - BOT_ROCKET_RADIUS
                       and rocketY <= bodyY + BOT_BODY_DOWN + BOT_ROCKET_RADIUS)
                        hitStanding = true;

                    // Above the takeoff point by this much on tick t. Negative once the
                    // arc has come back down past where it started, which is why this is
                    // subtracted rather than clamped - a late crossing is met by a bot
                    // that is falling again, and that has to count as a hit.
                    rise = NAV_JUMP_V0 * t - NAV_JUMP_GRAVITY * t * t / 2;
                    jumpY = char.y - rise;
                    if(rocketY >= jumpY - BOT_BODY_UP - BOT_ROCKET_RADIUS
                       and rocketY <= jumpY + BOT_BODY_DOWN + BOT_ROCKET_RADIUS)
                        hitJumping = true;
                }

                // Nothing later in the walk can change the verdict for this rocket.
                if(hitStanding and hitJumping)
                    done = true;
            }
        }

        if(hitStanding and !hitJumping)
            found = true;
    }
}

return found;
