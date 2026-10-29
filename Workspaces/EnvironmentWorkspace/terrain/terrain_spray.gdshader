shader_type spatial;
render_mode unshaded,cull_disabled,depth_prepass_alpha;
uniform float liquid_time=0.0;
uniform float lifetime=1.2;
uniform float size=0.12;
uniform vec4 foam_color:source_color=vec4(0.94,0.98,1.0,1.0);
varying float fade;
void vertex(){
 float age=fract(liquid_time/max(lifetime,0.01)+INSTANCE_CUSTOM.w)*lifetime;
 vec3 center=(MODEL_MATRIX*vec4(0.0,0.0,0.0,1.0)).xyz;
 center+=mat3(MODEL_MATRIX)*(INSTANCE_CUSTOM.xyz*age+vec3(0.0,-2.0,0.0)*age*age);
 vec3 billboard=INV_VIEW_MATRIX[0].xyz*VERTEX.x+INV_VIEW_MATRIX[1].xyz*VERTEX.y;
 POSITION=PROJECTION_MATRIX*VIEW_MATRIX*vec4(center+billboard*size,1.0);
 fade=smoothstep(0.0,0.1,age)*(1.0-smoothstep(lifetime*0.5,lifetime,age));
}
void fragment(){
 float shape=1.0-smoothstep(0.2,0.5,length(UV-vec2(0.5)));
 ALBEDO=foam_color.rgb; ALPHA=foam_color.a*shape*fade*0.65;
}
