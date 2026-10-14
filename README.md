Nightfall Holdout
=================

A top-down zombie survival game made in Godot 4.
Survival like Project Zomboid (hunger, scavenging, noise attracts zombies),
combat like V Rising (mouse aim, melee arcs, dodge roll, cooldown ability).

Version 0.1 - single player, survive day and night.


How to run
----------
1. Install Godot 4.3 or newer (standard version, not .NET).
   On Pop!_OS: download from godotengine.org, or `flatpak install flathub org.godotengine.Godot`
2. Open Godot, click Import, pick the project.godot file in this folder.
3. Press F5 (or the play button) to play.


Controls
--------
WASD          move
Mouse         aim
Left click    shoot (loud - zombies come to the noise)
Right click   melee swing (quiet, no ammo)
Space         dodge roll (you cannot be hit while rolling)
Q             shockwave (knocks back everything near you, 8s cooldown)
R             reload
E             search a crate
F             eat food
Enter         restart after dying


How it plays
------------
Day (90s):   scavenge crates for ammo, food and medkits. Zombies wander slowly.
Night (60s): it gets dark, zombies see further, and a horde spawns and hunts you.
Each new day the zombies get tougher and the horde gets bigger.
Hunger drains over time. At 0 you lose health. Keep it above 60 to slowly heal.


Running the tests
-----------------
From this folder:

    godot --headless --path . -s res://tests/test_runner.gd

It prints PASS/FAIL for each check and exits with code 0 if all pass.


Project layout
--------------
scenes/main.tscn        the only scene, everything else is built from code
scripts/main.gd         map, day/night cycle, spawning, noise
scripts/player.gd       movement, shooting, melee, dodge, hunger
scripts/zombie.gd       wander / investigate / chase behaviour
scripts/bullet.gd       bullets (ray-based hit detection)
scripts/loot_crate.gd   searchable crates
scripts/hud.gd          on-screen info
tests/test_runner.gd    automated tests


Planned next steps
------------------
1. Base building: place walls, doors and barricades on a grid
2. Resource gathering and crafting (wood, scrap, a workbench)
3. Zombies attacking walls at night
4. Online co-op (one player hosts, friends join)
