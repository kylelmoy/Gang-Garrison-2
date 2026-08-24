/// botIncomingProjectile(char, minTravel)
/// True if a reflectable enemy projectile is somewhere the airblast can actually reach, and
/// has already flown minTravel px from whoever fired it: the Pyro's airblast test, and its
/// only caller.
///
/// The reflectable set is Rocket, Flare and Mine (Flamethrower's User Event 2).
///
/// ⚠️ This used to ask a radius-and-arc question - within BOT_AIRBLAST_RANGE (150) and
/// within BOT_AIRBLAST_ARC (75 deg) of the aim - and both numbers were wrong in the same
/// way: they were copied from the Flamethrower's own blastDistance (150) and blastAngle
/// (75), which no longer gate a reflect. In User Event 2 blastDistance only scales the
/// knockback dealt to Characters, and the `angle` local computed in every reflect block is
/// dead code. What actually gates a reflect is
///
///     collision_circle(projectile.x, projectile.y, 5, poof, false, true)
///
/// against an AirBlastO spawned 25 px along the aim, whose mask is a narrow beam. So the
/// bot was pressing SPECIAL for rockets it could not possibly touch - anything inside a
/// 150 px circle, at up to 75 deg off-axis, against a beam covering well under 20 deg - and
/// the press is not free: the reflect test runs ONLY on the press frame, and the press sets
/// readyToBlast false for blastReloadTime (40 ticks). A rocket at 150 px is ~12 ticks from
/// impact, so the wasted blast was still on cooldown when it arrived. Reported from play as
/// a Pyro unable to deflect rockets even from a large distance, and that is the whole
/// mechanism: not a delay that was too long, a trigger volume ~10x wider than the weapon.
///
/// The beam, measured off the running exe rather than off the sprite file, which does not
/// agree with it: AirBlastMaskS is a 120x30 image, but its mask bounds are AUTO, so GM8
/// takes them from the opaque pixels and the box is bbox_left 8, bbox_right 96, bbox_top
/// -13, bbox_bottom 14 relative to the poof's own origin. The poof spawns 25 px out, and
/// collision_circle adds its 5 px radius, which gives the three constants:
///
///     BOT_AIRBLAST_NEAR   28    8 + 25 - 5. There IS a near edge, and it is not a
///                               rounding detail: a rocket already at the Pyro's feet is
///                               UNDER the beam and cannot be blasted at all.
///     BOT_AIRBLAST_REACH  126   96 + 25 + 5.
///     BOT_AIRBLAST_HALFW  18    13 + 5, taking the smaller of the mask's -13/+14.
///
/// Rotation is handled, and was verified the same way rather than assumed: at image_angle
/// 90 the box reads -13/14/-96/-8, which is the 0 deg box turned a quarter. At 45 deg GM8
/// gives the axis-aligned bounds of the rotated rectangle (-4/78/-77/4), which is a
/// superset of the true beam - so modelling the beam as a straight rectangle is the
/// conservative reading on the diagonals, and conservative is the right direction to be
/// wrong in. Declining a blast costs nothing; spending one costs 40 ticks.
///
/// Both the projectile's current position and its position one tick on are tested, and
/// either will do. The press and the blast do not resolve in the same place in the frame -
/// botInputUpdate writes keyState, Character's Begin Step runs User Event 2, and
/// move_all_bullets moves the projectile - and a rocket covers ~12 px a tick, which is most
/// of the beam's half-width. Rather than depend on that ordering, allow the frame either
/// way round.
///
/// minTravel is the reaction time, and it is a DISTANCE on purpose. The airblast had no
/// delay of any kind: this is re-evaluated every tick and the bit was returned the frame a
/// rocket appeared, so a rocket fired point-blank came back on the frame it was born.
/// Confirmed inhuman, exactly as reported from play. It is 60 rather than the 120 it was
/// first set to, and the beam is why: the window is now 28 to 126 px, so a shooter standing
/// 130 px away produced a rocket that was never eligible at any point on its flight. 60 px
/// is ~5 ticks of rocket travel, which still says "not the frame it left the barrel" -
/// which was all it was ever for.
///
/// Distance beats an age counter twice over. It says "do not reflect a rocket the instant
/// it leaves the barrel" directly rather than by proxy, it is frame-rate independent, and
/// Rocket already maintains exactly this number: move_all_bullets sets travelDistance from
/// the owner's live position every step, for the game's own 800px fade.
///
/// Flare and Mine carry no travelDistance, so theirs is measured to the owner's Character
/// behind an instance_exists guard. A projectile whose owner has since died has nothing to
/// measure against and is treated as having travelled far enough - it has, by then.
///
/// None of the projectile types share a parent object, so each needs its own pass. There
/// are never many of any of them alive at once.

var char, minTravel, found, travelled, fx, fy, sx, sy;

char = argument0;
minTravel = argument1;

found = false;

// The aim's unit vector and its perpendicular, once. lengthdir_* rather than cos/sin
// because GM8's y axis points down and these already account for it.
fx = lengthdir_x(1, char.aimDirection);
fy = lengthdir_y(1, char.aimDirection);
sx = lengthdir_x(1, char.aimDirection + 90);
sy = lengthdir_y(1, char.aimDirection + 90);

with(Rocket)
{
    if(ownerPlayer.team != char.team and travelDistance >= minTravel)
    {
        if(botInBlastBeam(char, x, y, fx, fy, sx, sy)
           or botInBlastBeam(char, x + hspeed, y + vspeed, fx, fy, sx, sy))
            found = true;
    }
}

with(Flare)
{
    travelled = minTravel;
    if(instance_exists(ownerPlayer))
    {
        if(botIsCharacter(ownerPlayer.object))
            travelled = point_distance(x, y, ownerPlayer.object.x, ownerPlayer.object.y);
    }
    if(ownerPlayer.team != char.team and travelled >= minTravel)
    {
        if(botInBlastBeam(char, x, y, fx, fy, sx, sy)
           or botInBlastBeam(char, x + hspeed, y + vspeed, fx, fy, sx, sy))
            found = true;
    }
}

with(Mine)
{
    travelled = minTravel;
    if(instance_exists(ownerPlayer))
    {
        if(botIsCharacter(ownerPlayer.object))
            travelled = point_distance(x, y, ownerPlayer.object.x, ownerPlayer.object.y);
    }
    if(ownerPlayer.team != char.team and travelled >= minTravel)
    {
        if(botInBlastBeam(char, x, y, fx, fy, sx, sy)
           or botInBlastBeam(char, x + hspeed, y + vspeed, fx, fy, sx, sy))
            found = true;
    }
}

return found;
