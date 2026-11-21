using Godot;
using System;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Linq;

public partial class LegacyResourceLoader : ResourceFormatLoader
{
    private static readonly Dictionary<string, string> Replacements = new()
    {
        ["res://Workspaces/AudioWorkspace/audio_instruments.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioInstruments.cs",
        ["res://Workspaces/AudioWorkspace/audio_templates.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioTemplates.cs",
        ["res://Workspaces/AudioWorkspace/audio_asset_index.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioAssetIndex.cs",
        ["res://Workspaces/AudioWorkspace/audio_library.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioLibrary.cs",
        ["res://Workspaces/AudioWorkspace/audio_preset_store.gd"] = "res://Workspaces/AudioWorkspace/AudioPresetStore.cs",
        ["res://Workspaces/AudioWorkspace/audio_preset.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioPreset.cs",
        ["res://Workspaces/AudioWorkspace/audio_edit_session.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioEditSession.cs",
        ["res://Workspaces/AudioWorkspace/audio_portable_copy.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioPortableCopy.cs",
        ["res://Workspaces/AudioWorkspace/audio_document.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioDocument.cs",
        ["res://Workspaces/AudioWorkspace/audio_transcription.gd"] = "res://Workspaces/AudioWorkspace/AudioTranscription.cs",
        ["res://Workspaces/AudioWorkspace/audio_layer_bundle.gd"] = "res://Workspaces/AudioWorkspace/AudioLayerBundle.cs",
        ["res://Workspaces/AudioWorkspace/audio_group_freeze.gd"] = "res://Workspaces/AudioWorkspace/AudioGroupFreeze.cs",
        ["res://Workspaces/AudioWorkspace/audio_optional_process.gd"] = "res://Workspaces/AudioWorkspace/AudioOptionalProcess.cs",
        ["res://Workspaces/AudioWorkspace/audio_doppler.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioDoppler.cs",
        ["res://scripts/actors/core/actor_screen_recorder.gd"] = "res://scripts/actors/core/ActorScreenRecorder.cs",
        ["res://scripts/actors/core/actor_audio_recorder.gd"] = "res://scripts/actors/core/ActorAudioRecorder.cs",
        ["res://scripts/actors/fog/fog_paint_gizmo.gd"] = "res://scripts/actors/fog/FogPaintGizmo.cs",
        ["res://scripts/actors/physics/structure/structure_gizmo.gd"] = "res://scripts/actors/physics/structure/StructureGizmo.cs",
        ["res://scripts/actors/physics/destruction/destruction_gizmo.gd"] = "res://scripts/actors/physics/destruction/DestructionGizmo.cs",
        ["res://scripts/actors/physics/physics_pin_gizmo.gd"] = "res://scripts/actors/physics/PhysicsPinGizmo.cs",
        ["res://scripts/actors/core/actor_skeleton_gizmo.gd"] = "res://scripts/actors/core/ActorSkeletonGizmo.cs",
        ["res://scripts/actors/core/actor_spatial_gizmo.gd"] = "res://scripts/actors/core/ActorSpatialGizmo.cs",
        ["res://scripts/actors/core/actor_ui_gizmo.gd"] = "res://scripts/actors/core/ActorUIGizmo.cs",
        ["res://Workspaces/AudioWorkspace/audio_modulation_matrix.gd"] = "res://Workspaces/AudioWorkspace/AudioModulationMatrix.cs",
        ["res://Workspaces/AudioWorkspace/audio_conductor_fit.gd"] = "res://Workspaces/AudioWorkspace/AudioConductorFit.cs",
        ["res://Workspaces/AudioWorkspace/audio_impulse.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioImpulse.cs",
        ["res://scripts/actors/core/audio_encoder_process.gd"] = "res://scripts/actors/core/KiwiAudioEncoderProcess.cs",
        ["res://scripts/actors/core/windows_system_audio.gd"] = "res://scripts/actors/core/WindowsSystemAudio.cs",
        ["res://scripts/actors/core/audio_take_writer.gd"] = "res://scripts/actors/core/NativeAudioTakeWriter.cs",

        ["res://scripts/actors/core/actor_timeline.gd"] = "res://scripts/actors/core/ActorTimeline.cs",

        ["res://scripts/actors/core/actor_runtime.gd"] = "res://scripts/actors/core/ActorRuntime.cs",
        ["res://scripts/actors/examples/basic_actor.gd"] = "res://scripts/actors/examples/BasicActorRuntime.cs",
        ["res://scripts/actors/examples/point_actor.gd"] = "res://scripts/actors/examples/PointActorRuntime.cs",
        ["res://scripts/actors/examples/video_actor.gd"] = "res://scripts/actors/examples/VideoActorRuntime.cs",
        ["res://scripts/actors/examples/ui_actor.gd"] = "res://scripts/actors/examples/ActorUIRuntime.cs",
        ["res://scripts/actors/examples/skeleton_rig_actor.gd"] = "res://scripts/actors/examples/ActorSkeletonRigRuntime.cs",
        ["res://scripts/actors/examples/transform_image_2d_actor.gd"] = "res://scripts/actors/examples/ActorTransformImage2DRuntime.cs",
        ["res://Workspaces/EnvironmentWorkspace/environment_actor.gd"] = "res://Workspaces/EnvironmentWorkspace/EnvironmentActorRuntime.cs",
        ["res://scripts/actors/physics/powder/powder_actor.gd"] = "res://scripts/actors/physics/powder/KiwiPowderRuntime.cs",
        ["res://scripts/actors/physics/fluid/fluid_actor.gd"] = "res://scripts/actors/physics/fluid/KiwiFluidRuntime.cs",

        ["res://scripts/actors/core/actor_property_batch.gd"] = "res://scripts/actors/core/ActorPropertyBatch.cs",
        ["res://scripts/actors/core/actor_file_import.gd"] = "res://scripts/actors/core/ActorFileImport.cs",

        ["res://scripts/actors/core/actor_animation.gd"] = "res://scripts/actors/core/ActorAnimation.cs",
        ["res://scripts/actors/core/actor_transformation_states.gd"] = "res://scripts/actors/core/ActorTransformationStates.cs",

        ["res://scripts/actors/core/actor_audio.gd"] = "res://scripts/actors/core/ActorAudio.cs",

        ["res://scripts/actors/core/actor_audio_system.gd"] = "res://scripts/actors/core/ActorAudioSystem.cs",
        ["res://Workspaces/AudioWorkspace/audio_playback.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioPlayback.cs",

        ["res://scripts/actors/core/actor_video.gd"] = "res://scripts/actors/core/ActorVideo.cs",

        ["res://scripts/actors/core/actor_font_picker.gd"] = "res://scripts/actors/core/ActorFontPicker.cs",
        ["res://scripts/actors/core/actor_dimension_dialog.gd"] = "res://scripts/actors/core/ActorDimensionDialog.cs",
        ["res://scripts/actors/core/actor_media_preview.gd"] = "res://scripts/actors/core/ActorMediaPreview.cs",
        ["res://Workspaces/ImageWorkspace/image_operation_preview.gd"] = "res://Workspaces/ImageWorkspace/ImageOperationPreview.cs",

        ["res://scripts/actors/core/actor_text_settings.gd"] = "res://scripts/actors/core/ActorTextSettings.cs",
        ["res://scripts/actors/core/editor_audio_settings.gd"] = "res://scripts/actors/core/EditorAudioSettings.cs",

        ["res://scripts/actors/core/actor_resource_slot.gd"] = "res://scripts/actors/core/ActorResourceSlot.cs",

        ["res://scripts/actors/physics/destruction/destruction_material_control.gd"] = "res://scripts/actors/physics/destruction/DestructionMaterialControl.cs",
        ["res://scripts/actors/physics/destruction/destruction_control.gd"] = "res://scripts/actors/physics/destruction/DestructionControl.cs",
        ["res://scripts/actors/physics/powder/powder_material_control.gd"] = "res://scripts/actors/physics/powder/PowderMaterialControl.cs",
        ["res://scripts/actors/physics/structure/structure_control.gd"] = "res://scripts/actors/physics/structure/StructureControl.cs",

        ["res://scripts/actors/core/actor_shader_time.gd"] = "res://scripts/actors/core/ActorShaderTime.cs",
        ["res://scripts/actors/core/actor_image_generator.gd"] = "res://scripts/actors/core/ActorImageGenerator.cs",
        ["res://scripts/actors/core/actor_skeleton_pose.gd"] = "res://scripts/actors/core/ActorSkeletonPose.cs",

        ["res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd"] = "res://Workspaces/ImageWorkspace/PixelSelectionAlpha.cs",
        ["res://Workspaces/ImageWorkspace/image_soften_brush.gd"] = "res://Workspaces/ImageWorkspace/ImageSoftenBrush.cs",

        ["res://Workspaces/ImageWorkspace/stroke_corrector.gd"] = "res://Workspaces/ImageWorkspace/KiwiStrokeCorrector.cs",

        ["res://Workspaces/ImageWorkspace/pixel_edge_field.gd"] = "res://Workspaces/ImageWorkspace/KiwiPixelEdgeField.cs",
        ["res://Workspaces/ImageWorkspace/pixel_object_segmenter.gd"] = "res://Workspaces/ImageWorkspace/KiwiPixelObjectSegmenter.cs",
        ["res://Workspaces/ImageWorkspace/pixel_edge_magnet.gd"] = "res://Workspaces/ImageWorkspace/KiwiPixelEdgeMagnet.cs",
        ["res://Workspaces/ImageWorkspace/pixel_selection_engine.gd"] = "res://Workspaces/ImageWorkspace/KiwiPixelSelectionEngine.cs",

        ["res://Workspaces/ModelWorkspace/model_selection.gd"] = "res://Workspaces/ModelWorkspace/KiwiModelSelection.cs",
        ["res://Workspaces/EnvironmentWorkspace/world/road_follow.gd"] = "res://Workspaces/EnvironmentWorkspace/world/RoadFollow.cs",
        ["res://Workspaces/EnvironmentWorkspace/world/world_building_massing.gd"] = "res://Workspaces/EnvironmentWorkspace/world/WorldBuildingMassingApi.cs",
        ["res://Workspaces/EnvironmentWorkspace/world/world_mesh_stamp.gd"] = "res://Workspaces/EnvironmentWorkspace/world/WorldMeshStamp.cs",
        ["res://Workspaces/EnvironmentWorkspace/world/world_seed.gd"] = "res://Workspaces/EnvironmentWorkspace/world/WorldSeed.cs",
        ["res://Workspaces/EnvironmentWorkspace/environment_world_override.gd"] = "res://Workspaces/EnvironmentWorkspace/EnvironmentWorldOverrideApi.cs",
        ["res://Workspaces/EnvironmentWorkspace/terrain/terrain_lod.gd"] = "res://Workspaces/EnvironmentWorkspace/terrain/TerrainLod.cs",
        ["res://Workspaces/EnvironmentWorkspace/terrain/terrain_waterfall_render.gd"] = "res://Workspaces/EnvironmentWorkspace/terrain/TerrainWaterfallApi.cs",
        ["res://Workspaces/EnvironmentWorkspace/terrain/environment_water_render.gd"] = "res://Workspaces/EnvironmentWorkspace/terrain/EnvironmentWaterApi.cs",
        ["res://Workspaces/ImageWorkspace/image_pattern_fill.gd"] = "res://Workspaces/ImageWorkspace/ImagePatternFill.cs",
        ["res://Workspaces/ImageWorkspace/image_live_eraser.gd"] = "res://Workspaces/ImageWorkspace/ImageLiveEraser.cs",

        ["res://Workspaces/SceneWorkspace/scripts/Timeline/actor_picker.gd"] = "res://Workspaces/SceneWorkspace/scripts/Timeline/ActorPicker.cs",
        ["res://Workspaces/SceneWorkspace/scripts/Timeline/actor_natural_material_editor.gd"] = "res://Workspaces/SceneWorkspace/scripts/Timeline/ActorNaturalMaterialEditor.cs",

        ["res://Workspaces/AudioWorkspace/audio_jobs.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioJobs.cs",
        ["res://Workspaces/AudioWorkspace/audio_source_cache.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioSourceCache.cs",

        ["res://Workspaces/AudioWorkspace/audio_file_preview.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioFilePreview.cs",
        ["res://Workspaces/AudioWorkspace/audio_tempo_map.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioTempoMap.cs",
        ["res://Workspaces/AudioWorkspace/audio_conductor.gd"] = "res://Workspaces/AudioWorkspace/KiwiAudioConductor.cs",

        ["res://scripts/Extra/editor_settings_button.gd"] = "res://scripts/Extra/RecordingOptionsButton.cs",
        ["res://scripts/Extra/screen_record_options.gd"] = "res://scripts/Extra/ScreenRecordingOptionsButton.cs",
        ["res://Workspaces/SceneWorkspace/scripts/Timeline/live_color_picker.gd"] = "res://Workspaces/SceneWorkspace/scripts/Timeline/LiveColorPickerButton.cs",
        ["res://Workspaces/SceneWorkspace/scripts/Timeline/drag_number.gd"] = "res://Workspaces/SceneWorkspace/scripts/Timeline/DragNumber.cs",
        ["res://CustomNodes/FileSystem/file_system_key_inputs.gd"] = "res://scripts/Globals/ProjectFileSystemKeyInput.cs",
        ["res://Workspaces/SceneWorkspace/scripts/Viewport/viewport_focusable_key_input.gd"] = "res://Workspaces/SceneWorkspace/scripts/Viewport/ViewportFocusableKeyInput.cs",
        ["res://CustomNodes/Freecam/Freecam.gd"] = "res://scripts/Extra/FreecamController.cs",
        ["res://scripts/Extra/focusable_key_input.gd"] = "res://scripts/Extra/FocusableKeyInput.cs",
        ["res://scripts/Globals/node_operations.gd"] = "res://scripts/Globals/NodeOperations.cs",
        ["res://CustomNodes/FileSystem/project_file_drag_button.gd"] = "res://scripts/Globals/ProjectFileDragButton.cs",
        ["res://CustomNodes/FileSystem/FileActionDialogue/file_action_dialogue.gd"] = "res://scripts/Extra/FileActionDialogueControl.cs",
        ["res://scripts/Extra/DialogParamChooser/dialog_param_chooser.gd"] = "res://scripts/Extra/DialogParamChooser/DialogParamChooser.cs",
        ["res://CustomNodes/FileSystem/FileActionDialogue/file_action_panel.gd"] = "res://scripts/Extra/FileActionPanelControl.cs",
        ["res://CustomNodes/ExpandableButton/expandable_button.gd"] = "res://scripts/Extra/ExpandableButtonControl.cs",
        ["res://scripts/Extra/cute_condition.gd"] = "res://scripts/Extra/CuteCondition.cs",
        ["res://Workspaces/EnvironmentWorkspace/timeline_material_link.gd"] = "res://Workspaces/EnvironmentWorkspace/TimelineMaterialBinding.cs",
        ["res://Workspaces/EnvironmentWorkspace/world/world_source.gd"] = "res://Workspaces/EnvironmentWorkspace/world/WorldSource.cs",
        ["res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd"] = "res://Workspaces/EnvironmentWorkspace/architecture/BuildingSource.cs",
        ["res://Workspaces/EnvironmentWorkspace/terrain/terrain_cave.gd"] = "res://Workspaces/EnvironmentWorkspace/terrain/KiwiTerrainCave.cs",
        ["res://scripts/actors/core/actor_registry.gd"] = "res://scripts/actors/core/ActorRegistry.cs",
        ["res://scripts/actors/core/actor_catalog.gd"] = "res://scripts/actors/core/ActorCatalog.cs",
        ["res://scripts/actors/core/actor_definition.gd"] = "res://scripts/actors/core/ActorDefinition.cs",
        ["res://Workspaces/ModelWorkspace/growth/growth_style.gd"] = "res://Workspaces/ModelWorkspace/growth/KiwiGrowthStyle.cs",
        ["res://Workspaces/ModelWorkspace/growth/growth_material.gd"] = "res://Workspaces/ModelWorkspace/growth/KiwiGrowthMaterial.cs",
        ["res://Workspaces/ModelWorkspace/growth/surface_growth_data.gd"] = "res://Workspaces/ModelWorkspace/growth/KiwiSurfaceGrowthData.cs",
        ["res://Workspaces/EnvironmentWorkspace/environment_climate.gd"] = "res://Workspaces/EnvironmentWorkspace/EnvironmentClimate.cs",
        ["res://Workspaces/EnvironmentWorkspace/environment_document.gd"] = "res://Workspaces/EnvironmentWorkspace/KiwiEnvironmentDocument.cs",
        ["res://Workspaces/ModelWorkspace/model_document.gd"] = "res://Workspaces/ModelWorkspace/KiwiModelDocument.cs",
        ["res://Workspaces/ModelWorkspace/model_component.gd"] = "res://Workspaces/ModelWorkspace/KiwiModelComponent.cs",
        ["res://Workspaces/ModelWorkspace/rig/rig_binding.gd"] = "res://Workspaces/ModelWorkspace/rig/KiwiRigBinding.cs",
        ["res://Workspaces/ModelWorkspace/model_mesh.gd"] = "res://Workspaces/ModelWorkspace/KiwiModelMesh.cs",
        ["res://scripts/actors/physics/destruction/physics_bake_cache.gd"] = "res://scripts/actors/physics/destruction/KiwiPhysicsBakeCache.cs",
        ["res://scripts/materials/natural_material_definitions.gd"] = "res://scripts/materials/NaturalMaterialCatalog.cs",
        ["res://Workspaces/TransformationWorkspace/transformation_document.gd"] = "res://Workspaces/TransformationWorkspace/KiwiTransformationImage2D.cs",
        ["res://Workspaces/TransformationWorkspace/transformation_component.gd"] = "res://Workspaces/TransformationWorkspace/KiwiTransformationComponent.cs",
        ["res://Workspaces/TransformationWorkspace/transformation_key.gd"] = "res://Workspaces/TransformationWorkspace/KiwiTransformationKey.cs",
        ["res://Workspaces/TransformationWorkspace/transformation_state.gd"] = "res://Workspaces/TransformationWorkspace/KiwiTransformationState.cs",
        ["res://Workspaces/ImageWorkspace/image_document.gd"] = "res://Workspaces/ImageWorkspace/KiwiImageDocument.cs",
        ["res://Workspaces/ImageWorkspace/image_layer.gd"] = "res://Workspaces/ImageWorkspace/KiwiImageLayer.cs",
        ["res://Workspaces/ImageWorkspace/image_warp_data.gd"] = "res://Workspaces/ImageWorkspace/KiwiImageWarpData.cs",
        ["res://Workspaces/ImageWorkspace/live_material_template.gd"] = "res://Workspaces/ImageWorkspace/KiwiLiveMaterialTemplate.cs",
        ["res://Workspaces/ImageWorkspace/live_paint_region.gd"] = "res://Workspaces/ImageWorkspace/KiwiLivePaintRegion.cs",
        ["res://Workspaces/ImageWorkspace/texture_material.gd"] = "res://Workspaces/ImageWorkspace/KiwiTextureMaterial.cs",
        ["res://Workspaces/ImageWorkspace/image_pattern_preset.gd"] = "res://Workspaces/ImageWorkspace/KiwiImagePatternPreset.cs",
        ["res://Workspaces/ImageWorkspace/image_texture_recipe.gd"] = "res://Workspaces/ImageWorkspace/KiwiImageTextureRecipe.cs",
        ["res://scripts/resources/Project.gd"] = "res://scripts/resources/Project.cs",
        ["res://scripts/actors/core/actor_object_definition.gd"] = "res://scripts/actors/core/ActorObjectDefinition.cs",
        ["res://scripts/actors/core/actor_property.gd"] = "res://scripts/actors/core/ActorProperty.cs",
        ["res://scripts/actors/core/actor_object_reference.gd"] = "res://scripts/actors/core/ActorObjectReference.cs",
        ["res://scripts/actors/core/actor_scene_data.gd"] = "res://scripts/actors/core/ActorSceneData.cs",
        ["res://scripts/actors/core/actor_object_data.gd"] = "res://scripts/actors/core/ActorObjectData.cs",
        ["res://scripts/actors/core/actor_data.gd"] = "res://scripts/actors/core/ActorData.cs",
        ["res://scripts/actors/core/actor_keyframe.gd"] = "res://scripts/actors/core/ActorKeyframe.cs",
        ["res://scripts/actors/core/actor_animation_track.gd"] = "res://scripts/actors/core/ActorAnimationTrack.cs",
        ["res://scripts/actors/core/actor_clip.gd"] = "res://scripts/actors/core/ActorClip.cs",
        ["res://scripts/actors/core/actor_inspector_state.gd"] = "res://scripts/actors/core/ActorInspectorState.cs",
        ["res://scripts/actors/core/actor_section.gd"] = "res://scripts/actors/core/ActorSection.cs",
        ["res://scripts/Extra/DialogParamChooser/dialog_param_chooser_mapping.gd"] = "res://scripts/Extra/DialogParamChooser/DialogParamChooserMapping.cs",
        ["res://scripts/resources/ProjectManagerSavedProjects.gd"] = "res://scripts/resources/ProjectManagerSavedProjects.cs",
        ["res://Workspaces/CompositingWorkspace/composite_graph_connection.gd"] = "res://Workspaces/CompositingWorkspace/CompositeGraphConnection.cs",
        ["res://Workspaces/CompositingWorkspace/composite_graph_node.gd"] = "res://Workspaces/CompositingWorkspace/CompositeGraphNode.cs",
        ["res://Workspaces/CompositingWorkspace/composite_graph.gd"] = "res://Workspaces/CompositingWorkspace/CompositeGraph.cs",
        ["res://Workspaces/CompositingWorkspace/composite_layer.gd"] = "res://Workspaces/CompositingWorkspace/CompositeLayer.cs",
        ["res://Workspaces/CompositingWorkspace/compositing_document.gd"] = "res://Workspaces/CompositingWorkspace/CompositingDocument.cs",
        ["res://Workspaces/ModelWorkspace/rig/rig_preset.gd"] = "res://Workspaces/ModelWorkspace/rig/RigPreset.cs"
    };
    // Godot binary resources resolve external dependencies through their saved
    // UID before falling back to the textual path. Keep those script IDs valid
    // when their GDScript declarations are retired, including compressed .res.
    private static readonly Dictionary<string, string> LegacyScriptUids = new()
    {
        ["uid://dtebd6myjq50t"] = "res://scripts/Extra/RecordingOptionsButton.cs",
        ["uid://cyim7vav4ykbb"] = "res://scripts/Extra/ScreenRecordingOptionsButton.cs",
        ["uid://dvfrqtcauy42f"] = "res://Workspaces/AudioWorkspace/KiwiAudioTempoMap.cs",
        ["uid://vy3qwl0wqdwt"] = "res://Workspaces/AudioWorkspace/KiwiAudioConductor.cs",
        ["uid://bt1lyl8qu7caa"] = "res://Workspaces/AudioWorkspace/KiwiAudioFilePreview.cs",
        ["uid://d4aydrpi2ouuj"] = "res://Workspaces/AudioWorkspace/KiwiAudioJobs.cs",
        ["uid://u7vtq2pmerga"] = "res://Workspaces/AudioWorkspace/KiwiAudioSourceCache.cs",
        ["uid://bfgqpjmqple6"] = "res://Workspaces/SceneWorkspace/scripts/Timeline/ActorPicker.cs",
        ["uid://d1y4akbvd2q37"] = "res://Workspaces/SceneWorkspace/scripts/Timeline/ActorNaturalMaterialEditor.cs",
        ["uid://cplevefxonxh3"] = "res://Workspaces/ModelWorkspace/KiwiModelSelection.cs",
        ["uid://w0hd3kmifdpm"] = "res://Workspaces/EnvironmentWorkspace/world/RoadFollow.cs",
        ["uid://d36vmxi8f87nf"] = "res://Workspaces/EnvironmentWorkspace/world/WorldBuildingMassingApi.cs",
        ["uid://cyat1rphor0wk"] = "res://Workspaces/EnvironmentWorkspace/world/WorldMeshStamp.cs",
        ["uid://bpqi2ym6e73l5"] = "res://Workspaces/EnvironmentWorkspace/world/WorldSeed.cs",
        ["uid://d013rj08xic5e"] = "res://Workspaces/EnvironmentWorkspace/EnvironmentWorldOverrideApi.cs",
        ["uid://wp15ipwm8ygn"] = "res://Workspaces/EnvironmentWorkspace/terrain/TerrainLod.cs",
        ["uid://dv8i3lln181g0"] = "res://Workspaces/EnvironmentWorkspace/terrain/TerrainWaterfallApi.cs",
        ["uid://bp16ghbsino7h"] = "res://Workspaces/EnvironmentWorkspace/terrain/EnvironmentWaterApi.cs",
        ["uid://dctpbbbj13bhu"] = "res://Workspaces/ImageWorkspace/ImagePatternFill.cs",
        ["uid://bmtu0cym46xje"] = "res://Workspaces/ImageWorkspace/ImageLiveEraser.cs",
        ["uid://qgy2lt2n6yw6"] = "res://Workspaces/ImageWorkspace/KiwiPixelEdgeField.cs",
        ["uid://bwao1klgf1nn7"] = "res://Workspaces/ImageWorkspace/KiwiPixelObjectSegmenter.cs",
        ["uid://clyovbgjeq1dm"] = "res://Workspaces/ImageWorkspace/KiwiPixelEdgeMagnet.cs",
        ["uid://2gy57isl5iqr"] = "res://Workspaces/ImageWorkspace/KiwiPixelSelectionEngine.cs",
        ["uid://cfnpsxxoox4f1"] = "res://Workspaces/ImageWorkspace/KiwiStrokeCorrector.cs",
        ["uid://cd454sx5dki0j"] = "res://Workspaces/ImageWorkspace/PixelSelectionAlpha.cs",
        ["uid://dp4h1t2nx07ul"] = "res://Workspaces/ImageWorkspace/ImageSoftenBrush.cs",
        ["uid://23huxkdt7hm1"] = "res://scripts/actors/core/ActorShaderTime.cs",
        ["uid://bgrxnrhv1qi5q"] = "res://scripts/actors/core/ActorImageGenerator.cs",
        ["uid://dqrq88rdcisna"] = "res://scripts/actors/core/ActorSkeletonPose.cs",
        ["uid://darlr8cyfekd6"] = "res://scripts/actors/physics/destruction/DestructionMaterialControl.cs",
        ["uid://ctkc3e0jrin03"] = "res://scripts/actors/physics/destruction/DestructionControl.cs",
        ["uid://b7w6lggif6qf6"] = "res://scripts/actors/physics/powder/PowderMaterialControl.cs",
        ["uid://dy7cgo7icixnt"] = "res://scripts/actors/physics/structure/StructureControl.cs",
        ["uid://bnsm35fv3egjy"] = "res://scripts/actors/core/ActorResourceSlot.cs",
        ["uid://c2kmjchhfgb33"] = "res://scripts/actors/core/ActorTextSettings.cs",
        ["uid://nfsmtkrdvjl4"] = "res://scripts/actors/core/EditorAudioSettings.cs",
        ["uid://eiafbqde8c5b"] = "res://scripts/actors/core/ActorFontPicker.cs",
        ["uid://ca6d0m17h8k1k"] = "res://scripts/actors/core/ActorDimensionDialog.cs",
        ["uid://754kfetw58o2"] = "res://scripts/actors/core/ActorMediaPreview.cs",
        ["uid://bx5coxioqcs35"] = "res://Workspaces/ImageWorkspace/ImageOperationPreview.cs",
        ["uid://0xcn0tow73hf"] = "res://scripts/actors/core/ActorVideo.cs",
        ["uid://chygh5pmj073u"] = "res://scripts/actors/core/ActorAudioSystem.cs",
        ["uid://dkomqdws726wo"] = "res://Workspaces/AudioWorkspace/KiwiAudioPlayback.cs",
        ["uid://c40qr1mibn2p0"] = "res://scripts/actors/core/ActorAudio.cs",
        ["uid://b4nqmllw5lv4v"] = "res://scripts/actors/core/ActorAnimation.cs",
        ["uid://dq1glsdf5883y"] = "res://scripts/actors/core/ActorTransformationStates.cs",
        ["uid://d3iu30dt85ncm"] = "res://scripts/actors/core/ActorPropertyBatch.cs",
        ["uid://51eloaq76rek"] = "res://scripts/actors/core/ActorFileImport.cs",
        ["uid://gosodii0yi0o"] = "res://scripts/actors/core/ActorRuntime.cs",
        ["uid://ebkbfnhmp5al"] = "res://scripts/actors/examples/BasicActorRuntime.cs",
        ["uid://bql7dx6qyxvms"] = "res://scripts/actors/examples/PointActorRuntime.cs",
        ["uid://dgo5msednxhsa"] = "res://scripts/actors/examples/VideoActorRuntime.cs",
        ["uid://dhyc3fm2cv3nq"] = "res://scripts/actors/examples/ActorUIRuntime.cs",
        ["uid://cnefaawd846yl"] = "res://scripts/actors/examples/ActorSkeletonRigRuntime.cs",
        ["uid://bgmgm07cx7rb5"] = "res://scripts/actors/examples/ActorTransformImage2DRuntime.cs",
        ["uid://2iws82oj67iw"] = "res://Workspaces/EnvironmentWorkspace/EnvironmentActorRuntime.cs",
        ["uid://d2xlp8yteluy8"] = "res://scripts/actors/physics/powder/KiwiPowderRuntime.cs",
        ["uid://br4ub4w2vtag4"] = "res://scripts/actors/physics/fluid/KiwiFluidRuntime.cs",
        ["uid://d0b8425a2fv08"] = "res://scripts/actors/core/KiwiAudioEncoderProcess.cs",
        ["uid://cgfll73l8gr02"] = "res://Workspaces/AudioWorkspace/KiwiAudioImpulse.cs",
        ["uid://dbc1qhj2hir8t"] = "res://Workspaces/AudioWorkspace/AudioConductorFit.cs",
        ["uid://bypqdu6x1nnye"] = "res://Workspaces/AudioWorkspace/AudioModulationMatrix.cs",
        ["uid://bngug685ejm0e"] = "res://scripts/actors/core/ActorUIGizmo.cs",
        ["uid://cc5apknsmo2wh"] = "res://scripts/actors/core/ActorSpatialGizmo.cs",
        ["uid://bnc64p4438owk"] = "res://scripts/actors/core/ActorSkeletonGizmo.cs",
        ["uid://cy7151xbq5wm1"] = "res://scripts/actors/physics/PhysicsPinGizmo.cs",
        ["uid://di2wxdi3goc20"] = "res://scripts/actors/physics/destruction/DestructionGizmo.cs",
        ["uid://ct36t66ursawi"] = "res://scripts/actors/physics/structure/StructureGizmo.cs",
        ["uid://dk2oi201lmdq8"] = "res://scripts/actors/fog/FogPaintGizmo.cs",
        ["uid://dtqxkpl4bbd6j"] = "res://scripts/actors/core/ActorAudioRecorder.cs",
        ["uid://cd6u6htds3avq"] = "res://scripts/actors/core/ActorScreenRecorder.cs",
        ["uid://d03e0ctsldh2h"] = "res://Workspaces/AudioWorkspace/KiwiAudioDoppler.cs",
        ["uid://exos63hcbmqk"] = "res://Workspaces/AudioWorkspace/AudioOptionalProcess.cs",
        ["uid://k00p1jcwsdjy"] = "res://Workspaces/AudioWorkspace/AudioGroupFreeze.cs",
        ["uid://ddbv8qtkhu4m0"] = "res://Workspaces/AudioWorkspace/AudioLayerBundle.cs",
        ["uid://bjf2xjc8x76ce"] = "res://Workspaces/AudioWorkspace/AudioTranscription.cs",
        ["uid://behb8neiwcl34"] = "res://Workspaces/AudioWorkspace/KiwiAudioDocument.cs",
        ["uid://cckc25qcjxlc6"] = "res://Workspaces/AudioWorkspace/KiwiAudioPortableCopy.cs",
        ["uid://dop3qnktpy2rs"] = "res://Workspaces/AudioWorkspace/KiwiAudioEditSession.cs",
        ["uid://dpgnnsqqdtva7"] = "res://Workspaces/AudioWorkspace/KiwiAudioPreset.cs",
        ["uid://c18k08toecx6p"] = "res://Workspaces/AudioWorkspace/AudioPresetStore.cs",
        ["uid://bhyfec6hekfeq"] = "res://Workspaces/AudioWorkspace/KiwiAudioLibrary.cs",
        ["uid://cg8hb736mlfvs"] = "res://Workspaces/AudioWorkspace/KiwiAudioAssetIndex.cs",
        ["uid://idqnerab7l4k"] = "res://Workspaces/AudioWorkspace/KiwiAudioTemplates.cs",
        ["uid://dexdvkxyccxrh"] = "res://Workspaces/AudioWorkspace/KiwiAudioInstruments.cs",
        ["uid://uup1jlbea3ww"] = "res://scripts/actors/core/WindowsSystemAudio.cs",
        ["uid://cmpaw5aulb10t"] = "res://scripts/actors/core/ActorTimeline.cs",
        ["uid://dog348mu505bf"] = "res://scripts/actors/core/NativeAudioTakeWriter.cs",
        ["uid://de0x4i5k2u2if"] = "res://Workspaces/SceneWorkspace/scripts/Timeline/LiveColorPickerButton.cs",
        ["uid://b1fx1jbvcufnt"] = "res://Workspaces/SceneWorkspace/scripts/Timeline/DragNumber.cs",
        ["uid://5b3es4pagcpo"] = "res://scripts/Globals/ProjectFileSystemKeyInput.cs",
        ["uid://cbpyo2oo61yst"] = "res://Workspaces/SceneWorkspace/scripts/Viewport/ViewportFocusableKeyInput.cs",
        ["uid://65nr6lacg13d"] = "res://scripts/Extra/FreecamController.cs",
        ["uid://cmdm1scp2dcrx"] = "res://scripts/Extra/FocusableKeyInput.cs",
        ["uid://461gor1wtmnb"] = "res://scripts/Globals/NodeOperations.cs",
        ["uid://dorqj5j2np3b7"] = "res://scripts/Globals/ProjectFileDragButton.cs",
        ["uid://c0ohimns5kdk7"] = "res://scripts/Extra/FileActionDialogueControl.cs",
        ["uid://cpbb83r3o2iah"] = "res://scripts/Extra/DialogParamChooser/DialogParamChooser.cs",
        ["uid://b7rja2mjbms6m"] = "res://scripts/Extra/FileActionPanelControl.cs",
        ["uid://dk22ixmn3cmrb"] = "res://scripts/Extra/ExpandableButtonControl.cs",
        ["uid://6s31sd2buphd"] = "res://scripts/Extra/CuteCondition.cs",
        ["uid://cm1ud4kqnttfb"] = "res://Workspaces/EnvironmentWorkspace/TimelineMaterialBinding.cs",
        ["uid://bvelm32ww0est"] = "res://Workspaces/EnvironmentWorkspace/world/WorldSource.cs",
        ["uid://4xtl6s5rl184"] = "res://Workspaces/EnvironmentWorkspace/architecture/BuildingSource.cs",
        ["uid://tgpf7jewdw8t"] = "res://Workspaces/EnvironmentWorkspace/terrain/KiwiTerrainCave.cs",
        ["uid://dsx4rkddg0igc"] = "res://scripts/actors/core/ActorRegistry.cs",
        ["uid://fca57ycc0nxh"] = "res://scripts/actors/core/ActorCatalog.cs",
        ["uid://cfphk6n07ph5o"] = "res://scripts/actors/core/ActorDefinition.cs",
        ["uid://ber3vk6jeg3pn"] = "res://Workspaces/ModelWorkspace/growth/KiwiGrowthStyle.cs",
        ["uid://dmfqrjopakn33"] = "res://Workspaces/ModelWorkspace/growth/KiwiGrowthMaterial.cs",
        ["uid://6u677c6fqpuu"] = "res://Workspaces/ModelWorkspace/growth/KiwiSurfaceGrowthData.cs",
        ["uid://6tcgjat3ueue"] = "res://Workspaces/EnvironmentWorkspace/EnvironmentClimate.cs",
        ["uid://dqnnk0yxf28fd"] = "res://Workspaces/EnvironmentWorkspace/KiwiEnvironmentDocument.cs",
        ["uid://bl6p51q7jtcwv"] = "res://Workspaces/ModelWorkspace/KiwiModelDocument.cs",
        ["uid://dyu2bglnyr14k"] = "res://Workspaces/ModelWorkspace/KiwiModelComponent.cs",
        ["uid://cesspqomc4utl"] = "res://Workspaces/ModelWorkspace/rig/KiwiRigBinding.cs",
        ["uid://7pfmqla4nc8p"] = "res://Workspaces/ModelWorkspace/KiwiModelMesh.cs",
        ["uid://bhf0sff881ik8"] = "res://scripts/actors/physics/destruction/KiwiPhysicsBakeCache.cs",
        ["uid://cv7twlvy8o1j8"] = "res://scripts/materials/NaturalMaterialCatalog.cs",
        ["uid://cg6g62f8p4mgw"] = "res://Workspaces/TransformationWorkspace/KiwiTransformationImage2D.cs",
        ["uid://bn6g34wrs6hpt"] = "res://Workspaces/TransformationWorkspace/KiwiTransformationComponent.cs",
        ["uid://cpk4i3xyfnh55"] = "res://Workspaces/TransformationWorkspace/KiwiTransformationKey.cs",
        ["uid://cqqekm0eakuoe"] = "res://Workspaces/TransformationWorkspace/KiwiTransformationState.cs",
        ["uid://ry7x3rcg4ef"] = "res://Workspaces/ImageWorkspace/KiwiImageDocument.cs",
        ["uid://cs0drsjkh26r7"] = "res://Workspaces/ImageWorkspace/KiwiImageLayer.cs",
        ["uid://bgsli00o3x73c"] = "res://Workspaces/ImageWorkspace/KiwiImageWarpData.cs",
        ["uid://c42aao70grb3i"] = "res://Workspaces/ImageWorkspace/KiwiLiveMaterialTemplate.cs",
        ["uid://cr5jiqkbmxfnd"] = "res://Workspaces/ImageWorkspace/KiwiLivePaintRegion.cs",
        ["uid://bgctpifix6uht"] = "res://Workspaces/ImageWorkspace/KiwiTextureMaterial.cs",
        ["uid://c1jsrb78i436g"] = "res://Workspaces/ImageWorkspace/KiwiImagePatternPreset.cs",
        ["uid://j2ecsylwlnxo"] = "res://Workspaces/ImageWorkspace/KiwiImageTextureRecipe.cs",
        ["uid://biypvu31h5nlp"] = "res://scripts/resources/Project.cs",
        ["uid://ct1qlalxsv4yb"] = "res://scripts/actors/core/ActorObjectDefinition.cs",
        ["uid://bdqg0opq1ftpj"] = "res://scripts/actors/core/ActorProperty.cs",
        ["uid://bnpoxogs6k8gh"] = "res://scripts/actors/core/ActorObjectReference.cs",
        ["uid://bl2vh1ax6s3ha"] = "res://scripts/actors/core/ActorSceneData.cs",
        ["uid://b41uoebkf51m"] = "res://scripts/actors/core/ActorObjectData.cs",
        ["uid://bfgbrxqam8mfc"] = "res://scripts/actors/core/ActorData.cs",
        ["uid://dg11tecslnp10"] = "res://scripts/actors/core/ActorKeyframe.cs",
        ["uid://dx3p205rwfb1"] = "res://scripts/actors/core/ActorAnimationTrack.cs",
        ["uid://dfyq2iv2d23mq"] = "res://scripts/resources/ProjectManagerSavedProjects.cs",
        ["uid://cbwugyqv7rtpg"] = "res://scripts/Extra/DialogParamChooser/DialogParamChooserMapping.cs",
        ["uid://bl552v83ekiyc"] = "res://scripts/actors/core/ActorSection.cs",
        ["uid://m3y8a8llh6g2"] = "res://scripts/actors/core/ActorInspectorState.cs",
        ["uid://c1vpn361k0wl7"] = "res://scripts/actors/core/ActorClip.cs"
    };
    internal static string NativeScriptPath(string path) => Replacements.TryGetValue(path, out string? native) ? native : path;
    public static void RegisterLegacyUids()
    {
        foreach (var entry in LegacyScriptUids)
        {
            long id = ResourceUid.TextToId(entry.Key);
            if (ResourceUid.HasId(id)) ResourceUid.SetId(id, entry.Value);
            else ResourceUid.AddId(id, entry.Value);
        }
    }
    public override string[] _GetRecognizedExtensions() => new[] { "tres" };
    public override bool _HandlesType(StringName type) => true;
    public override string _GetResourceType(string path) => _RecognizePath(path, "") ? "Resource" : "";
    public override bool _RecognizePath(string path, StringName type)
    {
        if (!path.EndsWith(".tres", StringComparison.OrdinalIgnoreCase) || !Godot.FileAccess.FileExists(path)) return false;
        using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
        if (file == null) return false;
        string contents = file.GetAsText();
        foreach (Match declaration in Regex.Matches(contents, @"\[ext_resource[^\r\n]*\]"))
            if (Replacements.Keys.Any(legacy => declaration.Value.Contains("path=\"" + legacy + "\"", StringComparison.Ordinal))) return true;
        return false;
    }

    public override Variant _Load(string path, string originalPath, bool useSubThreads, int cacheMode)
    {
        using var file = Godot.FileAccess.Open(path, Godot.FileAccess.ModeFlags.Read);
        if (file == null) return (int)Error.FileCantOpen;
        string text = file.GetAsText();
        text = Regex.Replace(text, @"\[ext_resource[^\r\n]*\]", match =>
        {
            string line = match.Value;
            bool remapped = false;
            foreach (var replacement in Replacements)
                if (line.Contains("path=\"" + replacement.Key + "\"", StringComparison.Ordinal)) { line = line.Replace("path=\"" + replacement.Key + "\"", "path=\"" + replacement.Value + "\""); remapped = true; }
            if (remapped) line = Regex.Replace(line, " uid=\"[^\"]*\"", "");
            return Regex.Replace(line, "path=\"([^\"]+)\"", reference =>
            {
                string value = reference.Groups[1].Value;
                if (value.Contains("://", StringComparison.Ordinal) || System.IO.Path.IsPathRooted(value)) return reference.Value;
                string absolute = System.IO.Path.GetFullPath(ProjectSettings.GlobalizePath(path.GetBaseDir().PathJoin(value))).Replace('\\', '/');
                return "path=\"" + absolute + "\"";
            });
        });
        string directory = OS.HasFeature("editor") ? "res://.godot/migration" : "user://csharp_resource_migration";
        if (DirAccess.MakeDirRecursiveAbsolute(ProjectSettings.GlobalizePath(directory)) != Error.Ok) return (int)Error.CantCreate;
        string hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(path + "\n" + text)));
        string temporary = directory.PathJoin(hash + ".tres");
        using (var output = Godot.FileAccess.Open(temporary, Godot.FileAccess.ModeFlags.Write))
        {
            if (output == null) return (int)Error.FileCantWrite;
            output.StoreString(text);
        }
        var resource = ResourceLoader.Load<Resource>(temporary, "", ResourceLoader.CacheMode.Ignore);
        if (resource == null) return (int)Error.FileCorrupt;
        resource.TakeOverPath(originalPath.Length > 0 ? originalPath : path);
        return resource;
    }
}
