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
- **Heat Accumulation Physics:** Fire spread operates via deterministic thermodynamics rather than stochastic probability. Cells dynamically accumulate radiant heat from burning neighbors. The simulation parameters (ignition thresholds, radiative heat transfer rates, and environmental cooling factors) have been rigorously tuned to mirror the aggressive spread velocities observed in real-world satellite telemetry.
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
- **Volumetric Lightning:** During heavy storms, procedural volumetric lightning strikes occur using `Path3D` and `CSGPolygon3D` meshes, generating dynamic light flashes.
- **Day/Night Cycle:** Fully dynamic sky shader updates. The system modulates sun and moon rotation, color temperature, and light energy based on the time of day. Clouds naturally block starlight and dim ambient light.

### 4. Terrain & Grass Generation
**Files:** `terrain_generator.gd`, `grass_manager.gd`, `terrain.gdshader`

- **Chunked Terrain:** The monolithic 4km PlaneMesh is subdivided into 64 chunks (8x8 grid) on load. This is a critical optimization for Godot's frustum culling.
- **Shader Displacement:** Terrain height is evaluated via macro/micro noise in the vertex shader. Normals are calculated on the fly using central differencing.
- **Slope Texturing:** The fragment shader dynamically blends rock, dirt, and grass colors based on the normal's slope.
- **Dynamic Burn Maps:** The terrain shader reads the global fire simulation texture to organically overlay deep charcoal charring, ash patches (using multi-directional wave noise), and glowing embers (using low-frequency heat noise).
- **GPU Grass Placement:** 150,000 grass blades are instanced using `GPUParticles3D` and a custom process material. The grass follows the camera natively (world offset mapping in the shader) to simulate an infinite field with zero CPU cost.

### 5. Machine Learning Pipeline & Ground Truth Accuracy Testing
**Folder:** `/ml_pipeline/`

The project integrates a custom Python-based machine learning pipeline trained to predict fire spread dynamics using real-world satellite telemetry. By treating the Godot cellular automata simulation as the "Ground Truth" reality, the system continuously evaluates the AI model's predictive accuracy in real-time.

**Dataset & Academic Reference:**
The models are trained on the **Next Day Wildfire Spread Dataset** compiled by Google Research. 
> *Huot, F., et al. (2022). "Next Day Wildfire Spread: A Machine Learning Data Set to Predict Wildfire Spread from Remote-Sensing Data." IEEE Transactions on Geoscience and Remote Sensing.* 
> **Download / Source:** [Kaggle Dataset Link](https://www.kaggle.com/datasets/fantineh/next-day-wildfire-spread)

- **Real-Time Asynchronous Bridge:** A multithreaded Godot `WorkerThreadPool` task continuously downsamples the massive 2048x2048 physics texture into a localized 64x64 matrix. It isolates "at-risk" cells along the fire perimeter, translates simulation physics into real-world units (e.g., Celsius to Kelvin), and streams the matrix via HTTP POST to an asynchronous Python Flask server.
- **Model Tuning & Thresholding:** Real-world wildfire satellite data suffers from extreme class imbalance (the vast majority of historical data represents unburned forest). To counteract the model's resultant conservative bias, the Random Forest Classifier utilizes a custom `>15%` probability threshold, allowing it to aggressively and accurately flag high-risk coordinates.
- **Dynamic Accuracy Tracking (True Positives):** Godot extracts the spatial coordinates of every tree the ML model predicts will burn and stores them in a mathematical Set. On every frame, the physics engine cross-references this set against the active simulation. This creates a live, console-based dashboard grading the ML model's True Positive accuracy against the deterministic physical simulation.

## 🚀 Advanced Optimization Techniques

- **MultiMeshInstance3D Chunking:** The 450k trees are batched into chunks of 250m. This allows the engine to efficiently cull entire forests behind the camera.
- **Billboard LODs (Level of Detail):** Close trees are rendered as full 3D meshes. Trees beyond a visibility threshold are replaced by massive `MultiMeshInstance3D` batches of 2D camera-facing quads (Billboards). This saves millions of polygons per frame.
- **World Offset Particles:** Fire and ember `GPUParticles3D` have engine interpolation disabled. Their world coordinates are offset inside their process shaders based on camera position. This ensures smooth particle rendering independent of camera velocity.
- **Custom Collision Heightmaps:** The terrain script manually calculates a `HeightMapShape3D` corresponding to the shader's macro noise, enabling fast and accurate physics collisions without relying on complex mesh collisions.
- **Threaded Texture Reads:** Reading pixels from a viewport texture is a heavy operation. The `FireManager` performs tree damage assessments entirely on background tasks using `WorkerThreadPool.add_task()`.
- **Initialization Orchestration:** Game launch dynamically suspends all environment nodes (`PROCESS_MODE_DISABLED`), utilizing a seamless UI loader while the `WorkerThreadPool` scatters hundreds of thousands of trees and generates the Fuel Map, ensuring uninterrupted execution.

## 🛠️ Installation & Setup

### Prerequisites
- **Godot Engine:** Version 4.x or higher.
- **Python:** Version 3.8+ (for the Machine Learning server).
- **Python Dependencies:** `flask`, `pandas`, `scikit-learn`, `numpy`.

### 1. Start the Machine Learning Server
To enable the AI prediction pipeline and accuracy grading, the Python inference server must be running in the background before launching the simulation.
```bash
cd ml_pipeline
pip install -r requirements.txt # Or install flask pandas scikit-learn numpy manually
python ml_server.py
```
*The server will start listening on `http://127.0.0.1:5000`.*

### 2. Run the Godot Simulation
1. Open the Godot 4 Project Manager and import the `forest-fire-simulation` folder.
2. Open the project.
3. Press `F5` (or click the Play button in the top right) to launch the main scene.
4. Ignite a fire using the interactive UI/tools provided in the simulation and observe the `[Accuracy Tester]` console logs as the AI grades its predictions against the physics engine.

## 📂 Project Structure

- `/scripts/` - Core logic for weather, fire, terrain generation, and the day/night cycle.
- `/resources/` - The complex custom `.gdshader` files powering the GPU logic.
- `/scenes/` - Main environment scenes and UI components.
- `/ml_pipeline/` - Python ML training scripts and serialized `.joblib` models (Random Forest, Logistic Regression) trained on real-world satellite fire data.

---
*Developed for Godot 4.x. Designed with a focus on bleeding-edge procedural rendering and GPU-accelerated computing.*
