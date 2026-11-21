class_name ShaderDocumentationPopup
extends PopupPanel
## Searchable shader reference with copyable, ready-to-use examples.

signal sample_open_requested(entry: Dictionary)
const SampleBrowser = preload("res://Workspaces/ShaderWorkspace/shader_sample_browser.gd")
var sections := TabBar.new()
var documentation_body: Control
var sample_browser: Control
var _page_root: VBoxContainer

const ACCENT := Color("62e6c7")
const ACCENT_SOFT := Color("203f42")
const TEXT := Color("e8f0f5")
const MUTED := Color("91a6b5")
const SURFACE := Color("111923")
const SURFACE_RAISED := Color("182431")
const BORDER := Color("2c4252")

const TOPICS: Array[Dictionary] = [
	{
		"category": "PROCESSORS", "title": "Spatial vertex()", "tag": "SPATIAL",
		"summary": "Runs once for every mesh vertex before rasterization and may change geometry, normals, UVs and point size.",
		"body": "Key inputs: VERTEX, NORMAL, TANGENT, BINORMAL, UV, UV2, COLOR, INSTANCE_ID, INSTANCE_CUSTOM and BONE_INDICES/WEIGHTS. Key writable values: VERTEX, NORMAL, TANGENT, BINORMAL, POSITION, ROUGHNESS and POINT_SIZE. MODEL_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX and their inverse forms are available for coordinate conversion. Writing POSITION bypasses the default projection transform.",
		"code": "void vertex() {\n    // VERTEX/NORMAL are model-space unless render modes change them.\n    VERTEX.y += sin(VERTEX.x * 6.0 + TIME) * 0.08;\n    // POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);\n}"
	},
	{
		"category": "PROCESSORS", "title": "Spatial fragment()", "tag": "SPATIAL",
		"summary": "Runs for each covered fragment and defines the material values consumed by Godot's lighting pipeline.",
		"body": "Inputs include FRAGCOORD, FRONT_FACING, VIEW, UV/UV2, COLOR, NORMAL, TANGENT, BINORMAL, VERTEX, SCREEN_UV and POINT_COORD. The main outputs are ALBEDO, ALPHA, METALLIC, SPECULAR, ROUGHNESS, EMISSION, NORMAL_MAP, NORMAL_MAP_DEPTH, AO, AO_LIGHT_AFFECT, RIM, RIM_TINT, CLEARCOAT, CLEARCOAT_ROUGHNESS, ANISOTROPY, ANISOTROPY_FLOW and DEPTH. Writing ALPHA moves the material into the transparent pipeline; ALPHA_SCISSOR_THRESHOLD performs opaque cutout instead.",
		"code": "void fragment() {\n    ALBEDO = vec3(0.18, 0.55, 0.82);\n    METALLIC = 0.0;\n    ROUGHNESS = 0.65;\n    SPECULAR = 0.5;\n    EMISSION = vec3(0.0);\n}"
	},
	{
		"category": "PROCESSORS", "title": "Spatial light()", "tag": "SPATIAL",
		"summary": "Runs once per affecting light, after fragment(), and replaces the built-in diffuse/specular light calculation.",
		"body": "Inputs include NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, ALBEDO, ROUGHNESS, METALLIC, SPECULAR and BACKLIGHT. LIGHT is the surface-to-light direction in view space. ATTENUATION combines distance, shadow and projector attenuation. Accumulate into DIFFUSE_LIGHT and SPECULAR_LIGHT with += because the function executes for every light.",
		"code": "void light() {\n    float n_dot_l = max(dot(NORMAL, LIGHT), 0.0);\n    DIFFUSE_LIGHT += n_dot_l * ATTENUATION * LIGHT_COLOR * ALBEDO;\n    vec3 half_vector = normalize(LIGHT + VIEW);\n    float highlight = pow(max(dot(NORMAL, half_vector), 0.0), 32.0);\n    SPECULAR_LIGHT += highlight * ATTENUATION * LIGHT_COLOR;\n}"
	},
	{
		"category": "PROCESSORS", "title": "Canvas item functions", "tag": "2D",
		"summary": "Canvas shaders provide vertex(), fragment() and light() processors for Sprite2D, Control and other CanvasItem rendering.",
		"body": "vertex() edits VERTEX in pixel coordinates and can write UV, COLOR and POINT_SIZE. fragment() reads TEXTURE/TEXTURE_PIXEL_SIZE, UV, COLOR, SCREEN_UV and SCREEN_TEXTURE-style sampler uniforms, then writes COLOR, NORMAL and NORMAL_MAP_DEPTH. light() receives LIGHT_COLOR, LIGHT_POSITION, LIGHT_DIRECTION, LIGHT_HEIGHT, LIGHT_ENERGY, LIGHT_VERTEX, NORMAL and SHADOW_MODULATE, and writes LIGHT.",
		"code": "shader_type canvas_item;\n\nvoid vertex() {\n    VERTEX.y += sin(VERTEX.x * 0.05 + TIME) * 3.0;\n}\n\nvoid fragment() {\n    vec4 tex = texture(TEXTURE, UV);\n    COLOR = tex * COLOR;\n}"
	},
	{
		"category": "PROCESSORS", "title": "Particle functions", "tag": "PARTICLES",
		"summary": "Particle shaders use start() for initialization and process() for per-frame simulation on the GPU.",
		"body": "start() runs when a particle begins or restarts. process() advances active particles. Writable built-ins include TRANSFORM, VELOCITY, COLOR, CUSTOM, MASS and ACTIVE. Inputs include DELTA, LIFETIME, NUMBER, INDEX, EMISSION_TRANSFORM, RANDOM_SEED, RESTART and restart flags for position, rotation, velocity, color and custom data. Keep simulation deterministic by deriving randomness from RANDOM_SEED and INDEX.",
		"code": "shader_type particles;\n\nvoid start() {\n    if (RESTART_VELOCITY) {\n        VELOCITY = vec3(0.0, 2.0, 0.0);\n    }\n}\n\nvoid process() {\n    VELOCITY += vec3(0.0, -9.8, 0.0) * DELTA;\n    TRANSFORM[3].xyz += VELOCITY * DELTA;\n}"
	},
	{
		"category": "PROCESSORS", "title": "Sky functions", "tag": "SKY",
		"summary": "Sky shaders use sky() to calculate radiance for the background, reflections and ambient lighting.",
		"body": "sky() receives EYEDIR, SCREEN_UV, SKY_COORDS, POSITION, TIME and pass flags such as AT_CUBEMAP_PASS, AT_HALF_RES_PASS and AT_QUARTER_RES_PASS. LIGHT0–LIGHT3 expose enabled state, direction, energy, color, size and angular distance for directional lights affecting the sky. Write COLOR, ALPHA, FOG and optional HALF_RES_COLOR/QUARTER_RES_COLOR outputs.",
		"code": "shader_type sky;\n\nvoid sky() {\n    float horizon = pow(1.0 - abs(EYEDIR.y), 4.0);\n    vec3 zenith = vec3(0.03, 0.09, 0.2);\n    vec3 horizon_color = vec3(0.7, 0.3, 0.12);\n    COLOR = mix(zenith, horizon_color, horizon);\n}"
	},
	{
		"category": "PROCESSORS", "title": "Fog function", "tag": "FOG",
		"summary": "Fog shaders use fog() to add custom density and emission inside volumetric fog froxels.",
		"body": "fog() receives WORLD_POSITION, OBJECT_POSITION, UVW, SIZE, SDF and TIME. Write DENSITY for local fog density, ALBEDO for scattering color and EMISSION for emitted radiance. The shader is evaluated in the bounded FogVolume containing the sample; SDF is meaningful when the volume shape supplies it.",
		"code": "shader_type fog;\n\nuniform float density = 1.0;\n\nvoid fog() {\n    float wisps = sin(WORLD_POSITION.x * 2.0 + TIME) * 0.5 + 0.5;\n    DENSITY = density * wisps;\n    ALBEDO = vec3(0.65, 0.75, 0.9);\n}"
	},
	{
		"category": "BUILT-INS", "title": "Global constants and values", "tag": "ALL SHADERS",
		"summary": "Godot exposes mathematical constants, elapsed time and renderer state without uniforms.",
		"body": "PI is π, TAU is 2π and E is Euler's number. TIME is elapsed seconds and repeats according to the rollover project setting; it is affected by time scale but not pause. OUTPUT_IS_SRGB indicates whether shader output expects sRGB encoding. CLIP_SPACE_FAR is the far-plane clip-space value for the active renderer. Use global uniforms for game state instead of trying to assign these read-only values.",
		"code": "float phase = TIME * TAU;\nfloat wave = sin(phase);\nfloat exponential = pow(E, 2.0);\n\n// OUTPUT_IS_SRGB and CLIP_SPACE_FAR are renderer-dependent read-only values."
	},
	{
		"category": "BUILT-INS", "title": "Spatial matrices and camera values", "tag": "SPATIAL",
		"summary": "Built-in matrices convert between model, world, view and clip coordinate spaces.",
		"body": "MODEL_MATRIX maps model to world space. VIEW_MATRIX maps world to view space. PROJECTION_MATRIX maps view to clip space. MODELVIEW_MATRIX combines model and view and is often more stable for distant objects. INV_MODEL_MATRIX, INV_VIEW_MATRIX and INV_PROJECTION_MATRIX reverse those transforms. MODEL_NORMAL_MATRIX transforms normals to world space. CAMERA_POSITION_WORLD, CAMERA_DIRECTION_WORLD, NODE_POSITION_WORLD, VIEWPORT_SIZE, VIEW_INDEX and EYE_OFFSET describe the active view.",
		"code": "vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\nvec3 view_position = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;\nvec4 clip_position = PROJECTION_MATRIX * vec4(view_position, 1.0);\nvec3 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);"
	},
	{
		"category": "FUNCTIONS", "title": "Angle and trigonometry", "tag": "BUILT-IN FUNCTIONS",
		"summary": "Angle conversion and trigonometric functions operate component-wise on scalar or vector floating-point values.",
		"body": "radians() converts degrees to radians; degrees() does the reverse. sin(), cos() and tan() evaluate circular functions. asin(), acos() and atan() return inverse angles; atan(y, x) preserves the correct quadrant. sinh(), cosh(), tanh(), asinh(), acosh() and atanh() provide hyperbolic forms.",
		"code": "radians(degrees)  degrees(radians)\nsin(x)  cos(x)  tan(x)\nasin(x)  acos(x)  atan(y, x)\nsinh(x)  cosh(x)  tanh(x)\nasinh(x)  acosh(x)  atanh(x)"
	},
	{
		"category": "FUNCTIONS", "title": "Scalar and interpolation", "tag": "BUILT-IN FUNCTIONS",
		"summary": "These functions shape ranges, thresholds and transitions and apply component-wise to vectors.",
		"body": "pow(), exp(), exp2(), log(), log2(), sqrt() and inversesqrt() handle powers. abs(), sign(), floor(), round(), roundEven(), trunc(), ceil() and fract() transform values. mod() returns a remainder. min(), max() and clamp() constrain ranges. mix() interpolates, step() creates a hard threshold and smoothstep() creates a cubic transition. isnan() and isinf() diagnose invalid numbers; fma() performs fused multiply-add where supported.",
		"code": "pow(x, y)  exp(x)  exp2(x)  log(x)  log2(x)\nsqrt(x)  inversesqrt(x)\nabs(x)  sign(x)  floor(x)  round(x)  trunc(x)  ceil(x)  fract(x)\nmod(x, y)  min(a, b)  max(a, b)  clamp(x, low, high)\nmix(a, b, weight)  step(edge, x)  smoothstep(a, b, x)\nisnan(x)  isinf(x)  fma(a, b, c)"
	},
	{
		"category": "FUNCTIONS", "title": "Vector geometry", "tag": "BUILT-IN FUNCTIONS",
		"summary": "Geometry functions measure and transform directions without manually expanding vector math.",
		"body": "length() returns vector magnitude and distance() measures separation. dot() measures alignment. cross() returns the perpendicular vector for vec3 inputs. normalize() creates unit length. faceforward() orients a normal against an incident direction. reflect() returns a mirror direction and refract() applies Snell's law using an index-of-refraction ratio.",
		"code": "length(v)  distance(a, b)\ndot(a, b)  cross(a, b)  normalize(v)\nfaceforward(normal, incident, reference_normal)\nreflect(incident, normal)\nrefract(incident, normal, eta)"
	},
	{
		"category": "FUNCTIONS", "title": "Matrices and comparisons", "tag": "BUILT-IN FUNCTIONS",
		"summary": "Matrix helpers and component-wise relational functions cover common transform and mask operations.",
		"body": "matrixCompMult() multiplies matrices component-wise; outerProduct() builds a matrix from two vectors; transpose(), determinant() and inverse() perform their standard linear-algebra operations. lessThan(), lessThanEqual(), greaterThan(), greaterThanEqual(), equal() and notEqual() return boolean vectors. any() and all() reduce them; not() negates them.",
		"code": "matrixCompMult(a, b)  outerProduct(column, row)\ntranspose(m)  determinant(m)  inverse(m)\nlessThan(a, b)  lessThanEqual(a, b)\ngreaterThan(a, b)  greaterThanEqual(a, b)\nequal(a, b)  notEqual(a, b)  any(mask)  all(mask)  not(mask)"
	},
	{
		"category": "FUNCTIONS", "title": "Texture lookup", "tag": "BUILT-IN FUNCTIONS",
		"summary": "Texture functions query dimensions, sample filtered values or fetch exact texels and mip levels.",
		"body": "texture() performs the normal filtered lookup. textureProj() divides projected coordinates before sampling. textureLod() selects an explicit mip level, while textureGrad() supplies coordinate derivatives. texelFetch() reads an exact integer texel without filtering. textureSize() reports dimensions and textureQueryLod() reports calculated mip information. Availability varies by sampler and renderer.",
		"code": "textureSize(sampler, lod)\ntextureQueryLod(sampler, uv)\ntexture(sampler, uv [, bias])\ntextureProj(sampler, projected_uv)\ntextureLod(sampler, uv, lod)\ntextureGrad(sampler, uv, dPdx, dPdy)\ntexelFetch(sampler, integer_coord, lod)"
	},
	{
		"category": "FUNCTIONS", "title": "Derivatives and bit operations", "tag": "BUILT-IN FUNCTIONS",
		"summary": "Derivative functions inspect neighboring fragments; bit functions operate on integer representations.",
		"body": "dFdx() and dFdy() return screen-space partial derivatives, with coarse/fine variants where available. fwidth() is abs(dFdx)+abs(dFdy), useful for antialiasing procedural edges. floatBitsToInt/Uint and intBitsToFloat/uintBitsToFloat reinterpret bits. bitfieldExtract/Insert, bitfieldReverse, bitCount, findLSB and findMSB support packed integer work. Derivatives are intended for fragment processing and can be undefined across non-uniform control flow.",
		"code": "dFdx(value)  dFdy(value)  fwidth(value)\ndFdxCoarse(value)  dFdyCoarse(value)  fwidthCoarse(value)\ndFdxFine(value)  dFdyFine(value)  fwidthFine(value)\nfloatBitsToInt(x)  floatBitsToUint(x)  intBitsToFloat(x)  uintBitsToFloat(x)\nbitfieldExtract(value, offset, bits)  bitfieldInsert(base, insert, offset, bits)\nbitfieldReverse(x)  bitCount(x)  findLSB(x)  findMSB(x)"
	},
	{
		"category": "SURFACES", "title": "Albedo map", "tag": "TEXTURE",
		"summary": "Sample a color texture and multiply it by a tint.",
		"body": "Mark color textures with source_color. This ensures authored sRGB colors are converted correctly before lighting.",
		"code": "uniform sampler2D albedo_map : source_color;\nuniform vec4 albedo_tint : source_color = vec4(1.0);\n\nvoid fragment() {\n    vec4 sampled = texture(albedo_map, UV);\n    ALBEDO = sampled.rgb * albedo_tint.rgb;\n    ALPHA = sampled.a * albedo_tint.a;\n}"
	},
	{
		"category": "SURFACES", "title": "Normal map", "tag": "TEXTURE",
		"summary": "Add small surface detail without increasing geometry.",
		"body": "Use hint_normal so Godot imports and samples the texture correctly. NORMAL_MAP_DEPTH controls the apparent strength.",
		"code": "uniform sampler2D normal_map : hint_normal;\nuniform float normal_strength : hint_range(0.0, 4.0) = 1.0;\n\nvoid fragment() {\n    NORMAL_MAP = texture(normal_map, UV).rgb;\n    NORMAL_MAP_DEPTH = normal_strength;\n}"
	},
	{
		"category": "SURFACES", "title": "PBR maps", "tag": "MATERIAL",
		"summary": "Drive metallic, roughness and specular response from textures.",
		"body": "METALLIC describes whether the surface behaves like metal. ROUGHNESS controls reflection blur. SPECULAR adjusts dielectric reflectance and is usually kept near 0.5.",
		"code": "uniform sampler2D metallic_map : hint_default_black;\nuniform sampler2D roughness_map : hint_roughness_r;\nuniform sampler2D specular_map : hint_default_white;\n\nvoid fragment() {\n    METALLIC = texture(metallic_map, UV).r;\n    ROUGHNESS = texture(roughness_map, UV).r;\n    SPECULAR = texture(specular_map, UV).r * 0.5;\n}"
	},
	{
		"category": "SURFACES", "title": "Emission", "tag": "LIGHTING",
		"summary": "Make a surface appear self-lit using an emission map and multiplier.",
		"body": "Emission is added to the lit surface result. Values above 1.0 can bloom when glow is enabled in the environment.",
		"code": "uniform sampler2D emission_map : source_color;\nuniform vec3 emission_color : source_color = vec3(1.0);\nuniform float emission_energy : hint_range(0.0, 16.0) = 1.0;\n\nvoid fragment() {\n    EMISSION = texture(emission_map, UV).rgb\n        * emission_color * emission_energy;\n}"
	},
	{
		"category": "UV & MAPPING", "title": "UV scale and offset", "tag": "UV",
		"summary": "Tile and reposition a texture with two simple parameters.",
		"body": "Scaling above 1 repeats the texture when the texture resource uses repeat wrapping. Offset moves the sampled region.",
		"code": "uniform sampler2D main_texture : source_color;\nuniform vec2 uv_scale = vec2(1.0);\nuniform vec2 uv_offset = vec2(0.0);\n\nvoid fragment() {\n    vec2 transformed_uv = UV * uv_scale + uv_offset;\n    ALBEDO = texture(main_texture, transformed_uv).rgb;\n}"
	},
	{
		"category": "UV & MAPPING", "title": "Scrolling UV", "tag": "ANIMATION",
		"summary": "Animate a texture continuously using the built-in TIME value.",
		"body": "TIME is measured in seconds. Multiplying it by a direction vector creates predictable motion without CPU-side updates.",
		"code": "uniform sampler2D main_texture : source_color;\nuniform vec2 scroll_speed = vec2(0.1, 0.0);\n\nvoid fragment() {\n    vec2 scrolling_uv = UV + TIME * scroll_speed;\n    ALBEDO = texture(main_texture, scrolling_uv).rgb;\n}"
	},
	{
		"category": "UV & MAPPING", "title": "Triplanar mapping", "tag": "3D",
		"summary": "Project a texture from three axes to avoid obvious UV seams.",
		"body": "The normal determines how strongly each planar projection contributes. Increase blend_power for sharper transitions.",
		"code": "uniform sampler2D triplanar_texture : source_color;\nuniform float triplanar_scale = 1.0;\nuniform float blend_power = 4.0;\n\nvoid fragment() {\n    vec3 blend = pow(abs(NORMAL), vec3(blend_power));\n    blend /= max(blend.x + blend.y + blend.z, 0.0001);\n    vec3 tx = texture(triplanar_texture, VERTEX.zy * triplanar_scale).rgb;\n    vec3 ty = texture(triplanar_texture, VERTEX.xz * triplanar_scale).rgb;\n    vec3 tz = texture(triplanar_texture, VERTEX.xy * triplanar_scale).rgb;\n    ALBEDO = tx * blend.x + ty * blend.y + tz * blend.z;\n}"
	},
	{
		"category": "UV & MAPPING", "title": "World triplanar inputs", "tag": "3D",
		"summary": "Keep projected textures stable when an object moves or scales.",
		"body": "Pass world position and world normal from vertex() to fragment(), then use them in place of local VERTEX and NORMAL in a triplanar shader.",
		"code": "varying vec3 world_position;\nvarying vec3 world_normal;\n\nvoid vertex() {\n    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);\n}\n\n// In fragment(), project world_position and blend with abs(world_normal)."
	},
	{
		"category": "EFFECTS", "title": "Fresnel rim", "tag": "LIGHTING",
		"summary": "Create a glowing edge where the surface turns away from the camera.",
		"body": "The view-normal dot product is strongest when facing the camera. Inverting and exponentiating it produces a controllable rim.",
		"code": "uniform vec3 rim_color : source_color = vec3(1.0);\nuniform float rim_power : hint_range(0.1, 8.0) = 3.0;\n\nvoid fragment() {\n    float fresnel = pow(1.0 - max(dot(normalize(NORMAL),\n        normalize(VIEW)), 0.0), rim_power);\n    EMISSION += rim_color * fresnel;\n}"
	},
	{
		"category": "EFFECTS", "title": "Alpha cutout", "tag": "TRANSPARENCY",
		"summary": "Discard transparent pixels with crisp, depth-friendly edges.",
		"body": "Alpha scissor is a good fit for leaves, fences and sprites. Unlike blended transparency, it can remain in the opaque rendering path.",
		"code": "uniform sampler2D alpha_texture;\nuniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;\n\nvoid fragment() {\n    ALPHA = texture(alpha_texture, UV).a;\n    ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;\n}"
	},
	{
		"category": "EFFECTS", "title": "Dissolve", "tag": "ANIMATION",
		"summary": "Reveal or remove a surface using a noise texture and animated threshold.",
		"body": "Animate dissolve_amount from 0 to 1. The smoothstep band creates a controllable glowing edge around the transition.",
		"code": "uniform sampler2D dissolve_noise;\nuniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;\nuniform float dissolve_edge = 0.05;\nuniform vec3 dissolve_color : source_color = vec3(1.0, 0.4, 0.0);\n\nvoid fragment() {\n    float noise_value = texture(dissolve_noise, UV).r;\n    ALPHA = step(dissolve_amount, noise_value);\n    float edge = 1.0 - smoothstep(dissolve_amount,\n        dissolve_amount + dissolve_edge, noise_value);\n    EMISSION += dissolve_color * edge;\n}"
	},
	{
		"category": "GEOMETRY", "title": "Billboard", "tag": "VERTEX",
		"summary": "Rotate a quad so it always faces the active camera.",
		"body": "This is useful for particles, labels and impostors. Cull both sides because the camera may cross the original plane.",
		"code": "shader_type spatial;\nrender_mode unshaded, cull_disabled;\n\nvoid vertex() {\n    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(\n        INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],\n        INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);\n}"
	},
	{
		"category": "GEOMETRY", "title": "Y-axis billboard", "tag": "VERTEX",
		"summary": "Face the camera while remaining upright around the world Y axis.",
		"body": "This constrained billboard is useful for characters, trees and signs that should never tilt toward the camera.",
		"code": "void vertex() {\n    vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0),\n        INV_VIEW_MATRIX[2].xyz));\n    vec3 forward = normalize(cross(INV_VIEW_MATRIX[0].xyz,\n        vec3(0.0, 1.0, 0.0)));\n    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(\n        vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0),\n        vec4(forward, 0.0), MODEL_MATRIX[3]);\n}"
	},
	{
		"category": "REFERENCE", "title": "Spatial outputs", "tag": "CHEAT SHEET",
		"summary": "The fragment outputs used most often by 3D materials.",
		"body": "ALBEDO is the base RGB color. ALPHA controls opacity. METALLIC, ROUGHNESS and SPECULAR define the PBR surface. EMISSION adds self-lit color. NORMAL_MAP and NORMAL_MAP_DEPTH apply tangent-space normals. AO darkens indirect light.",
		"code": "ALBEDO = vec3(1.0);\nALPHA = 1.0;\nMETALLIC = 0.0;\nROUGHNESS = 0.5;\nSPECULAR = 0.5;\nEMISSION = vec3(0.0);\nAO = 1.0;"
	},
	{
		"category": "REFERENCE", "title": "Useful functions", "tag": "CHEAT SHEET",
		"summary": "Small built-in functions cover most shader math and blending needs.",
		"body": "mix(a, b, weight) blends values. clamp limits a range. smoothstep creates a smooth threshold. dot measures directional similarity. normalize creates a unit vector. reflect and refract calculate view rays. texture samples an image.",
		"code": "float mask = smoothstep(0.25, 0.75, value);\nvec3 blended = mix(color_a, color_b, mask);\nfloat facing = max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);\nvec3 reflection_ray = reflect(-VIEW, NORMAL);"
	},
	{
		"category": "REFERENCE", "title": "Render modes", "tag": "CHEAT SHEET",
		"summary": "Render modes change culling, depth, lighting and blending behavior.",
		"body": "Modes are comma-separated after render_mode. Common choices include unshaded, cull_disabled, blend_add, depth_draw_opaque, depth_test_disabled, wireframe, skip_vertex_transform and world_vertex_coords.",
		"code": "shader_type spatial;\nrender_mode unshaded, cull_disabled;\n\n// Other examples:\n// render_mode blend_add, depth_draw_never;\n// render_mode world_vertex_coords;\n// render_mode wireframe;"
	},
	{
		"category": "REFERENCE", "title": "Debugging checklist", "tag": "TIPS",
		"summary": "Reduce a broken shader to a visible constant, then restore one concern at a time.",
		"body": "Confirm shader_type and semicolons first. Output a constant ALBEDO to verify the material is visible. Then inspect UVs as color, verify texture hints, and guard divisions with a small epsilon. Remember that fragment inputs and outputs depend on shader type.",
		"code": "void fragment() {\n    // 1. Is the material visible?\n    ALBEDO = vec3(1.0, 0.0, 1.0);\n\n    // 2. Are UVs present and oriented as expected?\n    // ALBEDO = vec3(UV, 0.0);\n\n    // 3. Avoid division by zero.\n    // float safe_value = numerator / max(denominator, 0.0001);\n}"
	}
]

