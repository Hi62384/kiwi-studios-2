# Actor foundation

Saved data uses Godot Resources; live nodes only display or execute that data.
The timeline UI now uses this foundation through `ActorTimeline`. Inspector,
filesystem resolution, scene persistence, and keyframes are not connected yet.

## Timeline UI

`Workspaces/SceneWorkspace/Timeline.tscn` is embedded in the main scene. Use
**+ Actor** to create a 3D Point at the ruler cursor. Select and drag a clip to
change its start time, or enter a time in **Start**. **Delete**, **Undo**, and
**Redo** operate on the timeline model. Ctrl+Z and Ctrl+Y / Ctrl+Shift+Z work
when the timeline has focus; text fields keep their normal editing shortcuts.
Dragging previews the change and commits one history entry on release. Escape
or losing application focus cancels it. Snap uses 0.1-second intervals; Shift
bypasses it. Zoom and scrolling are view changes and do not enter undo history.

Drag either clip edge to trim its length (minimum 0.1 seconds). Left trims keep
the right edge fixed and adjust source offset to preserve source-time alignment;
right trims keep the start fixed. Each gesture commits one undo action. Holding
the pointer near either timeline edge scrolls continuously while moving/trimming.

The properties panel displays fields from the selected actor definition. Vector,
number, boolean, text, and color values use the same timeline undo history.
Numeric text commits on submission/focus loss, and color edits on picker close.
Object-reference pickers are not implemented yet. The current 3D Point exposes
position, rotation, and scale. These edit saved actor data; runtime viewport
integration remains a separate step.

Built-in type metadata and default values live in the editable, saveable
`examples/basic_actor_catalog.tres` resource. `BasicActors` only loads that
catalog into the registry; runtime scripts contain behavior rather than defaults.
Each property stores its inspector section in `options.group`, and each definition
references its own SVG icon. The inspector renders grouped sections; the icon is
reused in the actor picker, timeline clip, and selected-actor header.
Category headers can be expanded and collapsed. `ActorInspectorState` stores each
actor's category states, scroll position, and vector-link toggles. The state is
embedded in `Project` and saved back to its `.tres` file after a short debounce,
so frequent scroll events do not write on every pixel.
Actor names can be edited in the inspector and use the same undo history.
Numeric fields support horizontal dragging (one tick per four pixels): 0.1 by
default, 1 with Ctrl, 0.01 with Shift. Shift wins when both are held. A click
without dragging enters text editing. Drag previews commit once on release;
Escape or application focus loss cancels them.

During numeric dragging, every step updates actor data and reevaluates its runtime
so the viewport responds before release. The original complete property value is
captured at the start; only release creates a single undo action, while Escape
restores the original value. The pointer wraps to the opposite edge of the editor
viewport, rebasing its position without changing the value. Modified properties
show a reset button which restores their definition's default through undo/redo.
Vector headings have a chain toggle: when enabled, an edit sets every component
to the newly entered value (it does not preserve ratios). Link state is an editor
preference retained per actor/property for the session. Reset always restores the
complete default vector, regardless of the link state.

Color-picker gestures follow the same preview/commit split: the first color
change immediately updates actor data and the viewport, and release creates one
undo entry. Closing the popup always clears its contextual interaction hint.

Actor runtimes are synchronized into `World/SubViewport/ActorRuntimes` and are
evaluated whenever the cursor or actor data changes. Meshes, 3D text, lights, and
actor cameras explicitly use visibility/cull layer 1, which matches the editor
camera. Visible starter actors default to `(0, 0, -3)` so they appear in front of
the initial free camera.

The **3D Image** actor prompts for an image before its first timeline clip is
created. Cancelling the project asset picker cancels creation. The selected file
is wrapped in an editable `Image` object, so creation remains one undo action.
The same resource slot can create a **Noise Image**, an Image-compatible procedural
object with resolution, seamless generation, FastNoiseLite algorithm, seed,
frequency, fractal, contrast, inversion, and gradient-color controls. Image objects
show a live inspector preview and can be embedded, saved, shared, or made unique.
The runtime resolves either Image subtype onto a transparent, unshaded 1×1-meter
quad on visibility layer 1. On creation, its X/Y scale preserves the selected image's
aspect ratio: the longer side is `1.0` and the shorter side is a fraction, so no
component exceeds `1.0`. This ratio is the Scale property's actor-dependent
default, so Scale's reset button recomputes the same ratio from the actor's current
image rather than resetting to `(1, 1, 1)`. Its dimensions are then changed with
the normal Scale property.
The custom read-only picker has a project folder tree, a large filtered file grid,
per-file thumbnails, selected-asset preview, and project-wide search. It never
navigates outside the loaded project directory and validates the selected path
again before accepting it. The picker itself is file-type agnostic: a property
supplies any allowed extension list, or an empty list to accept every file type.
The tree includes the matching assets beneath their folders, hides folder branches
with no matches, and shows each folder's recursive match count. Files can be
selected or double-clicked directly in either the tree or thumbnail grid.
Actor file properties opt into this reusable UI with `options.file_picker`, `extensions`, and,
when needed, `prompt_on_create` in the catalog resource.

