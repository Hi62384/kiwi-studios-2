# Natural Materials and shader library

## Painting

Brush and Bucket have independent **Color / Material** modes beside their color controls. In Material mode, click the material swatch to open the shared dock. **Browse** searches the catalog; **Settings** edits the active material while the canvas remains visible. Texture Size controls the pattern independently of Brush Size. Emboss uses the material's structural height and its lighting direction.

The existing brush preset row stores both color and material brushes. Selecting a preset changes the painting mode automatically. The All / Color / Material filter, Save, Save as New, and the preset context menu manage the same persistent collection. Changing the active brush does not silently rewrite a saved preset.

Enable **Live Edit**, then use **+ New** in the third toolbar row. Each live template has its own stable ID, settings and painted coverage. Changing its material updates all its regions without repainting. Templates with identical material names remain independent. The template context menu offers naming, duplication and visibility. Delete removes only that template's unbaked regions and supports undo. Bake converts only the chosen template's regions into raster content in their original painting order. Show a hidden template before baking it.

With Live Edit disabled, material strokes and fills become ordinary raster artwork. Repair remains its own tool. Existing solid-color brush, bucket tolerance, selections, Stroke Correct and layer operations use their existing paths.

Stamp and scatter painting use the same material engine. Each live region keeps its coordinate map separately from coverage, so later material edits preserve stamp placement. Coordinate maps are cropped on commit and capped at 2048 pixels per dimension; coverage remains at document resolution.

## Scene materials

Choose **Natural Material** in a compatible general surface-material selector. The shared browser exposes the same material definitions, structural settings and saved presets as the Image Workspace. Material objects remain part of the existing actor object/reference system, including local, linked and file-backed resources. Use **Make Unique** before editing an independent copy of a linked resource.

Scene materials support albedo, roughness, metallic response, height-derived surface normals, UV scale/rotation and procedural triplanar projection. Imported images and the advanced secondary-material mixer use UVs. Fog, sky and camera-effect slots retain their specialized shader restrictions.

## Shader samples and templates

The existing shader documentation popup now contains Documentation, Shader Samples and Shader Templates. Search covers names, descriptions, categories and tags. Type filters, favorites and recents narrow the catalog. The library contains 142 samples and 20 templates, each with complete source and target/context information.

Cards are rendered from their actual shader. A single thumbnail renderer generates cached stills lazily; only the selected large preview animates. Its geometry, orbit, zoom and applicable uniforms are temporary preview controls. Compiler failures and unsupported render contexts display an explanation.

Copy Code copies the complete source. Open in Editor opens a copy without replacing an unsaved shader. Create Shader File saves a new resource and protects library originals. Apply to Selected Actor validates the target shader context, requests confirmation before replacing an existing material and records an undoable change. Particle process shaders can be previewed, copied, opened and saved; current actor definitions do not expose a particle process-material slot for direct Apply. Fog previews require Godot's Forward+ renderer.

## Architecture

`scripts/materials/natural_material_definitions.gd` owns stable IDs, defaults, versions and concise parameter schemas for ten families: Metal, Wood, Fabric, Stone, Ground, Organic, Weathering, Illustration, Geometry and Noise. All 143 existing IDs are retained.

`natural_material_pattern.gdshaderinc` is the single procedural structure evaluator. It produces directional grain and knots, brushed scratches and dents, woven and knitted yarn, mineral cells and veins, pores and masonry, blades/clumps/dunes/gravel, organic structures, weathering, illustration marks, geometry and generic noise. `natural_material_shader_source.gd` specializes this evaluator before compilation, removing unused families and mixers. A preloaded ShaderInclude keeps the source available in exported applications.

`natural_material_engine.gd` adapts the same structure and settings to 3D surfaces and requested albedo/height/normal/roughness/metallic maps. The existing texture-material renderer provides the canvas adapter. Seeds are deterministic; texture scale and mapping are separate from brush coverage. Structural height drives both 2D emboss and 3D detail. Compiled shaders and generated maps use bounded caches. `natural_material_presets.gd` persists shared presets as independent resource copies.

`live_material_template.gd` stores a document-local definition. `live_paint_region.gd` stores explicit ownership, mapping and coverage within an ordered layer stack. Ordinary raster segments and live regions preserve interleaved painting order. Layer/document serialization stores masks losslessly. Snapshots copy editable metadata while sharing immutable texture data; editing a coverage mask creates or updates the owned stroke texture, not other history states.

The image renderer caches unchanged layer targets and updates affected dependencies. Interactive previews follow zoom tiers and cap source dimensions at 2048 pixels during gestures. High-zoom views refine after 350 ms idle. Camera compensation preserves placement and texture scale. Bucket region detection uses an isolated native-resolution render; masks, document saving, export and baking retain native resolution. Very large documents and many interleaved regions still require substantial GPU memory.

The shader catalog's authoring inputs are `Workspaces/ShaderWorkspace/library/catalog.json` and the standalone `.gdshader` files. The generated `shader_library_data.gd` embeds their exact source strings and metadata for export-safe lazy loading. After changing a shader, update its SHA-256 manifest entry and run `python scripts/tests/rebuild_shader_library_index.py --write`. Running that script without `--write` verifies the index and hashes.

## Verification commands

Use Godot 4.6.1. On Windows, redirect APPDATA to a temporary test profile if the test environment restricts writes. Do not use headless rendering to claim visual or shader compilation coverage. Run graphics suites sequentially to avoid simultaneous driver compilation exhausting memory.

```powershell
$godot = 'C:\path\to\Godot_v4.6.1-stable_win64.exe'
$env:APPDATA = Join-Path $env:TEMP 'kiwi-material-tests'
& $godot --path . --rendering-method gl_compatibility --script res://scripts/materials/natural_material_engine_test.gd
& $godot --path . --rendering-method forward_plus --script res://scripts/tests/shader_library_validation.gd
python scripts/actors/tests/run_regressions.py --godot $godot --renderer forward_plus
python scripts/actors/tests/run_regressions.py --godot $godot --renderer forward_plus --report material_perf live_material_benchmark
& $godot --path . --rendering-method forward_plus --script res://scripts/actors/tests/live_material_benchmark.gd -- --adaptive-only
python scripts/tests/rebuild_shader_library_index.py
```

Evidence is written under `.godot/verification/`: all material-family comparison sheets, actual 2D/3D surfaces, live-template workflow, browser screenshots, every shader preview, structured catalog reports and benchmark data. These are generated verification artifacts, not bundled placeholder thumbnails. The delivered patch's README records the checks actually executed and their outcomes on the implementation machine.