var search := LineEdit.new()
var topic_list := VBoxContainer.new()
var content := VBoxContainer.new()
var result_count := Label.new()
var scroll := ScrollContainer.new()
var _filtered_indices: Array[int] = []
var _selected_index := 0
var _copy_revision := 0


func _ready() -> void:
	_native_docs().ready(self)

func open() -> void:
	_native_docs().open(self)

func open_samples(templates: bool = false) -> void:
	_native_docs().open_samples(self,templates)

func _section_changed(index: int) -> void:
	_native_docs().section_changed(self,index)

func _build_header() -> Control:
	return _native_docs().build_header(self)

func _build_body() -> Control:
	return _native_docs().build_body(self)

func _filter_topics(query: String) -> void:
	_native_docs().filter_topics(self,query)

func _rebuild_navigation() -> void:
	_native_docs().rebuild_navigation(self)

func _update_navigation_selection() -> void:
	_native_docs().update_navigation_selection(self)

func _select_topic(index: int) -> void:
	if not _native_docs().select_topic(self,index): return
	await get_tree().process_frame
	_native_docs().reset_scroll(self)

func _build_code_card(source: String, topic_title: String) -> Control:
	return _native_docs().build_code_card(self,source,topic_title)

func _copy_code(source: String, button: Button, _topic_title: String) -> void:
	var revision: int=_native_docs().copy_code(self,source,button)
	await get_tree().create_timer(1.4).timeout
	_native_docs().finish_copy(self,revision,button)

func _show_empty_state(query: String) -> void:
	_native_docs().show_empty_state(self,query)

func _style(bg: Color, border: Color, width: int, radius: int, padding: int) -> StyleBoxFlat:
	return _native_docs().style(bg,border,width,radius,padding)

func _style_button(button: Button, normal: Color, border: Color, hover: Color) -> void:
	_native_docs().style_button(button,normal,border,hover)

func _style_topic_button(button: Button, selected: bool) -> void:
	_native_docs().style_topic_button(button,selected)

func _make_highlighter() -> CodeHighlighter:
	return _native_docs().make_highlighter()


func _sample_open_requested(entry: Dictionary) -> void:
	sample_open_requested.emit(entry)

static func _native_docs() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("shader_documentation")
