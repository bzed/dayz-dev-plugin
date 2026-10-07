# Testing the Client Side of a Mod, Automatically

`local-server.md` proves the server half of a mod. Anything a player drives (UI, input, what the
client sees after the server changed something, RPCs in both directions) needs a real DayZ
client. This page runs one without a monitor, connects it to a local server, and lets the mod
report test results by itself.

Everything marked **(tested)** was run on Linux with the stable client and server 1.29.163709
(Steam client app 221100) and, unless a line says otherwise, the same way on the experimental client and
server 1.30.164014.27 (app 1024020, see "Experimental"). Both with GE-Proton11-1, an AMD GPU through
Vulkan/RADV and sway 1.12.

## What you need

- A running **Steam** client, logged in, owning DayZ. The game talks to it. **(tested)**
- The DayZ client (221100) installed, and a Proton tool. On Linux there is no native client.
- `sway` and `grim` (`apt install sway grim`). Nothing else: sway runs on a virtual output.
- A server tree (`local-server.md`, section 2) with the mods and their `.bikey` files linked.
- The mods also linked into the **client's** DayZ directory, see below.

## Ground rules: one game, many servers, stop early

- **Only one game (client) can run at a time.** A Steam account runs one game at once, and a second client
  on the machine would fight the first over the GPU, the Wine prefix and the Steam connection. This holds
  across stable and experimental, and it includes the user's own game: if they are playing DayZ, wait or ask.
  Many **servers** can run side by side, each on its own tree and ports (`local-server.md`).
- **Check before you start a game.** `dayz-client-headless.sh status` lists any running DayZ client (exit 1
  if there is one); `start` and `dayz-client-test.sh` run the same check and refuse to start a second game.
  Never kill a game you did not start: look at its PID and arguments first. **(tested: `status` with no game)**
- **Stop the game as soon as you no longer need it.** It holds the GPU and several GB of RAM, and the Steam
  account shows "playing DayZ". Run `stop` right after the last screenshot or log you need, not at the end of
  the session, and before any long wait or unrelated work. `dayz-client-test.sh` stops its client itself,
  also on failure, timeout or Ctrl-C. Servers are cheap by comparison, but stop them too when done.

## 1. Run the client without a display

`scripts/dayz-client-headless.sh` starts a headless sway (`WLR_BACKENDS=headless`, 1280x720) and
launches the game inside it. Nothing appears on your desktop. **(tested)**

```sh
S="${CLAUDE_SKILL_DIR}/scripts/dayz-client-headless.sh"
$S start /tmp/dzc -name=autotest "-mod=@9dd22c91;@MyMod" -connect=127.0.0.1 -port=$GAME
$S shot  /tmp/dzc /tmp/dzc/now.png      # screenshot of the headless output, read it with an image viewer
$S stop  /tmp/dzc                       # ends sway, which ends the game
```

**Why not `steam -applaunch 221100 ...`?** Steam is a single instance per user, so the command hands the
launch to the Steam that is already running, and the game would inherit *that* Steam's display (your
desktop), not the one you set for the command. (Reasoned from how Steam forwards launches; not run.)
The script runs the chain Steam itself uses
(Steam Linux Runtime 4 `_v2-entry-point` -> `proton run` -> `DayZ_x64.exe`) from inside the headless
session instead, so the game inherits that session's display. The Steam API handshake still works
because it only needs the running Steam client. **(tested)**

Other things the script does, and why:

- `for_window [app_id="dayz_x64.exe"] fullscreen enable`: without it the game window is larger than the
  1280x720 output and the screenshot is cropped. With it the whole HUD is in frame. **(tested)**
- It passes `-nolauncher -skipintro -window -nosplash -noPause`. `-connect=<ip> -port=<port>` joins the
  server straight from the command line, no clicks needed. **(tested)**
- `-name=<x>` sets the player name; the server's admin log shows it, which is the cheapest "client connected" check.
- It writes DayZ's arguments one per line into a file. A `;` in `-mod=@a;@b` would otherwise be cut by
  sway's command parser.