The primitive Cube and Sphere entries have been consolidated into **Basic Shape**.
Its Shape choice provides Box, Sphere, Cylinder, Capsule, Plane, Prism, Quad, and
Torus, while Scale controls dimensions and its Material slot accepts Material or
ShaderMaterial. **Basic Mesh** accepts embedded Mesh resources and project GLB,
GLTF, FBX, OBJ, DAE, Blend, `.mesh`, `.res`, or `.tres` assets; an optional
Material slot overrides every MeshInstance3D in an imported model. **3D Light**
switches between Directional, Omni, and Spot modes with shared color, energy,
shadow, range, and spot-angle controls. **World Environment** contains one editable
Environment resource slot. Expanding that resource exposes Background, Ambient
Light, Tonemap, and Fog categories; the resource can be embedded, saved, shared,
loaded, or made unique like a Material, and drives the viewport while its clip is active.
Background mode supports Color, panorama Image, Godot ProceduralSkyMaterial, and
a sky `.gdshader` wrapped in ShaderMaterial, plus sky rotation. The resource also
exposes Reflected Light, SSR, SSIL, SDFGI, Glow, Volumetric Fog, and Adjustments.
Removing or deactivating the actor restores the viewport Environment that was
active before it. A dedicated **Directional Light** actor exposes angular size,
indirect and volumetric energy, negative/specular contribution, sky mode, and
cascaded-shadow controls. Basic Shape uses Godot PrimitiveMesh resources and has
per-shape sections for native size, radius, height, subdivision, segment, ring,
hemisphere, orientation, prism, torus, and cylinder cap properties.

### File resource properties

`ActorProperty.file_resource_mode()` distinguishes two asset behaviors declared by
`options.file_resource_mode`. `uneditable` properties store a project file path and
only allow choosing/resetting it; Image is the first example. `editable` properties
store an `ActorObjectReference`. They can choose a correctly typed saved resource or
create an `ActorObjectData` embedded in the actor. Embedded resources can be saved
into the project's generated `Materials` folder, at which point the actor switches
to a shared asset reference. Nested edits use the actor undo history; edits to a
saved resource are also written back to its `.tres` file.

Material is registered as an `ActorObjectDefinition` in the same catalog as actor
types. It exposes Tint, an Image-compatible Albedo map, Opacity, Roughness,
Metallic, Specular, emission controls,
Unshaded, Double sided, and Disable depth test. The Image actor defaults Material to
null and displays the source image plainly until one is assigned. Its runtime
evaluates all nested material values. Material selection filters `.tres`
files by declared object type, rather than showing unrelated resources. Double-click
an editable resource in the project filesystem to replace the actor view in the
properties panel with that resource's fields; those edits save to the resource.

Editable references render as a resource slot to the right of the actor property
name. An empty slot opens New/Load choices on either left- or right-click. A populated
slot expands and collapses its boxed resource inspector on left-click and offers New,
Load from project, Make Unique, Save As, and Clear on right-click. Make Unique installs
an embedded copy; Clear assigns null. These assignments use the actor history. Save As
uses the custom project-only folder/name dialog. Resource actions are kept out of the
expanded property box so its fields are visually separate from actor properties.

The mouse wheel scrolls layers vertically while it is over the timeline body.
Over the seconds ruler it scrolls time horizontally; the two regions update their
corresponding scrollbars independently.

### Contextual interaction hints

New gestures should publish their applicable shortcuts through `InteractionHints`:
call `begin(owner, text)` when the action starts and `end(owner)` on completion,
cancellation, or teardown. The latest active context is shown, with no idle list
of unrelated keys. Timeline moves/trims and property drags show only
`Esc cancels drag`; ruler scrubbing shows `Esc cancels scrub`.

Each actor has one clip in this first version. Rows are shared layers: click a
layer to choose it for creation, and drag clips vertically to change layers.
Creation uses the next available gap on the chosen layer if the cursor is occupied.
Moves snap to the nearest available position before or after neighboring clips,
checking the entire layer to avoid secondary overlaps. Touching edges are allowed.
Dragged trim edges stop at neighboring clips. A move's layer and time are undone
together. Empty destination
layers remain available below the used layers.

Timeline state lasts for the
current editor session; saving the scene and connecting runtimes to the viewport
are separate integration steps. The timeline history is separate from the existing
filesystem history, and shortcuts are scoped to the focused area.

## Create and evaluate an actor

