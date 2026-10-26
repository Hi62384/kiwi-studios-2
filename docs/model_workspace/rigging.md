# Universal armature authoring

This is the first integrated, end-to-end rig-authoring foundation, not completion
of every advanced feature in the supplied universal-rigging specification.
It extends the existing Modeling workspace and the existing Scene skeleton actor;
there is no separate humanoid-only rigging engine.

## Fast path: Create → Bind → Pose

1. Select one or more mesh components in a Modeling tab. **Quick Rig** offers a
   fitted chain, rig templates, viewport bone drawing, or an existing armature.
2. Fit the bones using **Edit**: drag a joint, or change its rig-space head/tail
   coordinates and roll in the inspector. Connected joints stay connected unless
   explicitly disconnected. Use orthographic Front/Side/Top views for depth work.
3. Choose **Smooth**, **Distance**, or **Envelope**, then **Bind**. Calculation
   runs in a cancelable worker. The original geometry is not overwritten.
4. Choose **Pose**. Click a bone and use **W / E / R** handles or numeric pose
   fields. **Ctrl** snaps and **Esc** cancels a gesture. Test Bend and reset
   controls make deformation checks quick. Rest editing and posing are distinct.
5. Choose **Weight** to correct the same posed mesh without leaving the viewport.
6. Save the model, then **To Scene**. Its skeleton becomes a Skeleton Rig actor;
   meshes and points remain separate actors with the original hierarchy.

**Auto Rig is deliberately a bounds-fitted editable chain.** It does not claim
to recognize arbitrary anatomy. Humanoid and animal templates are approximate
bounds fits and need artist correction before binding.

## Bones and templates

- Draw connected chains by clicking successive joints. **Enter** ends the chain;
  **Escape** clears it; right-click cancels a pending point.
- Placement modes: Inside Mesh, Surface, camera-facing View Plane with depth,
  and fixed XY/YZ/XZ construction planes. Nearby existing joints snap together.
- Edit head/tail positions, name, roll, parent, and envelope radius. The envelope
  circle can be dragged in the viewport; rebind with Envelope to recalculate.
- The **⋯** menu provides extrusion from the current tip, parent/child navigation,
  connect/disconnect, insertion, duplicate/mirror chain, unparent, delete, reset
  pose, save/load preset, detach, and exit rigging.
- Mirror creation and joint edits support X/Y/Z symmetry and an offset plane.
  Mirrored counterparts keep stable links and predictable `_L` / `_R` names.
- Templates cover humanoid/simplified humanoid, quadruped, bird, fish, snake,
  insect, spider, tail, tentacle, flexible chain, branch, long neck, hinged arm,
  shaft, slider, robot arm, and a basic rigid-assembly chain. Chain length is
  adjustable. Mechanical templates do not create constraints automatically.
- **Save rig** creates a reusable `KiwiRigPreset` resource containing hierarchy,
  rest transforms, stable authoring IDs, names, roll, mirror links and metadata.
  Load Rig approximately fits a new independent armature to the current target.

## Binding and weight correction

Smooth binding combines bone-segment distance scoring, welded triangle
connectivity, per-island candidate restrictions, and anchored neighborhood
smoothing. It is a useful initial solver, **not** an anatomical/heat-diffusion
solver or a guarantee of production-character deformation quality. Distance
and adjustable-radius Envelope remain available for different geometry.

The renderer receives real four-influence bone/weight arrays, inverse bind
matrices and a shared `Skeleton3D`. The reusable backend also supports eight
influences. Posing updates skeleton matrices without rebuilding the source mesh.
Soft binding requires triangular surfaces; line/point components can use Rigid.

- Weight mode displays the selected bone as blue → green/yellow → red influence.
- Add, Subtract, Replace, Smooth, and Clear brushes have radius/strength controls.
  **Shift+wheel** changes radius; **Ctrl** temporarily subtracts. Back-side
  painting and selected-vertices-only painting are explicit options.
- Select Vertices / Select Faces support click or rectangle regions, additive
  **Shift/Ctrl** selection, and numeric **Assign selected region**. Weight 1
  makes a region rigid to that bone. Rectangle selection is through-selection.
- Lock Selected Influence preserves that bone's values during painting and
  reweighting; normalization only redistributes the unlocked budget.
- Normalize and Fix Weights normalize/cap influences; Fix Weights also prunes
  tiny unlocked values below `0.00001`. These operations are undoable.
- Mirror Weights copies from the selected bone's side to the opposite side,
  retaining the source side. It requires matching reflected vertex positions;
  it is not nearest-surface weight transfer. Center bones default to negative
  → positive. The symmetry plane controls the reflection.
- Validate reports invalid indices, missing bindings, nonfinite/negative weights
  and unweighted/non-normalized vertices. It does not diagnose artistic quality.
- Keep a bone posed while painting, compare rest/pose, show/hide guides, or show
  only the selected descendant chain. Turn off Compare Rest before painting.