- `PROTON` (default `GE-Proton11-1`) and `STEAM_ROOT` are environment variables; set them to match the
  Proton tool Steam selected for DayZ. `PROTON_ENABLE_WAYLAND=1` is set, as in the user's Steam launch options.

## 2. Mods on the client

The client loads a mod by folder name from the DayZ install directory, so link it there:

```sh
ln -sfn "$PWD/build/@MyMod" "<library>/steamapps/common/DayZ/@MyMod"     # your own build
```

The client directory is `<library>/steamapps/common/DayZ`, in the library that holds app 221100.
**(tested)** Workshop mods may already have a hashed link there, such as
`@9dd22c91 -> workshop/content/221100/1559212036`; use whatever is already there. This writes into
the Steam install directory (a symlink only); remove it when the test mod is no longer needed.

- **Use the client-side names in `-mod=` for the client**, which can differ from the server's.
  The server's `@CF` and the client's `@9dd22c91` are the same mod. Passing a name that does not exist
  in the client directory loads nothing and the game still starts (it even shows the "modded game"
  notice). **(tested)**
- **The symptom of a wrong or missing client mod** is the server kicking the player:
  `Client is missing a mod which is on the server. (<mod names>) (Missing PBO.)` in the server's output
  and `script`/RPT lines. **(tested)** Read it before assuming a networking problem.
- Put dependencies first: CF before a mod that needs it. (The working runs used this order; the wrong
  order was not tried.)
- **Signing.** Keep `verifySignatures = 2` on the server and put every mod's `.bikey` in the tree's
  `keys/`. The workshop mods ship their keys; for your own build use `dayz-mod-pack.sh keygen/build`.
  Signed mods with their keys installed joined fine. **(tested)** An unsigned mod with signature checks on
  was not tried.
- **BattlEye.** The client started this way does not start BattlEye, so set `BattlEye = 0;` in the tree's
  `serverDZ.cfg`. **(tested)**

## Experimental (1.30)

Experimental is separate in every path, and has **no Workshop of its own**: you cannot subscribe to or
download mods through it. The mods come from stable.

| | Stable | Experimental |
|---|---|---|
| Client app / directory | 221100, `steamapps/common/DayZ` | 1024020, `steamapps/common/DayZ Exp` |
| Server app / directory | 223350, `DayZServer` | 1042420, `DayZ Server Exp` (`find-dayzserver.sh -e`) |
| Wine prefix | `compatdata/221100` | `compatdata/1024020` |
| Client logs | `.../AppData/Local/DayZ/` | `.../AppData/Local/DayZ Exp/` (note the space) |
| Script log line | `  SCRIPT       : text` | `21:21:01.843  SCRIPT       : text` (timestamp prefix) |

How to run an experimental test **(tested, 1.30.164014.27)**:

1. **Get the mods through stable.** Subscribe in the Steam Workshop and let the *stable* DayZ client download
   them. They land in `steamapps/workshop/content/221100/<id>`. On the verification machine
   `workshop/content/1024020` is already a symlink to `221100`, so experimental tools see the same items; if
   yours is not, ask the user before creating it (it is a Steam directory).
2. **Link them into the experimental client directory**, not the stable one, with the same names or new ones:
   `ln -s .../workshop/content/221100/1559212036 "<library>/steamapps/common/DayZ Exp/@9dd22c91"`. Your own
   test mod gets a link there the same way.
3. **Build an experimental server tree** from the experimental server, and link the same mods into it:
   `make-server-tree.sh <tree> "$(find-dayzserver.sh -e)"`, then `@CF`, your mod and their `.bikey` files, and
   `BattlEye = 0;` in `serverDZ.cfg` (section 2).
4. **Pass `-e` to the client scripts**: `dayz-client-headless.sh -e start ...` or
   `dayz-client-test.sh -e -t <exp-tree> ...`. Without it they start the stable client against your
   experimental server, which `forceSameBuild = 1` should reject (expected, not run).
