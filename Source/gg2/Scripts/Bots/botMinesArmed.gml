/// botMinesArmed(player, char)
/// True if any mine this bot has out has an enemy inside its blast, which is exactly the
/// moment SPECIAL is worth pressing: the Minegun detonates *every* mine the player owns
/// at once, so the question is never "is this mine worth it" but "is any of them".
///
/// BOT_MINE_TRIGGER is a little under the Mine's own affectRadius, so the detonation
/// catches someone walking in rather than someone already walking out.

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
