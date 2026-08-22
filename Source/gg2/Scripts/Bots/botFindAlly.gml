/// botFindAlly(char, range, skipFollowers)
/// Picks the teammate a Medic bot should have its beam on, or noone. Scored rather than
/// simply nearest: the hurt come first, and between two equally healthy teammates the
/// tougher one wins, because a Medic's job is to keep the biggest body in the fight
/// alive rather than to top up whoever is closest.
///
/// score = 1000 * hp/maxHp + distance - maxHp
///
/// so a Heavy at half health (1000*0.5 + d - 200) outscores a Scout at half health
/// (1000*0.5 + d - 125) by exactly the difference in what they can absorb, and anyone
/// actually wounded outscores anyone who is not by far more than distance can make up.
///
/// Line of sight uses the same Obstacle-typed collision_line the Medigun itself uses to
/// validate a heal target, not collision_line_bulletblocking: a heal beam is stopped by
/// walls the same way a bullet is, but the two predicates are not the same object set
/// and the beam's is the one that decides whether the heal actually connects.
///
/// skipFollowers drops every candidate that is itself a bot of a following class, and it
/// exists because two Medics who pick each other deadlock. The follow goal in
/// botObjectiveUpdate is the ally's own position, so Medic A's goal is where Medic B is
/// standing and Medic B's goal is where Medic A is standing: both are already there, both
/// report arrived, and neither ever leaves spawn. Seen live on koth_valley - two red
/// Medics parked at x=460 with the rest of their team at the point, each holding the
/// other's Character as its ally.
///
/// It is an argument rather than a rule inside this script because the *beam* has no such
/// problem: a Medic healing another Medic is correct play, and botCombatUpdate passes
/// false so that keeps working. Only the thing that turns an ally into a destination
/// needs the exclusion. Filtering during the search rather than rejecting the winner
/// afterwards is what lets the second-best candidate win - a Medic beside a wounded Medic
/// and a healthy Heavy still follows the Heavy, instead of giving up on following at all.
///
/// Human Medics are deliberately not excluded: a person walks somewhere on their own, so
/// following one is a destination that actually moves, and no cycle can form.

var char, range, skipFollowers, queue, ally, candidate, best;

char = argument0;
range = argument1;
skipFollowers = argument2;
queue = ds_priority_create();

with(Character)
{
    if(id != char and team == char.team and hp > 0)
    {
        var dist, isFollower;

        // ⚠️ -1 is GM8's `self`, not "no instance", so an unguarded player.class here
        // would silently read the *Character's* own class rather than failing.
        isFollower = false;
        if(skipFollowers and player != -1)
            isFollower = (player.isBot and botClassProfile(player.class, BOT_CP_FOLLOW));

        dist = point_distance(x, y, char.x, char.y);
        if(dist <= range and !isFollower)
            ds_priority_add(queue, id, 1000 * hp / maxHp + dist - maxHp);
    }
}

ally = noone;
while(ally == noone and !ds_priority_empty(queue))
{
    candidate = ds_priority_delete_min(queue);
    if(!collision_line(char.x, char.y, candidate.x, candidate.y, Obstacle, true, true))
        ally = candidate;
}

ds_priority_destroy(queue);
return ally;
