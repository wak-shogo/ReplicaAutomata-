# STAR REPLICA: AUTOMA

A 2D HD-2D pixel-art Von Neumann self-replicating factory & orbital swarm game built in **Godot 4.7** (GL Compatibility / WebGL 2.0), rebuilt from the ground up from [`docs/DESIGN_SPECIFICATION.md`](docs/DESIGN_SPECIFICATION.md) and [`docs/art/target_gameplay_concept.jpeg`](docs/art/target_gameplay_concept.jpeg).

## Play Online
- **GitHub Pages**: https://wak-shogo.github.io/ReplicaAutomata-/

## Core Architecture
- **360-Degree Spherical Planet (`scripts/world/spherical_planet.gd`)**: Fine-grained `24px`-voxel terrain (`900 x 100`) rendered via 30 GPU-cached curved ring `MeshInstance2D` chunks (`120x400px` nearest-neighbor HD-2D texels), with undulating sandstone crust, organic subterranean crystal caverns, molten lava core, Shell-Theorem + inverse-square multi-body gravity, zero-drag vacuum Keplerian orbits, 3 orbiting moons (`LUNA-PRIME`, `IGNIS-IX`, `CRYO-IV`), and 140 harvestable asteroids.
- **Seed Unit + Physically Docking Fabricator Drones (`scripts/entities/seed_unit.gd`)**: Begin as an orbital Seed Core, dock up to 8 Fabricator Drones on articulated trusses for synchronized multi-beam mining, mount bolt-on propulsion tiers (`Seed Ion Hover` -> `Orbital Booster` -> `Deep Cryo Drive` -> `Swarm Flagship`), and rely on rechargeable Electric Ion hover + Emergency Re-Drop so you can never soft-lock.
- **Hard Local Wired Power & Connected Physical Logistics (`scripts/factory/industrial_grid.gd`)**: Solar Arrays, Geothermal Plants, and 18,000 kJ Night Power Banks must be physically wired to Tesla Relays to energize nearby machines. Mining Drills feed physical items onto Conveyor Belts / Lift Shafts -> 4-Way Filter Cargo Depots -> Blast Smelters -> Auto Assemblers -> Gantry Macro 3D Printers -> 45-degree Mass Drivers.
- **10,000-Unit GPU Swarm & Corrupted Orbital Fortress (`scripts/entities/orbital_swarm.gd`)**: `MultiMeshInstance2D` renders up to 10,000 golden replica probes launching from Mass Drivers and fighting the upper-sky Corrupted Orbital Fortress under 4 Fleet Doctrines (`HARVEST`, `REPLICATE`, `DEFEND`, `ASSAULT`).
- **Concept-Art Industrial HUD & Tech Tree (`scripts/ui/command_hud.gd`)**: Slim left resource/fleet sidebar, bottom pixel-art icon hotbar, right doctrine strip, bottom-right orbital telemetry & log, diegetic HP/Fuel/Ion arcs, Factorio-style 8-node Tech Tree DAG (`[T]`), Cargo Depot 4-way filter UI, and mobile/touch-only virtual controls.

## Controls
- **Move / Thrust**: `WASD` or Arrow Keys (`Shift` / Right-Click to Brake)
- **Mine / Place / Wire / Tap Building**: Left-Click (`Space` to Mine, `E` to interact with nearby Depot/Machine)
- **Rotate Belt**: `R` | **Tech Tree**: `T` | **Orbital View**: `M` | **Megastructures**: `G` | **Hotbar**: `1`-`7`

## Verification & Export
```powershell
# Headless integration tests
H:\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe --headless --run-tests

# Web export + COI shell injection
H:\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe --headless --export-release "Web" docs/index.html
python tools/inject_web_shell.py

# Live headless Chromium WebGL playtest (Desktop 1280x720 + Mobile Portrait 412x915)
python -u tools/playtest_v3.py
```
