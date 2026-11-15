# Orbit Architect

A 2D orbital-mechanics and spacecraft-engineering game built for the NASA
International Space Apps Challenge 2026.

Design a vehicle, plan the burns, fly the mission. A campaign of 5 missions exists, maybe more in the future

It was built using Godot 4.7 using GDScript, desktop first, mobile may come later.

## Controls

| Action | Input |
| --- | --- |
| Pan the map | drag with mouse / touch |
| Zoom | mouse wheel |
| Pause / resume | `Space` or `PAUSE` |
| Advance time | warp buttons `1x … 10Mx`, `+1 H`, or `1–8` |
| Warp step up/down | `+` / `-` |
| Plan a burn | `PROGRADE` / `RADIAL` fields or sliders, then `EXECUTE BURN` / `Enter` |
| Auto-plan capture | `AUTO-PLAN CAPTURE` or `A` |
| Rewind | `REWIND` or `R` |
| Transmit science | `TRANSMIT SCIENCE` or `T` |
| Buy a hint | `SOLVE -5` or `H` |
| Cycle free hints | `NEXT >` or `N` |
| Scan flyby windows | `SCAN` or `G` |
| Solve a flyby burn | `SOLVE BURN` or `F` |
| Focus a body | `EARTH` / `MOON` / `SHIP` / `SYSTEM` |
| Save a blueprint | `Ctrl+S` in the hangar |
| Back out of a screen | `ESC` |

## Campaign

| # | Mission | Target | Core objective |
| --- | --- | --- | --- |
| 1 | Lunar Relay | Moon | Trans-lunar injection, bound lunar orbit, relay science |
| 2 | Jezero Descent | Mars | Escape Earth, reach Mars, survive atmospheric entry |
| 3 | Metal World | 16 Psyche | Leave Earth, reach the asteroid, survey it |
| 4 | Europa Clipper | Jupiter / Europa | Jupiter arrival and Europa flyby |
| 5 | Outer Grand Tour | Saturn | Reach the outer solar system and close the tour |

The campaign ends with a completion banner and a direct link to the credits.
Each mission also carries a short **field note** explaining the real science
behind the target.

A hidden **Landing Drill** is used by Flight School. It starts 2 km above the
Moon with zero horizontal velocity, teaching the final braking burn and a soft
touchdown under 40 m/s.

## The flight model

- **Restricted N-body.** The spacecraft is integrated through the summed gravity
  of all twelve real bodies. The bodies themselves are not integrated: they
  follow analytic Keplerian ephemerides (JPL *Approximate Positions of the
  Planets*, Standish & Williams) sampled once per mission into interpolation
  tables (Moon 900 s, Earth 1800 s, planets 3600 s, Sun 7200 s). Tables use
  cubic Hermite interpolation, so positions and velocities stay smooth without
  recomputing elements every frame.
- **RK4 with adaptive steps** (`core/propagator.gd`): 10 s near Earth/Moon,
  30 s in the mid field, 60 s far out. Near a target surface the step shrinks to
  as little as 0.2 s so a landing cannot skip through the ground between
  integration steps.
- **Impulsive burns** with Tsiolkovsky mass loss (`Δv = Isp · g₀ · ln(m₀/m₁)`),
  so propellant, dry mass, and engine choice genuinely decide the mission.

### Lunar reference solution

| Step | Value |
| --- | --- |
| Build | `core_bus, tank_large, engine_chem, solar_wing, dish_hga, sci_relay, structure_ring` |
| Wet mass / Δv | 1,525 kg / 4,706 m/s (7 of 13 slots, ≈ $22.8M) |
| Trans-lunar injection | +3,170 m/s prograde at t = 0 |
| Coast | lunar approach around T+2d 16h |
| Lunar orbit insertion | ≈ −715 m/s retrograde at closest approach (AUTO-PLAN) |
| Result | all three objectives, ≈ 821 m/s remaining, 87/100 Silver |

A 3,150 m/s injection for the Moon has a narrow window. The
trajectory preview is produced by the same integrator and force model that
flies the ship. `Sim.predict_preview` uses a step sized from the local orbital
timescale instead of a fixed step, and stops after one closed loop when the
craft is still bound to a body. The baseline path is cached while the sim is
paused, and only the planned path is recomputed while a burn slider moves.

