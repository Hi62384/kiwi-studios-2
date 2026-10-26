# 3D Modeling Workspace — first implementation

Open **+ → 3D Modeling** in the main tab bar. Model documents, scene documents,
shaders, images, and audio retain separate workspaces. No external modeling app,
service, neural model, application export, or additional dependency is required.

## Fast workflow

1. Use **Create** to add a primitive, or choose **Draw Box / Draw Cylinder** to
   drag a footprint, release, set its height, then click to confirm.
2. Use **Object / Vertex / Edge / Face** (keys **1–4**).
3. Drag the colored handles. **W / E / R** choose move / rotate / scale.
   **G** starts a free move and **S** starts a scale. During a transform,
   **X / Y / Z** constrain an axis, **Shift+axis** constrains a plane, numbers
   enter a precise amount, **Ctrl** temporarily toggles snapping, **Enter**
   confirms, and **Esc** cancels.
4. Select a face and use **Push/pull** (or **Alt+drag**) to extrude/recess it.
   A distance can be typed during the drag. **Extrude / Inset / Bevel** also
   provide compact numeric dialogs with live previews and Apply/Cancel.
5. **Space / Commands** searches operations with subsequence matching and recent
   commands first. **Ctrl+D** duplicates and starts a move in one undoable gesture.
6. **File → Save** or **Ctrl+S** saves the editable model. **Ctrl+Shift+S** saves
   a separate asset. Native `.tres` and binary `.res` resources are supported.
7. **To Scene** saves and instantiates the model's hierarchy in a scene tab:
   one editable actor per mesh, transform actors for groups, and Skeleton Rig
   actors for skeletons, all beneath a linked/folded root.

In Components, drag a mesh/group onto another to parent it, or into empty tree
space to unparent it. Parent/Unparent buttons remain available. Nested subtrees
keep their internal hierarchy; reparenting preserves world transforms, rejects
cycles and supports Undo/Redo.

Navigation: **RMB + WASD/QE** flies, wheel while flying changes speed, **MMB**
orbits, **Shift+MMB** pans, wheel zooms, **F** frames the selection and
**Shift+F** frames the model. View provides perspective/orthographic and six
principal views. The corner axis indicator is clickable; Shift chooses the
opposite view. Hierarchy and properties can be hidden; smaller new workspaces
collapse the hierarchy to favor the viewport.

## Working features

- Indexed polygon topology, shared vertices, edge/face adjacency, n-gon
  triangulation, per-corner UVs, face material slots, generated normals and
  tangents, and separate generated rendering meshes.
- Objects and multi-component hierarchies with stable IDs, local transforms,
  pivots, grouping, parenting/unparenting, duplication, renaming, hiding, locking,
  joining, and separating selected faces.
- Object, vertex, edge, and face picking; additive/toggle selection, rectangle
  selection, X-ray selection, select all/invert, connected selection,
  grow/shrink, similar face normals, and matching material regions.
- World/local transform handles, numeric transforms, proportional editing,
  grid/vertex/edge/surface/origin snapping, and optional surface-normal alignment.
  Surface placement offsets the mesh onto the surface rather than embedding
  the object's origin inside it.
- Region/individual-face extrusion, direct push/pull, inset, convex chamfer
  bevels, edge/face/whole-mesh subdivision, weld, smooth, flip normals, and delete.
  Partial face subdivision updates neighboring polygon boundaries to avoid
  T-junctions.
- Editable procedural box, sphere, cylinder, cone, capsule, plane, torus, prism,
  gear (including teeth and shaft hole), pipe, bolt head/shaft, arch, stairs,
  beam, and panel. Parameter changes regenerate the source until it is made
  editable or directly edited.
- Evaluated modifier stack: bisected/welded mirror, linear and radial arrays,
  quad subdivision, smoothing, solidify, twist, taper, and convex bevel. Parameters,
  enable state and order affect the preview. Apply-through-here bakes a stack
  prefix into editable polygon data.
- Boolean union/difference/intersection using temporary engine CSG followed by
  a bake into editable mesh data. No permanent CSG nodes are saved in the model.
  Cutters are retained hidden; Undo restores them. Existing materials are passed
  through the bake, including material regions on newly cut surfaces.
