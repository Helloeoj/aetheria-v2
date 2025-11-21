# World Chunk 0,0 Setup Guide (Godot 4)

This guide walks you through building the first world chunk (0,0) in Godot 4 with no prior Godot experience. It follows the previously agreed constants:

- **Tile size:** 32×32 pixels (keeps consistency with the earlier plan; if you switch to 64×64 later, update the TileMap cell size accordingly).
- **Chunk size:** 128×128 tiles (4,096×4,096 pixels).
- **Scene naming:** `WorldChunk_0_0.tscn` stored under `res://scenes/world/`.
- **Supporting folders:** `res://tilesets/` for art, `res://scripts/world/` for future chunk scripts.

## 1) Open the project and prepare folders

1. Launch **Godot 4**. In the Project Manager window, click **Import**.
2. In the file chooser, navigate to the repository folder, open `godot_client/`, select `project.godot`, and click **Open** → **Import & Edit**.
3. In the **FileSystem** panel (bottom-left by default):
   - Right-click anywhere in the panel → **New Folder** → enter `scenes` → **OK**.
   - Right-click `scenes` → **New Folder** → enter `world` → **OK**.
   - Right-click the root (empty space) → **New Folder** → enter `tilesets` → **OK**.
   - Right-click the root (empty space) → **New Folder** → enter `scripts` → **OK**.
   - Right-click `scripts` → **New Folder** → enter `world` → **OK**.

## 2) Create the main world chunk scene

1. Go to the top menu **Scene → New Scene**. A new empty scene opens.
2. In the Scene dock (top-left), click **2D Scene**. This adds a `Node2D` as the root.
3. With the root selected, press **F2** (or right-click → **Rename**) and name it **WorldChunk_0_0**.
4. Add a TileMap: click the **+** icon in the Scene dock → search for **TileMap** → select it → **Create**. Rename it to **Ground**.
5. Set the cell size to match the tile size:
   - Select the **Ground** TileMap.
   - In the **Inspector**, expand **TileMap > Cell**.
   - Set **Size X** to `32` and **Y** to `32`.
6. Save the scene: **Scene → Save** (or **Ctrl+S**). In the file dialog, browse to `res://scenes/world/`, set the name to `WorldChunk_0_0.tscn`, and click **Save**.

## 3) Add a tileset (import art or make a placeholder)

### Option A: import a free PNG tileset
1. Download any **32×32 top-down RPG tileset PNG** (search terms: "32x32 top-down RPG tileset" or "Kenney topdown tileset 32x32").
2. Copy the PNG into the project folder `godot_client/tilesets/`.
3. Back in Godot, the FileSystem panel will auto-refresh (or click **Scan** if needed). Confirm the PNG appears under `res://tilesets/`.

### Option B: create a quick placeholder inside Godot
1. In **FileSystem**, right-click `tilesets` → **New Resource**.
2. In the dialog, search for **Image** → select **Image** → click **Create**.
3. Name it `placeholder_tiles.png` (Godot will still let you save a PNG). In the save dialog, ensure the path is `res://tilesets/placeholder_tiles.png` → **Save**.
4. Double-click `placeholder_tiles.png` to open the Image Editor at the bottom.
5. In the Image Editor toolbar, set the **Width** to `32` and **Height** to `32`, then click **Resize**.
6. Click the **Fill** tool (paint bucket), choose a color (e.g., green for grass), and click inside the canvas. Use the **Brush** to draw simple variants (e.g., brown for dirt) by changing colors and painting different 32×32 areas. Save with **Ctrl+S**.

### Create a TileSet resource and slice the tiles
1. Select the **Ground** TileMap in the Scene dock.
2. In the **Inspector**, next to **Tile Set**, click the **[empty]** dropdown → **New TileSet**. A `TileSet` resource is created.
3. Click the new `TileSet` resource (it shows as `TileSet` in the Inspector) to open the **TileSet** panel at the bottom.
4. In the TileSet panel, click the **+** button → **Add Atlas Source**.
5. In the file picker, choose your tileset PNG (`res://tilesets/placeholder_tiles.png` or the imported one) → **Open**.
6. With the Atlas Source selected (it appears in the left list), set the region for slicing:
   - In the right Inspector for the Atlas Source, set **Texture Region Size** to **32** by **32**.
   - Set **Margins** and **Separation** to `0` unless your tileset has spacing.
