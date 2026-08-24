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
///
/// A Sentry and a Generator are asked the same question with a different metric, and the
/// difference is not a refinement - it is the only reading that works. This script used to
/// scan `with(Character)` and nothing else, so a Demoman that had chosen a sentry as its
/// target (botCombatUpdate takes Sentry and Generator targets, and botClassKeys lobs at
/// them) put its whole stock of mines on that sentry and then never pressed SPECIAL, because
/// no Character was ever standing next to them. Reported from play as "shooting grenades at
/// sentries, but not detonating", which was exactly it. Mine.User Event 2 does damage both -
/// a Sentry for explosionDamage*3/2, a Generator for the flat value - so the shots were
/// wasted purely because the detonate test could not see the thing the bot had aimed at.
///
/// The metric is `distance_to_object`, which is box to box, because that is the test the
/// engine's own damage block uses on these two: `distance_to_object(mine) < blastRadius`
/// with the same `1 - d/blastRadius <= 0.25` skip, so anything at 30 or more takes nothing.
/// BOT_MINE_TRIGGER is that same 30 and needs no second constant - but it is being read as a
/// box distance here and as a centre distance above, which is right, since a Character is
/// ~10 px of box either side of its centre while a Sentry is a wide object whose centre may
/// be 30 px from the mine sitting against its base.

var player, char, armed;

player = argument0;
char = argument1;
armed = false;

with(Mine)
{
    if(ownerPlayer == player)
    {
        // other is the Mine inside these blocks; the script's own locals are still visible.
        with(Character)
        {
            if(team != char.team and hp > 0 and !cloak)
            {
                if(point_distance(x, y, other.x, other.y) <= BOT_MINE_TRIGGER)
                    armed = true;
            }
        }

        with(Sentry)
        {
            if(team != char.team and hp > 0)
            {
                if(distance_to_object(other) < BOT_MINE_TRIGGER)
                    armed = true;
            }
        }

        with(Generator)
        {
            if(team != char.team and hp > 0)
            {
                if(distance_to_object(other) < BOT_MINE_TRIGGER)
                    armed = true;
            }
        }
    }
}

return armed;
