/// botIsCharacter(inst)
/// True if a combat target is a player character rather than a piece of map furniture.
///
/// The combat chain reads a dozen fields off whatever it is shooting at - cloak, onground,
/// player, hspeed - and every one of them exists only on a Character. Reading onground off a
/// Generator in GM8 is not a false, it is a hard runtime error; reading player off a Sentry
/// silently returns some other instance's variable. So every one of those reads is guarded,
/// and this is the one place that decides what is being guarded against.
///
/// It used to be a botTargetIsGen flag, written when a Generator was the only non-Character a
/// bot could target (M7 6.3). Adding the Sentry made the question "is this a Character",
/// not "is this a generator" - and a flag named after one specific exception is a flag that
/// quietly stops covering the next one. Asking the object instead means a new target type
/// needs no new flag at all.
///
/// WARNING: named botIsCharacter and not botTargetIsChar, which is the obvious name and is
/// also the name of the Player variable this fills in. In GM8 a script name is a read-only
/// compile-time constant, so a script and an instance variable sharing a name makes every
/// assignment to that variable a compilation error - and a compilation error here takes the
/// whole game down at startup rather than failing loudly at the line. Caught by gml-lint's
/// assign-to-resource-name rule; nothing about the code looks wrong.
///
/// object_is_ancestor as well as a plain compare, because the class characters (Scout,
/// Soldier and the rest) are children of Character - the parent is never instantiated
/// directly, so the compare alone would answer false for every real player in the game.

var inst;
inst = argument0;

if(inst == noone)
    return false;
if(!instance_exists(inst))
    return false;
if(inst.object_index == Character)
    return true;
return object_is_ancestor(inst.object_index, Character);
