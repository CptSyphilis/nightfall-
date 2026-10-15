# Nightfall Holdout

A top-down zombie survival game made in Godot 4.

Scavenge and build by day, defend your campfire through the night. Survival like
Project Zomboid (hunger, scavenging, noise draws zombies), combat like V Rising
(mouse aim, melee arcs, dodge roll, cooldown ability), and Maul-style maze building.

**[Play in the browser](https://cptsyphilis.github.io/nightfall-/)** (keyboard and mouse)

## How it plays

- **Day:** no zombies, no timer. Gather wood, stone and scrap, search crates,
  craft gear and build your base.
- **Campfire:** the heart of your base. Build one and use it when you're ready
  to start the night. Every zombie that reaches it costs a life; lose all 10 and
  it's game over. You can move it during the day by demolishing it (full refund).
- **Night:** it gets dark and the horde comes. Night 1 lasts 60 seconds, each night
  10 seconds longer (up to 2 minutes), and the zombies get tougher every night.
- **Hunger:** drains over time. At 0 you start losing health; keep it above 60 to
  slowly heal.
- **Noise:** gunshots carry far and pull zombies in. Bows and crossbows are quiet.

## Controls

| Action | Keyboard + mouse | Xbox | PlayStation |
| --- | --- | --- | --- |
| Move | WASD | Left stick | Left stick |
| Aim | Mouse | Right stick | Right stick |
| Ranged weapon | Left click | RT | R2 |
| Melee / gather | Right click | RB | R1 |
| Dodge roll | Space | A | Cross |
| Shockwave (8s cooldown) | Q | LB | L1 |
| Reload | R | Y | Triangle |
| Search / open chest / workbench | E | X | Square |
| Eat | F | D-pad up | D-pad up |
| Heal (bandage, then medkit) | H | D-pad down | D-pad down |
| Character screen | Tab or I | Menu | Options |
| Close menu / cancel | Esc | B | Circle |
| Build mode | B | D-pad right | D-pad right |

### In build mode

| Action | Keyboard + mouse | Xbox | PlayStation |
| --- | --- | --- | --- |
| Build (hold and drag for walls) | Left click | RT | R2 |
| Demolish (half the cost back) | Right click | Y | Triangle |
| Choose piece | Wheel or 1-5 | LB / RB | L1 / R1 |

Button prompts switch automatically to whatever you last touched.

## Weapons

Craft weapons in the character screen, then select one to equip it.

- **Melee:** Fists, Club, Stone axe, Spear (long reach, narrow), Spiked club, Machete.
  Each one gathers differently: the axe is best on trees, the spiked club on rocks
  and the machete on scrap. Better tools clear a pile faster and get more out of it.
- **Ranged:** Pistol (loud), Bow and Crossbow (quiet, use arrows).

Some recipes need a workbench nearby. Crafting at a workbench can also use items
from chests next to it.

## Building

Pieces snap to a grid and are paid for from your inventory.

| Piece | Cost | Notes |
| --- | --- | --- |
| Campfire | 6 wood, 4 stone | starts the night; defend it (only one) |
| Wood wall | 2 wood | cheap, good for mazes |
| Stone wall | 2 stone, 1 wood | tough |
| Door | 4 wood, 1 scrap | you walk through, zombies don't |
| Spike trap | 3 wood, 1 stone | hurts and slows zombies |
| Arrow tower | 10 wood, 6 stone, 3 scrap | shoots zombies by itself |
| Concrete floor | 1 concrete | walls and chests can go on top |

Zombies always take the open route, so a long maze buys time for your towers.
Wall yourself in completely and they'll smash through instead.

## Running it locally

1. Install [Godot 4.7](https://godotengine.org/download) or newer (standard
   version, not .NET), or `flatpak install flathub org.godotengine.Godot`.
2. In Godot, click **Import** and pick `project.godot` from this folder.
3. Press **F5** to play.