```gdscript
var registry := ActorRegistry.new()
BasicActors.register_all(registry)
var definition := registry.get_definition(&"point_3d")
var actor := definition.create_actor()
var clip := ActorClip.create(actor, 0.0, 5.0)
var runtime := definition.create_runtime(actor)
add_child(runtime)
# Wait until runtime.is_node_ready() before evaluating if the parent isn't ready.
definition.set_property_value(actor, &"position", Vector3(2, 0, 0))
runtime.evaluate_clip(clip, 2.0)
# Future keyframe sampling can pass temporary overrides:
runtime.evaluate_clip(clip, 3.0, {&"position": Vector3(4, 0, 0)})
```

Create one runtime per clip when multiple clips can evaluate the same actor at
different local times. `ActorTimeline.set_parent(child_id, parent_id)` validates
that both actors exist and prevents parent cycles; `unparent(child_id)` clears the
relationship. Both operations share timeline undo/redo. Deleting a parent
temporarily detaches its direct children and undo restores their relationships.
The timeline editor mirrors this logical tree in its disposable runtime roots;
the scene-tree controls for choosing a parent are still a separate UI task.

## Add an actor type

1. Create a scene with a root script extending `ActorRuntime`.
2. Override `evaluate(local_time, values)` and `set_active(value)`.
3. Create an `ActorDefinition` with stable type/property IDs and that scene.
4. Register the definition, as in `examples/basic_actors.gd`.

Runtime evaluation must be deterministic at an absolute time and treat supplied
values as read-only. Update private runtime materials/resources rather than
mutating saved or shared resources. Definitions are immutable after registration.
Property `options` supplies the default and future inspector hints; min/max hints
are not yet enforced. Current type checking is exact, including int versus float.

## Embedded objects and filesystem assets

```gdscript
var material_type := ActorObjectDefinition.new()
material_type.type_id = &"material"
material_type.display_name = "Material"
material_type.properties = [
    ActorProperty.create(&"color", "Color", Color.WHITE, true),
    ActorProperty.create(&"roughness", "Roughness", 0.5, true),
]
var material := material_type.create_object()
var reference := ActorObjectReference.from_object(material)
var property := ActorProperty.create(&"material", "Material", reference)
property.object_type = &"material"
# Add property to an actor definition before registering it.
```

An `ActorObjectData` can be saved directly with `ResourceSaver.save` to a `.tres`
file, or embedded through a reference in an actor's values. Object definitions
describe the inspector fields in either case. Keep them in an application-owned
map keyed by `type_id` when implementing the inspector.

For file-backed objects, use `ActorObjectReference.from_asset(asset_id, type_id)`.
Pass a Callable to `resolve()` that maps that ID to loaded `ActorObjectData`.
The asset ID/path index is intentionally left to the filesystem integration;
no paths are assumed or scanned by the actor layer. Missing/wrong-type assets
resolve to null and keep the reference intact. Native media such as textures
will need import/adaptor code; the resolver currently returns ActorObjectData.

`make_unique(resolver)` returns a new embedded copy, or null for a missing asset.
`copy_actor()` assigns a new actor ID and copies owned data; external references
keep their asset IDs. Embedded objects must form an acyclic ownership tree.
Reassigning properties emits `changed`; nested edits emit on the nested resource,
so the future document controller should track those or route edits via commands.

Resources have schema versions for future migrations; migration logic is not
implemented. Store actors and clips in a future scene document Resource. Use one
document command/undo layer around definition setters instead of putting undo
history in individual actors.

## Property animation

Click a property's diamond in the actor inspector to key it at the timeline
cursor. Nested object fields and shader uniforms have the same controls, including
when the object is a file-backed resource. The selected actor's tracks appear below
the timeline, grouped by property/resource path. Click keys to edit their time,
value, outgoing interpolation (linear/ease/step), and attenuation. Shift/Ctrl-click
selects multiple keys, dragging moves them together, arrows nudge, Ctrl+A selects
keys, and Delete/Backspace removes them. Esc cancels pointer edits. Right-click a
property diamond to remove the current key or its entire animation.

Once a property has a track, its regular inspector edits key the value at the
cursor; preview gestures apply live and commit one undo action on release.
`ActorData.animation_tracks`, `ActorAnimationTrack`, and `ActorKeyframe` are saved
Resources. Key times use clip source-local seconds, so moving/trimming clips does
not rewrite key positions. Copies own their tracks. Runtime sampling creates
private nested object overrides and never saves animated values into shared files.

Eligible scalar, vector, color, switch, enum, and text fields support keys;
resource/file slots themselves do not. Set a property's `options.no_keyframes`
to true to opt a field out. Switches, text, and enum controls default to stepped
interpolation. Keyframe commands share the actor timeline's undo/redo history.

Run `res://scripts/actors/tests/actor_keyframes_test.gd` for animation, inspector,
sampling, resource round-trip, file-backed object, shader uniform, pointer editing,
and undo/redo regression coverage.

## Smoke check

Run Godot headlessly with `--path <project> --script
res://scripts/actors/tests/actor_smoke_test.gd` after the editor has imported the
project. The check covers registration, validation, copying, object resolution,
serialization, and absolute-time evaluation. Its temporary save is removed.
