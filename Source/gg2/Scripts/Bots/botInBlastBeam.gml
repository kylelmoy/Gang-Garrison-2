/// botInBlastBeam(char, px, py, fx, fy, sx, sy)
/// True if the point (px, py) is inside the volume this character's airblast would actually
/// reflect. Split out of botIncomingProjectile because that script asks it six times - three
/// projectile types, each at its current position and one tick on - and the alternative is
/// the same four lines of projection written six times.
///
/// (fx, fy) is the aim's unit vector and (sx, sy) its perpendicular, both passed in rather
/// than recomputed: they are the same for every projectile on a given tick, and lengthdir_*
/// is not free inside three `with` loops.
///
/// The volume, and where its three constants come from, is botIncomingProjectile's header.
/// The short version: it is a beam, not a cone, because what gates a reflect is a
/// collision_circle against the AirBlastO's mask - and that mask is 88 px long and 27 px
/// tall, spawned 25 px along the aim. A cone test is the wrong shape at every distance, and
/// the arc it used was wrong by roughly a factor of ten besides.
///
/// Perpendicular offset is compared unsigned, so the beam is symmetric about the aim line.
/// The real mask is very slightly not (-13 above, +14 below); taking the smaller of the two
/// as the half-width is the conservative reading, which is the one to want here - a blast
/// declined costs nothing and a blast spent costs 40 ticks of cooldown.

var char, px, py, fx, fy, sx, sy, dx, dy, fwd;

char = argument0;
px = argument1;
py = argument2;
fx = argument3;
fy = argument4;
sx = argument5;
sy = argument6;

dx = px - char.x;
dy = py - char.y;

fwd = dx * fx + dy * fy;
if(fwd < BOT_AIRBLAST_NEAR)
    return false;
if(fwd > BOT_AIRBLAST_REACH)
    return false;

return (abs(dx * sx + dy * sy) <= BOT_AIRBLAST_HALFW);
