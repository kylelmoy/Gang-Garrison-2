# NPC Bots

Design notes for server-side AI players ("bots"). This is a condensed copy of the working
research/design record; see the project's planning notes for full findings (F1-F35) if you need
the "why" behind something here.

## The core idea

The server is authoritative and broadcasts every player's *inputs* each tick; clients simulate
locally from them (`Character.events/User Event 12.xml`, `GameServerBeginStep.gml`). So a bot is
nothing more than a server-side `Player` whose `Character.keyState` / `netAimDirection` /
`aimDistance` are written by AI code instead of by `processClientCommands`. Movement, weapons,
damage, the kill log, the scoreboard, and chat bubbles all already work unmodified. **Vanilla
clients need zero changes** and can join a bot-enabled server without any patch.

Design rule: bots must be expressible entirely through *existing* wire messages. Do not touch
`PROTOCOL_UUID` or widen the protocol.

## Architecture, coarsest first

1. **Bot identity** — `isBot` flag on `Player` (default `false`). Three call sites treat a `Player`
   as if it owned a real socket and must be guarded:
   - `GameServerBeginStep.gml`'s roster loop (`socket_has_error`/`kicked` reaping) — bots skip the
     socket-error check but still honour `kicked`, so the admin kick UI works on them for free.
   - `GameServerEndStep.gml`'s broadcast loop (`write_buffer(socket, ...)`).
   - `Scripts/Plugins/API/PluginPacketSendTo.gml` and `acceptJoiningPlayer.gml`'s multi-client-IP
     count.
   Slot accounting (`getNumberOfOccupiedSlots.gml`) excludes bots, so bots never cost a human a
   `SERVER_FULL`. Class limits, team balance, the scoreboard, and the Arena "wait for players"
   check already iterate `with(Player)` and count bots automatically — no change needed there.
2. **Population manager** — server-side, decides bot count per team from human count / target
   fill / difficulty; adds/removes on join, leave, and map change; picks classes via
   `checkClasslimits`. Bots must be re-teamed after every map change (the engine drops every
   `Player`, bots included, to spectator on map change; humans get a menu to re-pick, bots don't).
3. **Input driver** — per bot, per virtual (30 Hz) tick: compute `keyState` / `aimDirection` /
   `aimDistance` on the bot's `Character`, then call `event_user(1)` so `pressedKeys`/`releasedKeys`
   edge detection fires (jump, cloak, taunt all depend on this). Lives in
   `GameServerBeginStep.gml`'s roster loop, in the `else` branch beside
   `processClientCommands(player, i)` — the same point a human's `INPUTSTATE` is consumed, so
   ordering matches a human's by construction.
4. **Navigation** — built once per map load, server-only, from the walkmask
   (`global.CustomMapCollisionSprite`). A trajectory-fan nav graph (Pignole-style), simulated with
   the game's own physics update so it's exact by construction, chunked across frames so it never
   blocks socket servicing, and cached to disk keyed by map MD5.
5. **Combat/behaviour** — target selection modelled on `SentryTurret`'s End Step (a `ds_priority`
   over nearby `Character`s, LOS via `collision_line_bulletblocking`), plus per-class firing policy
   and a difficulty model (aim error, reaction latency, decision cadence).
6. **Configuration** — `[Bots]` section in `gg2.ini`, plus a **Bots** tab in the hosting menu.

## Gotchas worth remembering

- **Never call `place_free` / `collision_point_solid` from nav or AI code.** Collision solidity is
  toggled on/off every frame (`charSetSolids`/`charUnsetSolids`) and is `false` outside that
  bracket, so those calls silently report open space everywhere. Use
  `collision_point(px, py, CustomMapO, false, true)` (precise mask, solidity-independent) instead.
  `collision_line_bulletblocking` is exempt — it's object-typed, not solidity-typed — and is safe
  to call from anywhere, including target-selection AI.
- **Every new object/script/constant costs a full Game Maker build.** Splice-only changes to
  existing script bodies are fast; new resources are not. `AgentSpare0..3` (four blank objects
  already compiled into the dev template) let a *new object's* behaviour be prototyped at ~3s
  before promoting it to a real named object.
- **A whole-map nav build is seconds of blocking work** — fine in the map editor, not fine as a
  blocking loop on a live server. Chunk it across frames from an alarm, and cache the built graph
  to disk keyed by map MD5 so the expensive path runs once per map ever.
- **Almost nothing in GG2 is hitscan.** Only the Sniper Rifle is true hitscan; every other weapon
  (including Scattergun, Shotgun, Minigun, Revolver) drops with per-tick gravity. A bot's aim
  solver needs drop compensation on all of them, not just the obviously-lobbed Minegun.

## Status

- **M0** — `isBot` flag, the three socket guards, and slot accounting: implemented and verified
  against a live server + client session.
- **M1** — `botAdd(team, class, name)` / `botRemove(player)` roster insertion: implemented
  (`Scripts/Bots/botAdd.gml`, `Scripts/Bots/botRemove.gml`) and verified — a bot added this way is
  visible identically on the host and a real connected client, spawns a class-correct `Character`,
  can be damaged and killed (producing a correctly attributed kill-log line), and removal is
  broadcast like a real disconnect.
- **M2** — population manager, `[Bots]` ini config, and hosting menu tab: implemented
  (`Scripts/Bots/botPopulationUpdate.gml`, `botPickTeam.gml`, `botReteamAll.gml`;
  `BotsMenuController`) and verified — bots are added/removed automatically to track
  `FillToPlayers`/`MaxBots`/`MinHumans`, removal respects `RemoveOnDeath`/`RemoveTimeoutSeconds`
  (deferred until death or timeout rather than an abrupt kick), the lobby broadcast reports the
  real bot count, and `botReteamAll` correctly re-teams/re-classes bots reset to spectator by a map
  change.
- **M3** — input driver: implemented (`Scripts/Bots/botInputUpdate.gml`, `botFindTarget.gml`) and
  verified — bots pick the nearest visible enemy in range (`SentryTurret`-style `ds_priority` +
  `collision_line_bulletblocking`), aim and hold fire at it, and re-decide only every 15 ticks
  (staggered per bot) rather than tracking continuously. Confirmed via genuine bot-vs-bot combat
  (real kills, real respawns) and a direct `event_user(1)`/`pressedKeys` edge-detection check.
- **M4 onward** (navigation, path following, objectives/per-class/difficulty) are tracked in the
  project's working notes, not yet implemented. Bots currently do not move — they stand at spawn
  and fight whatever comes into range.
