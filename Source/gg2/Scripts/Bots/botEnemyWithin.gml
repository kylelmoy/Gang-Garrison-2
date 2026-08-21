/// botEnemyWithin(char, range)
/// True if any living, visible enemy Character is within range of char. No line of sight
/// test: this answers "is there a fight here", which is what an Uber or a sandvich is
/// decided on, and a wall between them does not make an enemy two metres away safe.

var char, range, found;

char = argument0;
range = argument1;
found = false;

with(Character)
{
    if(team != char.team and hp > 0 and !cloak)
    {
        if(point_distance(x, y, char.x, char.y) <= range)
            found = true;
    }
}

return found;