- Contextual grab, inflate/deflate (Ctrl), smooth, flatten, and pinch brushes.
  Shift+wheel adjusts their radius. These are modest mesh-deformation tools,
  not a high-resolution sculpting engine.
- Flat/smooth shading, UV preservation through import and core operations,
  native Material slots, face assignment, albedo tint, and existing Scene
  Material/ShaderMaterial overrides. Tint edits duplicate the material so its
  other settings and textures are preserved and Undo remains independent.

## Saving and scene integration

Native assets preserve topology, parameters, modifiers, components, hierarchy,
materials, pivots, selection, camera/navigation state, tool settings, and panel
layout. Preview images are stored as PNG bytes and decoded lazily, so a mesh-only
load does not need to create a GPU thumbnail texture.

Native models can be opened by double-clicking them in the project filesystem,
loaded in a Basic Mesh resource slot, or dragged onto the scene timeline.
The Basic Mesh inspector has **Model ↗** and **Unique…** actions. Saving a shared
model refreshes its scene instances; a unique asset affects only actors which
reference that separate file. Opening an existing model reuses its tab.

Dragging a model file onto the timeline or using **To Scene** creates individual
scene actors with the model's names, parent links, local transforms, and material
slots. Non-mesh grouping nodes are retained rather than flattened. The entire
import is one undoable action. Existing opaque Basic Mesh actors remain supported.
Shared geometry saves refresh component meshes; later changes to the source
node structure require instantiating the model again (existing scene parenting
and animation are not silently overwritten).

### Skeleton rigs and posing

The Modeling workspace now also supports **Quick Rig → Bind → Pose**, viewport
bone creation, reusable templates, soft and rigid binding, weight painting and
region assignment. See [the rig-authoring guide](rigging.md) for the workflow,
safety boundaries, validation and explicitly unfinished advanced scope.

Imported Skeleton3D nodes become **Skeleton Rig** actors. Bone names, parents,
rest transforms, mesh skin weights and bind poses survive native model and scene
serialization. Skin links are remapped independently for each instance.

Select the rig actor and choose **Bones** in the viewport toolbar (**B** toggles).
Click a joint or bone to select it; **W/E/R** choose move, rotate or scale and
show the corresponding 3D handles. **Ctrl** snaps, **Esc** cancels, **Rest** resets
the selected bone, and **I / ◆ Pose** keys its position, rotation and scale at
the playhead. The inspector also has a bone picker, draggable XYZ pose values,
and the usual property-keyframe controls. Once a channel is animated, editing it
inserts/updates a key. Bone tracks appear in the existing keyframe editor and
use its curves, component separation and timing tools. Rotation sampling uses
quaternion shortest-arc interpolation. Bone guides are editor-only, not rendered.

Import copies Mesh and PackedScene resources and their mesh hierarchy,
transforms, materials, and UVs. Runtime GLB/GLTF loading is supported; other
formats depend on Godot's existing imported resources. Original imported files
are never overwritten merely by converting them. Imported non-native sources
require Save As to create an editable model asset.

## Explicit limits and unfinished scope

This is a usable modeling foundation, not completion of every advanced item in
the original specification. Unsupported tools are not exposed as working tools.

- Bevel is a single-segment chamfer for convex, relatively small meshes (at most
  64 clipping planes). Arbitrary concave/non-manifold edge bevels, rounded bevel
  profiles, and production CAD robustness remain unfinished.
- Subdivision splits topology into quads; it is not Catmull–Clark subdivision.
  Smoothing is a separate operation/modifier. Per-edge hard-normal authoring and
  a UV unwrapping/editor workspace remain unfinished.
- General sketch-to-topology/cutting, editable curves/tubes, edge loop/ring
  selection, bridge, slide, collapse, topology-aware retopology, and advanced
  sculpting/remeshing are not implemented.
- Boolean interaction is limited to 2,500 evaluated input faces. Empty/failed
  results leave the sources intact. Dense asynchronous geometry processing and
  a general non-destructive Boolean modifier with a live cutter dependency are
  not implemented; the current Boolean commands bake once and remain undoable.