For mechanical parts, select the part(s), choose a bone, choose **Rigid**, then
**Bind**. Components follow that bone with a preserved rest offset and no soft
skin weights. Soft and rigid parts can share one armature. They do not need to
be joined. Native model-node instantiation also supports rigid follow without
rewriting the component hierarchy.

## Persistence, undo and source safety

- Native models save authoring bones, editable weights/locks, source surfaces,
  attachments, poses and active rig workspace state. Weight strokes and region
  edits store sparse vertex undo deltas. Structural edits use bounded model
  history. Escape restores canceled gestures; bind/rebind is one action.
- Original surfaces, material slots/names, normals, UV/UV2, colors, custom vertex
  channels and morph targets are retained by the skin-generation path. Relative
  morphs are transformed as deltas. Original source resources remain unchanged.
- Existing imported skins remain intact. Adopt Imported Weights only accepts
  a verified compatible mesh-space/inverse-bind convention. Unsupported custom
  binds are retained; the user can explicitly rebind instead. Their rest
  structure is protected until adoption/rebinding.
- Weighted topology edits, modifiers and direct bound-component rest-transform
  edits are guarded instead of silently losing weights. Detach first to model
  again; move the armature or a common parent to place the rigged model.
- Deleting a bone remaps influences to a surviving ancestor/fallback bone.
  Deleting the last bound bone, or deleting an armature while leaving its bound
  meshes behind, is refused. Detach or select the complete assembly first.
- Scene bone channels use the existing keyframe system, curves and timeline.
  In Scene, select the Skeleton Rig and enable **Bones / B**; **I / ◆ Pose** keys
  the selected bone. Bones/guides/heatmaps are editor-only.
- Scene instances own their bone structure and animation. Skin/weight changes
  can refresh when the source bind structure is compatible. If source bone
  rests/hierarchy change, existing scenes retain their compatible skin snapshot
  rather than mixing new bind matrices with old animated bones. Reinsert the
  updated rig to use its new structure; automatic animation remapping is not
  implemented.
- Weight jobs are canceled/joined on document switches or workspace close.
  Results from changed documents or active uncommitted edits are discarded.
  Soft binding is limited to 100,000 raw source vertices and 3 million
  vertex/bone pairs per selection; over-budget requests explain the limit.

## Explicit remaining scope

- Anatomical auto-detection, optional finger/toe generators, full multi-bone
  selection/group transforms, mirrored pose commands and named diagnostic poses.
- General nearest-surface/topology weight transfer; destructive topology edits
  retaining weights; automatic scene-animation remapping after structural edits.
- Geodesic/heat-diffusion quality solving, per-vertex influence-lock UI, and
  automatic detection of suspicious artistic influence regions.
- IK/FK, constraints, pole targets, mechanical joint limits/drivers, retargeting,
  control rigs and imported AnimationPlayer library conversion.
- Generated skin meshes do not regenerate/copy source LOD tables. Immutable
  originals are retained. Full dense-mesh, custom-channel and morph-animation
  production certification remains work; do not assume every imported asset
  convention is editable. Weight-pick CPU geometry is cached per stroke, but
  very dense brush interaction has not been performance-certified.
- M2DO/Morphable Image appearance integration and interchange rig export are not
  added. The data and solver consume ordinary meshes so those systems can reuse
  the same rig foundation later.

## Validation

Focused Godot 4.6.1 native Forward+ tests cover algorithms/data safety, actual
viewport mouse gestures, threaded binding/cancellation, GPU deformation versus
CPU picking, weight regions/locks/sparse undo, original surface/morph attributes,
rig presets, model/scene roundtrips, affine hierarchies, bone keyframes and rigid
attachments. Existing modeling, scene, shader, image and app smoke suites are
also exercised. Final logs/reports are under `.godot/verification/rig_authoring_*`.
No application export is needed or performed.

Validation on Windows with Godot 4.6.1 / native Forward+ (2026-10-22):

- **114 focused rig checks passed:** 68 data/algorithm checks, 30 viewport/workflow
  checks and 16 scene/animation checks. Latest report:
  `.godot/verification/rig_authoring_validated.json`.
- **16/16 regression scripts passed**, including the rig suites, five existing
  modeling suites, actor types, scene persistence, shader materials, image
  selection, text interactions, full application smoke, scene viewport tools and
  scene-tab/remote transforms. Report:
  `.godot/verification/rig_authoring_final.json`.
- Headless editor import/compilation and final script compilation passed. Native
  screenshots are under `.godot/verification/model_workspace/`.
- The new rig suites have no script errors or shutdown leaks. Godot's existing
  Windows certificate-store warning remains. Older actor-type, scene-data and
  shader-material fixtures still log their existing teardown resource warnings;
  the latter two also deliberately compile invalid shaders in negative tests.

```powershell
python scripts/actors/tests/run_regressions.py --godot PATH_TO_GODOT --renderer forward_plus --report rig_authoring_verify rig_authoring_core_test rig_authoring_viewport_test rig_authoring_scene_test
```