5. **Stable and experimental tests run one after the other**, never together (one game at a time).

What the experimental run showed **(tested)**: the same `AutoTest` PBO, built once, passed unchanged on
1.30.164014.27 (`DAYZ_1_30` define active) together with the stable Workshop's CF, with `DONE passed=2
failed=0` and no `NULL pointer` or crash log on the client. Test every change on both while 1.30 is on experimental (`SKILL.md`, dual targeting).
Mods that are not written for 1.30 can still fail on it; that is exactly what this run is for.

## 3. Tests that run on both sides and report back

Starting the client and seeing it connect proves very little. The useful part is code that runs **on
the client** and **on the server** in a known order and reports a result you can grep. The
approach below (RPC-driven tests) is implemented in `testing/autotest-mod/` and ran green. **(tested)**

### Design

```
 server (drives)                              client (executes)
 -----------------                            -----------------
 wait until the player is connected
 test N: ServerSetup(player)   (create item, set state, call the code under test)
 RPC AUTOTEST_RPC_RUN(name) ----------------> ClientCheck()  (retry up to 5 s while it returns false)
                              <--------------  RPC AUTOTEST_RPC_RESULT(name, passed, message)
 Print("[AUTOTEST] PASS|FAIL name message")
 test N+1 ...
 Print("[AUTOTEST] DONE passed=P failed=F")   <- the line an outside script waits for
```

Why it is built this way:

- **The server is the only driver.** Both sides already have the same test list because the same PBO is
  loaded on both, so only the test *name* crosses the wire. No ordering races, no two timers to align.
- **One RPC out, one RPC back, per test.** The server does not start test N+1 until it has the answer to
  N, or a 20 s timeout turns the silence into a `FAIL ... no answer from the client`. A client that
  crashed or never joined therefore fails the run instead of hanging it.
- **Client checks retry.** Server-side changes (inventory, state) take a moment to replicate. A check that
  returns `false` is repeated every 500 ms for up to 5 s, which turns "sync lag" from a flaky test into a
  non-event, and still fails if the state never arrives.
- **Results go to the server's script log.** The test runner then only has to read one file
  (`profiles/script_*.log`) for `[AUTOTEST]` lines; the client prints `[AUTOTEST-CLIENT]` lines to its
  own log for debugging.

### Adding a test

Everything is in `testing/autotest-mod/src/AutoTest/scripts/4_World/AutoTestCases.c`. A test is a class
(the two real ones in that file ran; this `FNX45` one is an illustrative sketch, not run):

```c
class MyModTestPistolReloads : AutoTestCase
{
	override string Name() { return "pistol_reloads"; }

	override void ServerSetup(PlayerBase player)        // runs on the server first
	{
		player.GetHumanInventory().CreateInHands("FNX45");
	}

	override bool ClientCheck(out string msg)           // then on the client
	{
		PlayerBase p = PlayerBase.Cast(GetGame().GetPlayer());
		if (!p || !p.GetHumanInventory().GetEntityInHands())
		{
			msg = "pistol not in hands yet";
			return false;                               // retried, then FAIL with this msg
		}
		msg = "pistol in hands";
		return true;
	}
}
```

Register it in `AutoTestRegistry.All()` (order = run order). Both sides compile the class, so you may
reference `PlayerBase` and every other `4_World` class from either half.

To test **your** mod: copy the `AutoTest` addon into a separate test mod (`@MyMod_Test`) that depends on
yours, instead of putting test code in the shipped mod. Load it with `-mod=` on server **and** client, and
leave it out of the release build. Then production players never get the harness or its RPC ids.
The mod name also becomes a script define (`#ifdef AutoTest` is true when the mod is loaded, visible in the
`Module: ...; defines:` log line), so shared code can switch on it. **(tested)**

### Pitfalls found while building it