- Proportional weights are cached during a drag. Neighborhoods requiring more
  than two million distance comparisons are refused with an explanation rather
  than freezing the interface. Very dense mesh editing has not been certified
  as production-ready.
- Mirror's editable control cage is its source geometry; use the retained half
  for bisected mirror editing and Apply to edit the complete result. Arbitrary
  custom mirror planes and universal symmetric brush behavior remain future work.
- Native Godot materials and Scene overrides work; a full shared Kiwi object-
  material binding/editor inside the modeling panel remains future integration.
- References currently use file paths. After moving/renaming an already-referenced
  model file, relink it in the Basic Mesh slot; automatic path-move relinking is
  not implemented by this workspace.
- Rig authoring, painting and posing are available; IK, constraints, retargeting,
  general topology-preserving weight transfer and imported AnimationPlayer
  library conversion remain unfinished. Weighted topology is protected rather
  than silently discarding skin weights. See the rig-authoring guide above.
- No interchange exporter, physics authoring, cloth, M2DO renderer, or
  automatic character-generation system was added.

## Validation

New automated suites:

- `model_geometry_test.gd`: all primitives, winding versus native Godot meshes,
  mesh validity, connected inset/extrusion, closed convex bevels, conforming
  subdivision, welded mirror seams, radial-array placement, hierarchy, duplication,
  serialization, import independence, and connectivity selection.
- `model_workspace_test.gd`: native viewport clicks/handles, push/pull,
  undo/cancellation, table save/reopen, a real cylindrical through-hole, procedural
  arrays, organic smoothing, and recessed wall geometry.
- `model_interaction_test.gd`: vertex/edge manipulation, constrained rotation and
  scale, combined duplicate-and-move undo, X-ray rectangle selection, unchanged
  mesh caching, interactive primitive creation, surface placement/alignment,
  document cancellation/isolation, and compact layout.
- `model_scene_integration_test.gd`: full application launch, real operation
  dialogs, project saving, Basic Mesh resource acceptance, shared/unique scene
  instances, scene serialization, model tab retention, and workspace isolation.
- `model_hierarchy_rig_test.gd`: drag/drop parenting, nested affine transforms,
  individual scene actors, single-action import undo/redo, group/skin import,
  real rigged GLB loading, visible skin deformation, bone move/rotate/scale,
  pose keyframes, scrubbing, cancellation and scene persistence.

The regression runner uses isolated user profiles. Native rendered screenshots
and JSON/log reports are under `.godot/verification/model_workspace/` and
`.godot/verification/model_*.json`. Application exports are not part of testing.

Initial implementation, Godot 4.6.1, Windows, Forward+ (2026-10-21): four modeling
suites passed 134 checks. Full application launch and headless editor validation
also passed. Existing application, scene-viewport, image-studio and shader suites
were exercised alongside the modeling tests. See `model_verified.json`,
`model_remaining_regressions.json` and `model_editor_final.log` for the final runs.
The shader-library clipboard check required one retry after Windows temporarily
refused clipboard access; its subsequent native runs passed. The engine's existing
Windows root-certificate-store warning is unrelated to modeling or compilation.

Hierarchy/rig follow-up validation: **57 focused checks passed**, plus **11/11
regression scripts**, including the five modeling suites, scene viewport tools,
actor animation, scene persistence, scene tabs, actor types and full application
launch. See `.godot/verification/model_rig_complete.json` and
`model_rig_editor_complete.log`. Headless editor import/compilation passed.
The scene-data suite deliberately tests a shader compiler error; the older
actor-type and scene-data fixtures still report their existing shutdown resource
warnings. The new hierarchy/rig suite has no script errors or shutdown leaks.

Example command (substitute the local Godot console executable):

```powershell
python scripts/actors/tests/run_regressions.py --godot PATH_TO_GODOT --renderer forward_plus --report model_verify model_geometry_test model_workspace_test model_interaction_test model_scene_integration_test model_hierarchy_rig_test
```
