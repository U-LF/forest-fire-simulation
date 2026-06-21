# Forest Fire Simulation (Godot 4)

A highly advanced, performant, and realistic forest fire simulation built in Godot 4. This project demonstrates procedural generation, GPU compute-based cellular automata, complex atmospheric weather systems, and massive-scale instancing with thousands of entities.

## 🌲 Overview

This project simulates a fully dynamic, procedural 4km x 4km forested environment with realistic fire propagation mechanics. Instead of relying on CPU-bound logic, the core fire simulation, grass placement, and atmospheric effects are offloaded to the GPU using custom shaders. This allows for over 450,000 trees, 150,000 grass instances, and tens of thousands of active fire and ember particles running smoothly at high framerates.

## ⚙️ Core Systems & Architecture

### 1. GPU Cellular Automata Fire Simulation
**Files:** `fire_manager.gd`, `fire_sim.gdshader`

The fire propagation logic is entirely GPU-driven using a cellular automata approach.
- **Ping-Pong Buffers:** Uses two `SubViewport` nodes set to `CLEAR_MODE_NEVER` and `use_hdr_2d = true` (16-bit float precision). They alternate updates frame-by-frame to accumulate simulation data continuously.
- **State Tracking:** The simulation texture encodes `Red=Fire`, `Green=Char`, `Blue=Fuel`, and `Alpha=Heat`.
- **Heat Accumulation Physics:** Fire spread is no longer based on random dice rolls. Cells physically accumulate radiant heat from burning neighbors, dynamically scaling against environmental cooling factors. A weak grass fire cools down too fast to easily ignite a massive tree.
- **Dynamic Fuel Maps:** The simulation reads a procedurally generated Fuel Map texture. Trees (1.0 fuel) radiate immense heat, while grass (0.4 fuel) burns weaker. Rocks and dirt (0.0 fuel) act as natural firebreaks.
- **Directional Wind Vectors:** Wind acts directionally via dot product calculations. Fire transfers heat exponentially faster downwind, creating realistic, jagged fire wedges, while severely struggling to burn upwind.
- **Environmental Factors:** Cooling is dynamically influenced by real-time Temperature, Relative Humidity, Wind Speed, and Moisture.
- **Absolute Dew Point Cutoffs:** A persistent moisture value protects terrain from igniting. If ambient humidity crosses extreme thresholds, the physical cooling rate prevents spontaneous ignition entirely.
- **Asynchronous Stats:** A `WorkerThreadPool` task asynchronously reads the texture data to count healthy, damaged, and burnt trees without stalling the main thread.

### 2. Procedural Forest Generation
**Files:** `forest_generator.gd`

Generates a massive, dense forest spanning the 4000x4000 terrain.
- **Multithreading:** Generation runs entirely on a background thread using `WorkerThreadPool`.
- **Procedural Fuel Map:** Simultaneously evaluates slopes, tree placements, and high-frequency "dirt noise" to paint a massive 2048x2048 Fuel Map Texture, injected directly into the fire shader.
- **Occupancy Grid & Proximity Checks:** Employs a highly optimized 1D byte array as an occupancy grid to ensure trees don't overlap, evaluating proximity instantly.
- **Biome Masking:** Utilizes `FastNoiseLite` to organically cut out sprawling meadows and dirt patches where trees will not spawn, creating natural firebreaks.
- **Spatial Indexing:** Organizes generated tree positions into a dictionary of `PackedVector3Array` chunks. This spatial hash allows the fire simulation to rapidly identify which trees are burning based on world coordinates.

### 3. Dynamic Weather & Atmosphere
**Files:** `weather_manager.gd`, `day_night_cycle.gd`

A continuous, deterministic, noise-driven weather system.
- **Simplex Noise Drivers:** Four separate 1D `FastNoiseLite` generators drive Temperature, Relative Humidity (RH), Wind Speed, and Rain intensity over time.
- **Continuous Wind Shifts:** A continuous vector rotation drives the `current_wind_dir` variable, shifting the direction of physical fire wedges organically over the simulation's lifespan.
- **Dynamic Moisture:** Moisture acts as a buffer. Heavy rain charges the moisture shield, while heat, low humidity, and wind evaporate it over time.
- **Volumetric Lightning:** During heavy storms, procedural volumetric lightning strikes occur using `Path3D` and `CSGPolygon3D` meshes, leaving behind dynamic light flashes.
- **Day/Night Cycle:** Fully dynamic sky shader updates. Modulates sun and moon rotation, color temperature, and light energy based on the time of day. Clouds naturally block starlight and dim ambient light.

### 4. Terrain & Grass Generation
**Files:** `terrain_generator.gd`, `grass_manager.gd`, `terrain.gdshader`

- **Chunked Terrain:** The monolithic 4km PlaneMesh is subdivided into 64 chunks (8x8 grid) on load. This is a critical optimization for Godot's frustum culling.
- **Shader Displacement:** Terrain height is evaluated via macro/micro noise in the vertex shader. Normals are calculated on the fly using central differencing.
- **Slope Texturing:** The fragment shader dynamically blends rock, dirt, and grass colors based on the normal's slope.
- **Dynamic Burn Maps:** The terrain shader reads the global fire simulation texture to organically overlay deep charcoal charring, ash patches (using multi-directional wave noise), and glowing embers (using low-frequency heat noise).
- **GPU Grass Placement:** 150,000 grass blades are instanced using `GPUParticles3D` and a custom process material. The grass follows the camera natively (world offset mapping in the shader) to simulate an infinite field with zero CPU cost.

## 🚀 Advanced Optimization Techniques

- **MultiMeshInstance3D Chunking:** The 450k trees are batched into chunks of 250m. This allows the engine to efficiently cull entire forests behind the camera.
- **Billboard LODs (Level of Detail):** Close trees are rendered as full 3D meshes. Trees beyond a visibility threshold are replaced by massive `MultiMeshInstance3D` batches of 2D camera-facing quads (Billboards). This saves millions of polygons per frame.
- **World Offset Particles:** Fire and ember `GPUParticles3D` have engine interpolation disabled. Their world coordinates are offset inside their process shaders based on camera position. This prevents the particles from "jumping" or lagging behind when the camera moves quickly.
- **Custom Collision Heightmaps:** The terrain script manually calculates a `HeightMapShape3D` corresponding to the shader's macro noise, enabling fast and accurate physics collisions without relying on complex mesh collisions.
- **Threaded Texture Reads:** Reading pixels from a viewport texture is a heavy operation. The `FireManager` performs tree damage assessments entirely on background tasks using `WorkerThreadPool.add_task()`.
- **Initialization Orchestration:** Game launch dynamically suspends all environment nodes (`PROCESS_MODE_DISABLED`), utilizing a seamless UI loader while the `WorkerThreadPool` scatters hundreds of thousands of trees and generates the Fuel Map, preventing engine lockup.

## 📂 Project Structure

- `/scripts/` - Core logic for weather, fire, terrain generation, and the day/night cycle.
- `/resources/` - The complex custom `.gdshader` files powering the GPU logic.
- `/scenes/` - Main environment scenes and UI components.

---
*Developed for Godot 4.x. Designed with a focus on bleeding-edge procedural rendering and GPU-accelerated computing.*