**Precision.** Position, velocity, the integrator and the ephemeris tables are
64-bit (`float`/`PackedFloat64Array`); `Vector2` is 32-bit and only appears at
the drawing/UI boundary. `CraftState.px/py/vx/vy` hold the truth and
`pos`/`vel` are 32-bit views.

### Landing drill reference

| Step | Value |
| --- | --- |
| Start | 2 km above the Moon, zero horizontal velocity |
| Free fall | warp until surface altitude is under 1 km |
| Final brake | brake all relative velocity around 0.3–0.5 km |
| Touchdown | ≈ 34 m/s, all objectives complete, 82/100 |
| Report | no credit payout for practice missions |

## Sandbox and contracts

The contract board is the repeatable side of the game.

- Three offers at a time, tiers 1–3, with expiry days, advances, rewards and
  reputation.
- Objective templates: **orbit**, **survey** (flyby + transmit), and **land**.
- **Free Build** lets you choose the destination: any real planet or moon, plus
  four extra procedural bodies. Extra bodies use stable serials `90001–90004`
  and are deterministic across sessions.
- Accepting a contract pays the advance up front; completion pays the rest based
  on score, and failure costs reputation.
- Contract-generated bodies are deterministic from their serial and are
  registered automatically when the board or a save needs them.

## Mission Builder and sharing

The Mission Builder creates ordinary playable missions:

- Name, target, objective (`ORBIT`, `FLYBY`, `LANDING`), budget and mass cap.
- Duration scales with target distance.
- Saved missions appear in the builder library with **OPEN**, **CODE** and
  **DELETE**.
- Deleting a mission also deletes its saved design, layout and completion entry.

Sharing is offline: a mission becomes `OA1-` followed by base64 JSON containing
name, target, objective, budget and mass. Import validates the base64/JSON, the
target, positive budget and mass, and the objective type. It always creates a
new local copy with a new `custom_N` id. Procedural targets are regenerated from
their serial if the receiving save does not already have that body.

## Blueprint Library

Blueprints are the per-mission saved designs. The library shows part count,
cost, wet mass and delta-v, and can reopen the original mission hangar. Designs
from expired contracts can be opened as sandbox copies.

## Flight School

Flight School is a data-driven overlay in `data/tutorial.json`. Steps can target
a screen, a specific mission and a UI node. They advance when the actual game
state satisfies the step, not on a timer: burn executed, time passed, orbit
bound, science transmitted, landing complete.

The full lesson is 14 steps:

1. Reference vehicle and launch
2. Trans-lunar injection
3. Time warp and coast
4. Capture at closest approach
5. Buying a hint
6. Circularization
7. Rewind
8. Science transmission
9. Filing the report
10. Landing practice prompt
11. Landing drill build
12. Free fall
13. Final brake
14. Landing report

Tutorial progress persists in the save.

## Content is data, not code

| File | Contents |
| --- | --- |
| `data/bodies.json` | 12 real bodies: μ, radii, SOI, scale height, J2000 elements + rates |
| `data/parts.json` | 15 parts: mass, cost, power, slots, tankage, Isp/thrust, comms/science tags |
| `data/missions.json` | 5 campaign missions + hidden landing drill; goals are data-driven |
| `data/achievements.json` | 25 milestone definitions |
| `data/tutorial.json` | Flight School steps (screen, mission, node, copy, completion condition) |
| `data/voice_lines.json` | voice cue metadata |
| `locale/languages.json` | language manifest |
| `locale/me.json` | Montenegrin strings |

**Assembling.** The bay is a paint canvas: a 17×13 grid of 16 px tiles over a
pixel-art plate (`assets/art/generated/bay_bg.png`, regenerated with
`node tools/make_bay_bg.js`). Part art is drawn edge to edge.

- Click a part in the catalogue to pick it up, then click or drag on the grid.
- **R** rotates the part in hand in 90° steps; rotation is saved and shown in flight.
- Right-click erases; clicking an installed part with an empty hand picks it up.
- `Hull Panel` is a 4 kg structural tile: cheap blocks that connect parts.

Three rules are enforced: exactly one command core, every part reachable from
the core through face-adjacent tiles, and the engine touching a propellant
tank. The flight view draws the same layout part by part, at each part's cell
and rotation, so the thing you built is the thing that flies. Cells and
rotations are saved as `[x, y, rot]` triples in `campaign.json`.

