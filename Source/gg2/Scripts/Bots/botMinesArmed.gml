/// botMinesArmed(player, char)
/// True if any mine this bot has out has an enemy inside the radius that actually hurts,
/// which is exactly the moment SPECIAL is worth pressing: the Minegun detonates *every*
/// mine the player owns at once, so the question is never "is this mine worth it" but "is
/// any of them".
///
/// ⚠️ BOT_MINE_TRIGGER is measured against the Mine's *damage* radius, not its
/// affectRadius, and the difference is the whole behaviour. Mine.User Event 2 damages
/// through blastRadius (40), not affectRadius (65), and skips a Character outright when
/// `1 - distance_to_object/blastRadius <= 0.25` - so anything at a bounding-box distance
/// of 30 or more takes *nothing at all*, and 45 damage falls off to 11 across the 30 px
/// that are left. This used to trigger at 60, measured centre to centre, which is outside
/// the blast on every axis: the bot detonated the moment an enemy came near, blew its
/// whole stock of mines, and dealt zero. Reported from play as "detonates too early,
/// doesn't damage enemies", which was exactly right.
///
/// 30 centre-to-centre is the conservative reading of that: a Character's box is ~10 px
/// either side of its centre, so 30 apart horizontally is ~20 of box distance and about
/// 22 damage, and a mine at the feet of someone standing over it is nearer 45.

var player, char, armed;

player = argument0;
char = argument1;
armed = false;

with(Mine)
{
    if(ownerPlayer == player)
    {
        // other is the Mine inside this block; the script's own locals are still visible.
        with(Character)
        {
            if(team != char.team and hp > 0 and !cloak)
            {
                if(point_distance(x, y, other.x, other.y) <= BOT_MINE_TRIGGER)
                    armed = true;
            }
        }
    }
}

return armed;
