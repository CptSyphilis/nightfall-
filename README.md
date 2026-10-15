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
B                       D-pad right     D-pad right     build mode on / off
Enter                   A               Cross           restart after dying

In build mode:
Left click (hold)       RT (hold)       R2 (hold)       build (drag to draw walls)
Right click             Y               Triangle        demolish (half the cost back)
Wheel or 1-5            LB / RB         L1 / R1         choose piece

The game switches button prompts automatically to whatever you last touched.


Weapons
-------
Melee:  Fists, Club, Stone axe (double wood), Spear (long reach, narrow),
        Spiked club, Machete (double scrap)
Ranged: Pistol (loud, attracts zombies), Bow and Crossbow (quiet, use arrows)
Craft them in the character screen, then select one to equip it.


Building (Maul-style mazes)
---------------------------
Press B to build. A faint grid shows where pieces go; everything on the map
lines up with it. Pieces are paid from your inventory:
  Campfire      6 wood, 4 stone            starts the night; defend it (only one)
  Wood wall     2 wood                     cheap, good for mazes
  Stone wall    2 stone, 1 wood            tough
  Door          4 wood, 1 scrap            you walk through, zombies don't
  Spike trap    3 wood, 1 stone            hurts and slows zombies walking over it
  Arrow tower   10 wood, 6 stone, 3 scrap  shoots zombies by itself
Zombies always take the open route, so a long maze buys time for your towers.
If there is no route at all (you walled yourself in), they walk up to your
walls and smash through.


How it plays
------------
Day:   no zombies and no timer. Gather wood, stone and scrap, search crates
       (they vanish once searched), craft, and build your base.
       Build ONE campfire and use it (press twice) when you are ready.
Campfire: the heart of your base. Horde zombies head for it, Maul style.
       Each one that reaches it costs a life. 10 lives; at 0 you lose.
       You can move it by demolishing it during the day (full refund).
Workbench: crafting there can also use items from chests near it.
Night: it gets dark and the horde hunts you. 60 seconds on night 1,
       10 seconds longer each night (max 2 minutes).
Dawn:  the zombies are gone and a new day starts. They get tougher every night.
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
