# STAR REPLICA: AUTOMA

Web Play (GitHub Pages): https://wak-shogo.github.io/ReplicaAutomata-/

Zero-from-scratch Godot 4.7 rebuild based strictly on [docs/DESIGN_SPECIFICATION.md](docs/DESIGN_SPECIFICATION.md) and [docs/art/target_gameplay_concept.jpeg](docs/art/target_gameplay_concept.jpeg).

## Core Architecture
- **HD-2D Pixel Art & Spherical 10x Open-World Planet** (`scripts/world/planet_world.gd`, `tools/build_pixel_art_atlas.py`): Seamless toroidal sandstone regolith crust, volcanic basalt strata, carved subterranean crystal caverns, molten magma core, 3 orbiting moons (`LUNA-PRIME`, `IGNIS-IX`, `CRYO-IV`), and natural orbital asteroid belt.
- **Full Newtonian Gravity & Zero-Drag Keplerian Orbit** (`scripts/entities/player_vessel.gd`): Multi-body inverse-square space gravity + Shell Theorem interior gravity, atmospheric drag inside `R_ATMOS`, strictly zero drag in vacuum space, RCS attitude + axial rocket bell propulsion, Electric Ion anti-softlock backup, and emergency Capsule Re-Drop.
- **Vessel Evolution**: Starts as a minimal brushed-steel cylinder (`Seed Capsule`) and visibly bolts crafted modules via the Onboard 3D Printer (`Lander Mk-I` -> `Apollo Mk-II` -> `Warp Mk-III`) plus tethered Fabricator Drones.
- **Hard Local Wired Power Grid & Physical Logistics** (`scripts/factory/factory_sim.gd`): Solar Arrays, 18,000 kJ night-buffer Power Banks, Geothermal Plants, wired Power Cables to Tesla Coils, Mining Drills (buffer 6), animated Conveyor Belts & Lift Shafts, Cargo Depots with 4-way output filters, Blast Smelters, Auto Assemblers, Gantry Macro Printers, and 45-degree Orbital Mass Driver railguns.
- **10,000-Unit MultiMesh2D Swarm Fleet** (`scripts/entities/swarm_sim.gd`): GPU-instanced orbital swarm with `HARVEST / REPLICATE / DEFEND / ASSAULT` doctrines and the Corrupted Orbital Fortress boss.
- **AAA Minimalist Controls & Fighter-Jet HUD** (`scripts/ui/hud.gd`): Diegetic circular HP/Fuel/Ion arcs with velocity/altitude/power/G callouts, single virtual joystick + ABXY 2-click command menus, and Factorio-style Tech Tree DAG for both Desktop (`1280x720`) and Portrait Mobile (`412x915`).
- **Refined 16-bit 44.1kHz Procedural Audio** (`scripts/core/audio_synth.gd`): Warm harmonic sine/FM synthesis and low-pass filtered launch/explosion transients.

## Verification Commands
```powershell
& "H:\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe" --headless --run-tests
python -u tools/verify_game.py
```
