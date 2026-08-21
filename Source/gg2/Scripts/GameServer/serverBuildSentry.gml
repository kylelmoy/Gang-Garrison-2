/// serverBuildSentry(player, playerId)
/// The server side of an Engineer building a sentry: check the preconditions, broadcast
/// it, build it. Does nothing if any precondition fails, exactly as the client command
/// did.
///
/// Extracted from processClientCommands' BUILD_SENTRY case so that a bot can build one.
/// Building is a client command rather than a key, so a bot has no other way to ask for
/// it, and the preconditions are numerous enough (class, 100 nuts and bolts, no sentry
/// within 50 px, not inside a SpawnRoom, no sentry already owned, not on a cabinet) that
/// a second copy of them would be a second chance to get them wrong.
///
/// ⚠️ The two buffers below are not a typo and must not be "fixed" here. The message byte
/// and player id go to global.sendBuffer while the three coordinate fields go to
/// global.serializeBuffer, and it works only because serializeState assigns
/// global.serializeBuffer = global.sendBuffer every tick, so the stale alias from the
/// previous tick happens to point at the right buffer. Quietly correcting it would
/// change the byte order on the wire for every existing client.

var player, playerId;

player = argument0;
playerId = argument1;

if(player.object == -1)
    exit;

if(player.class == CLASS_ENGINEER
        and collision_circle(player.object.x, player.object.y, 50, Sentry, false, true) < 0
        and player.object.nutsNBolts == 100
        and (collision_point(player.object.x,player.object.y,SpawnRoom,0,0) < 0)
        and !player.sentry
        and !player.object.onCabinet)
{
    write_ubyte(global.sendBuffer, BUILD_SENTRY);
    write_ubyte(global.sendBuffer, playerId);
    write_ushort(global.serializeBuffer, round(player.object.x*5));
    write_ushort(global.serializeBuffer, round(player.object.y*5));
    write_byte(global.serializeBuffer, player.object.image_xscale);
    buildSentry(player, player.object.x, player.object.y, player.object.image_xscale);
}