- **Do not `foreach` directly over a function's return value**, such as `foreach (T t : Registry.All())`.
  On the client that registry lookup worked once and then threw `NULL pointer to instance` on the second
  call, so the second test reported `unknown test`. Assigning the result to a local and indexing it
  (`array<ref T> all = Registry.All(); for (...) all.Get(i)`) fixed it. **(tested, 1.29)**
- **Pick RPC ids no other mod uses.** The example uses 74010 and 74011; there is no registry.
- **The runner starts 20 s after `InvokeOnConnect`** because the client is still loading. Too short and
  `client_has_player` fails; the retry loop absorbs small differences. A "ready" RPC from the client
  would be more exact, but was not needed.
- A test that needs several players needs several clients; this setup runs one.

## 4. One command: start, wait, report, stop

`scripts/dayz-client-test.sh` does the whole cycle: free ports, server, headless client, waiting for the
`DONE` line, collecting the `[AUTOTEST]` lines, a final screenshot, and teardown. **(tested)**

```sh
"${CLAUDE_SKILL_DIR}/scripts/dayz-client-test.sh" -t "$TREE" -s "@AutoTest" -c "@AutoTest" -o /tmp/run1
# [AUTOTEST] PASS client_has_player local player SurvivorM_Rolf
# [AUTOTEST] PASS server_item_synced Chemlight_Red replicated to the client
# [AUTOTEST] DONE passed=2 failed=0
# artifacts: /tmp/run1 (server.log, final.png; server script log: ...)
```

Exit status 0 means `DONE` was seen and there was no `FAIL`; 1 means a failure or a timeout (default 300 s;
a cold client start takes about 60 s on its own). On timeout it saves `timeout.png`.

Build and sign the example first: `dayz-mod-pack.sh -C testing/autotest-mod keygen` (once), then `build`.
Link `build/@AutoTest` and the `keys/AutoTest.bikey` into the server tree, and `build/@AutoTest` into the
client directory. The mod is an example: do not install its key on a real server.

## 5. Reading what the client did

- **Client script log:** `<compatdata>/<221100 or 1024020>/pfx/drive_c/users/steamuser/AppData/Local/<DayZ or DayZ Exp>/script_<date>.log`,
  with the newest file being the current run. This is the same kind of log as the server's: compile errors
  `SCRIPT (E)`, `Print` output, `NULL pointer` stack traces. **(tested)**
- **`crash_<date>.log`** next to it holds the script exception text of a client-side script error
  with its stack trace. Example from this run: DayZ-Editor's `EditorVersionCallback.OnSuccess` threw
  `NULL pointer to instance` in a sandbox without web access. A mod can therefore be checked on the client for
  script exceptions without looking at the screen. **(tested)**
- **Screenshots** (`shot`) show what a player would see; useful for "is the HUD there", not for pixel asserts.
- The server's admin log (`profiles/*.ADM`) has `Player "<name>" is connecting` / `is connected` lines and the
  spawn position, a reliable signal that the join worked. **(tested)**

## 6. Process and path gotchas

- The game's main thread is called `enfMain` in `ps` (like the server), not `DayZ_x64.exe`; look it up
  through the sway window (`swaymsg -t get_tree`, field `pid`) or just `stop` the session. **(tested)**
- A mod-tree path that is too long breaks the server's persistence:
  `File path exceeds max filename length. (291 > 280)`, and `spawnpoints.bin` is not written. Keep the server
  tree in a short directory (`/tmp/dzt`), not under a deep project path. **(tested)**
- `pkill -f DayZ_x64.exe` kills the shell running it, same as with the server (it did, exit 144). Use PIDs
  or `stop`. **(tested)**
- Other DayZ servers on the machine are not yours; check `ps` args before stopping anything by name.

## Not covered

- **gamescope and Xvfb** are installable but were not evaluated; sway headless worked first time. Xvfb has
  no GPU/DRI3 path, so Vulkan (DXVK) presentation is a doubt.
- **Input injection** (mouse/keyboard into the game) was not tried. `-connect` makes it unnecessary for joining.
- **BattlEye-enabled servers**, multiple clients, Windows and macOS were not run.
