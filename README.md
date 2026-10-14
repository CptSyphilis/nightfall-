Nightfall Holdout
=================

A top-down zombie survival game made in Godot 4.
Survival like Project Zomboid (hunger, scavenging, noise attracts zombies),
combat like V Rising (mouse aim, melee arcs, dodge roll, cooldown ability).

Single player. Gather, craft, build, and survive the night hordes.


Play in the browser
-------------------
https://cptsyphilis.github.io/nightfall-/
(needs keyboard and mouse; the build lives on the gh-pages branch)


How to run
----------
1. Install Godot 4.3 or newer (standard version, not .NET).
   On Pop!_OS: download from godotengine.org, or `flatpak install flathub org.godotengine.Godot`
2. Open Godot, click Import, pick the project.godot file in this folder.
3. Press F5 (or the play button) to play.


Controls
--------
Keyboard + mouse        Xbox            PlayStation     Action
WASD                    Left stick      Left stick      move
Mouse                   Right stick     Right stick     aim
Left click              RT              R2              ranged weapon
Right click             RB              R1              melee weapon / gather
Space                   A               Cross           dodge roll (no damage while rolling)
Q                       LB              L1              shockwave (8s cooldown)
R                       Y               Triangle        reload
E                       X               Square          search crate / open chest / workbench
F                       D-pad up        D-pad up        eat
H                       D-pad down      D-pad down      heal (bandage, then medkit)
Tab or I                Menu            Options         character screen
Esc                     B               Circle          close menu / cancel placing
Enter                   A               Cross           restart after dying

The game switches button prompts automatically to whatever you last touched.


Weapons
-------
Melee:  Fists, Club, Stone axe (double wood), Spear (long reach, narrow),
        Spiked club, Machete (double scrap)
Ranged: Pistol (loud, attracts zombies), Bow and Crossbow (quiet, use arrows)
Craft them in the character screen, then select one to equip it.


How it plays
------------
Day (90s):   gather wood, stone and scrap, search crates, craft and build.
             Zombies wander slowly.
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