7. Click **Create Tiles** (in the Atlas toolbar) → choose **Create tiles from region**. Godot auto-slices the texture into 32×32 tiles. You should now see each tile as a selectable entry in the TileSet panel.
8. Confirm the TileMap uses this TileSet: the **Ground** TileMap’s **Tile Set** property should display the new TileSet resource.

## 4) Paint the starter area (chunk 0,0)

1. Select the **Ground** TileMap.
2. Open the **Tile Palette** tab (bottom). You should see your sliced tiles.
3. To paint:
   - Left-click a tile in the palette to select it.
   - In the 2D viewport, left-click to paint or click-drag to fill areas.
   - Right-click to erase.
4. Navigation tips while painting:
   - **Mouse wheel** to zoom in/out; hold **Ctrl** while scrolling for finer steps.
   - Hold **Middle mouse button** (or press **Space** + drag) to pan the view.
   - Press **1** for Select mode, **2** for Paint mode, **3** for Erase mode.
5. Layout ideas for a quick showcase within the 128×128 tiles (remember chunk is 4,096 px wide/tall):
   - Fill most of the area with a grass tile.
   - Add a dirt or cobblestone path leading from the bottom edge to a central plaza.
   - Place a bordered square for a town plaza and a few water or stone tiles at an edge to hint at a river or walls.
   - Leave some open grass for future buildings or trees.
6. Use **Ctrl+Z** to undo and **Ctrl+Shift+Z** to redo. Save often with **Ctrl+S**.

## 5) Add a camera for screenshots

### Option A: add the camera inside `WorldChunk_0_0.tscn`
1. In the Scene dock, select the root **WorldChunk_0_0**.
2. Click the **+** icon → add **Camera2D** → **Create**.
3. With **Camera2D** selected, in the Inspector:
   - Check **Current** to make it the active camera.
   - Set **Zoom** to something like `Vector2(1, 1)` (1:1) or `Vector2(1.5, 1.5)` to show a wider view.
   - Optionally set **Limits** if you want to restrict camera movement to the chunk bounds (X: 0–4096, Y: 0–4096).
4. Position the camera in the 2D viewport by dragging the gizmo so it frames your town center.

### Option B: create a lightweight `Main.tscn` that instantiates the chunk
1. **Scene → New Scene** → **2D Scene** (root `Node2D`). Rename the root to **Main**.
2. With **Main** selected, click the **+** icon → **Instantiate Child Scene** → pick `res://scenes/world/WorldChunk_0_0.tscn` → **Open**.
3. Add a **Camera2D** as a child of **Main**. Set **Current** to true and adjust **Zoom** and position as above.
4. Save this scene as `res://scenes/Main.tscn` (create the `scenes` folder first if it does not already exist).

## 6) Run and capture a screenshot

1. Set the main scene to run: top menu **Project → Project Settings** → **Application > Run** → set **Main Scene** to `res://scenes/Main.tscn` (or `WorldChunk_0_0.tscn` if you added the camera there) → **Close**.
2. Click the **Play** button (clapperboard icon) in the top-right, or press **F5**. The game window should show your painted map.
3. Take a screenshot:
   - On Windows: press **Win+Shift+S**, drag to select the game window.
   - On macOS: press **Shift+Cmd+4** and select the window.
   - On Linux (GNOME/KDE): use **Print Screen** or your screenshot tool. Ensure the Godot game window is in view.
4. If the view is too zoomed-in or out, close the running game, adjust the Camera2D **Zoom** or position, save, and run again.

You now have a saved `WorldChunk_0_0` scene with a TileMap using 32×32 tiles, painted starter content, and a camera that can be used for quick screenshots.