## Localization and accessibility

- English and Montenegrin ship as separate JSON files behind a manifest.
- `Localization.t()` translates keys, `translate_any()` performs reverse lookup,
  and `apply_tree()` walks the UI.
- The logo is marked `no_translate` and has Godot auto-translation disabled, so
  the brand stays **ORBIT ARCHITECT** in every language.
- Subtitles are a Settings toggle, default off, and use the English voice cue
  text.
- Settings also expose reduced motion, scanline toggle, fullscreen, volume
  buses and background speed.

## Save data

- `user://campaign.json` — campaign progress, designs, layouts, custom missions,
  achievements, settings, flight snapshot.
- `user://campaign.bak.json` — previous save, written before replacement.
- Writes are atomic: temp file, then rename.
- `SAVE_VERSION` and migrations handle older saves.
- Flight autosaves every 8 seconds; exiting the sim saves immediately.
- Resuming a flight restores the exact mission, design, orbit, burns and
  objectives.

## Project layout

```
main.tscn / main.gd          app shell: routing, ESC, toast, tutorial host
scenes/*.tscn                real scenes (home, menu, contracts, blueprints,
                             builder, briefing, hangar, sim, debrief, credits,
                             achievements, tutorial)
scenes/components/*.tscn     reusable rows/cards instantiated from data
ui/*.gd                      screen behaviour; ui/world_view.gd draws the map
core/                        ephemeris, universe, propagator, craft/part/mission
                             defs, sim, contract generation
autoload/                    GameData (JSON), GameState (save), Localization,
                             EventBus, Audio, Art
data/                        all gameplay content
data/si_disclosure.json      machine-readable SI/AI disclosure
SI_DISCLOSURE.md             SI/AI disclosure and Space Apps form selection
locale/                      language manifest + per-language JSON
assets/art/                  art_manifest.json + generated art
tools/                       screenshot tool and asset generators
```

## Data sources and credits

- Orbital elements and rates: JPL Solar System Dynamics, *Approximate Positions
  of the Planets* (Standish & Williams), J2000 mean ecliptic.
- μ, radii, masses: NASA NSSDCA Planetary Fact Sheet.
- Mission parameters (Δv budgets, masses, budgets) tuned against NASA Artemis,
  Mars 2020, Psyche, Europa Clipper and Voyager fact sheets.
- Music: “Light Years” and “Cold Moon” by Eric Matyas, soundimage.org, free to
  use with in-game attribution.
- Interface and sci-fi sounds: Kenney, CC0 1.0.
- Voice lines: AI-generated with Fish Audio S2.1 Pro Free; disclosed in the
  in-game credits and tagged in the MP3 metadata.
- Code and text: assisted by AI primarily for physics, but also some debugging and etc
- Images and video: no SI-generated assets. Pixel art, ship art
  and UI graphics were created for this project.
- Credits to deep-fold.itch.io/pixel-planet-generator for the awesome planets
- Full disclosure is in `SI_DISCLOSURE.md`
- Engine: Godot 4.7, MIT License. Typeface: Noto Sans, SIL Open Font License.

## NASA notice

Orbit Architect is an independent submission for the NASA International Space
Apps Challenge 2026. It is not affiliated with or endorsed by NASA. NASA and
mission names are used for educational context only.

## Intentional approximations

- **Earth is the Earth–Moon barycenter.** The visible Earth sits at the
  barycenter; the Moon is offset from the true geocenter by up to ~4,700 km.
- **The Moon uses geocentric mean elements**, not a full ELP/lunar theory.
- **Only the spacecraft is integrated.** Planets are on rails: no mutual
  perturbations, no n-body chaos. Gravity assists work geometrically, not
  dynamically.
- **Burn frames are local:** prograde/radial relative to the body with the
  strongest influence at the craft's position, applied instantly.
- **Planets are not to scale on the map**; distances and trajectories are.
- **No atmospheric drag, J2 oblateness or continuous thrust.** The ion drive is
  modelled through Isp and power draw, but burns are impulsive.
- **No launch-window planner UI.** Departure hints use a single combined
  prograde burn, and the player times the departure by warping in the parking
  orbit.
