shader_type fog;
uniform float base_density=1.0;
uniform float density_multiplier=1.0;
uniform float contrast=1.0;
uniform float density_offset=0.0;
uniform float threshold=0.0;
uniform float maximum_density=64.0;
uniform float opacity=1.0;
uniform float scattering=1.0;
uniform float absorption=0.0;
uniform int render_style=0;
uniform float stylization=1.0;
uniform int shading_bands=3;
uniform vec4 shadow_tint:source_color=vec4(0.35,0.42,0.55,1.0);
uniform float highlight=1.0;
uniform bool cloud_lighting=false;
uniform float cloud_shadow_strength=1.0;
uniform float silver_lining=0.0;
uniform bool cloud_lod=false;
uniform float cloud_detail_distance=50.0;
uniform sampler3D cloud_low:filter_linear,repeat_enable;
uniform bool scene_ground=false;
uniform sampler2D scene_ground_height:filter_linear,repeat_disable;
uniform vec3 sun_direction=vec3(0.0,1.0,0.0);
uniform vec4 sun_color:source_color=vec4(0.0);
uniform vec3 viewer_position=vec3(0.0);
uniform vec4 base_color:source_color=vec4(1.0);
uniform vec4 secondary:source_color=vec4(1.0);
uniform vec4 third_color:source_color=vec4(1.0);
uniform vec4 fourth_color:source_color=vec4(1.0);
uniform int gradient_stops=2;
uniform vec2 gradient_positions=vec2(0.33,0.66);
uniform vec4 emission_color:source_color=vec4(0.0);
uniform float emission_energy=1.0;
uniform int gradient_mode=0;
uniform vec3 gradient_direction=vec3(0.0,1.0,0.0);
uniform vec3 gradient_range=vec3(0.0,1.0,1.0);
uniform bool world_mapping=false;
uniform mat4 world_to_local;
uniform vec3 volume_dimensions=vec3(4.0,2.0,4.0);
uniform bool has_simulation=false;
uniform bool has_source_field=false;
uniform sampler3D simulation_density:filter_linear,repeat_disable;
uniform mat4 simulation_to_unit;
uniform bool procedural_motion=false;
uniform vec3 motion_unit_offset=vec3(0.0);
uniform vec3 motion_world_offset=vec3(0.0);
uniform mat3 motion_rotation;
uniform float motion_turbulence=0.0;
uniform float motion_scale=1.0;
uniform float motion_phase=0.0;
uniform float motion_seed=0.0;
uniform vec3 texture_scale=vec3(1.0);
uniform vec3 texture_offset=vec3(0.0);
uniform mat3 texture_rotation;
uniform int texture_mapping=0;
uniform float texture_strength=1.0;
uniform float texture_contrast=1.0;
uniform bool texture_tiling=true;
uniform sampler2D color_map:source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D density_map:filter_linear_mipmap,repeat_enable;
uniform sampler2D mask_map:filter_linear_mipmap,repeat_enable;
uniform sampler2D detail_map:filter_linear_mipmap,repeat_enable;
uniform sampler3D density_volume:filter_linear,repeat_enable;
uniform sampler3D color_volume:source_color,filter_linear,repeat_enable;
uniform bool has_color=false;
uniform bool has_density=false;
uniform bool has_mask=false;
uniform bool has_detail=false;
uniform bool has_density_volume=false;
uniform bool has_color_volume=false;
uniform vec4 field_mode[5]; // enabled, type, combine, target
uniform vec4 field_params[5]; // strength, start, end, exponent
uniform vec4 field_direction[5]; // xyz direction, world space
uniform vec4 field_scale[5]; // xyz scale, invert
uniform vec4 field_offset[5]; // xyz offset, contrast
uniform vec4 field_color[5];
uniform float field_threshold[5];
uniform float field_value[5];
uniform float field_has_mask[5];
uniform vec4 field_shape[5]; // size xyz, primitive type
uniform vec4 field_cloud_ground[5]; // formation type, world elevation, height falloff
uniform vec4 field_rotation[5]; // quaternion
uniform float field_edge[5];
uniform sampler3D field_0:filter_linear,repeat_enable;
uniform sampler3D field_1:filter_linear,repeat_enable;
uniform sampler3D field_2:filter_linear,repeat_enable;
uniform sampler3D field_3:filter_linear,repeat_enable;
uniform sampler3D field_4:filter_linear,repeat_enable;
uniform sampler3D mask_0:filter_linear,repeat_disable;
uniform sampler3D mask_1:filter_linear,repeat_disable;
uniform sampler3D mask_2:filter_linear,repeat_disable;
uniform sampler3D mask_3:filter_linear,repeat_disable;
uniform sampler3D mask_4:filter_linear,repeat_disable;
uniform int shape_kind=3;
uniform float edge_fade=0.1;
uniform bool global_volume=false;
uniform bool has_boundary=false;
uniform sampler3D boundary_map:filter_linear,repeat_disable;

vec4 mapped_2d(sampler2D tex,vec3 p){
	if(texture_mapping==0){return textureLod(tex,p.xy,0.0);}
	return (textureLod(tex,p.xy,0.0)+textureLod(tex,p.yz,0.0)+textureLod(tex,p.zx,0.0))/3.0;
}
float ramp(float v,vec3 range){return pow(clamp((v-range.x)/max(0.0001,range.y-range.x),0.0,1.0),max(0.01,range.z));}
float shape_distance(vec3 p,vec4 shape){
	vec3 e=max(abs(shape.xyz)*0.5,vec3(0.0005));int kind=int(shape.w);float r=min(e.x,min(e.y,e.z));
	if(kind==1){return length(p)-r;}
	if(kind==2){return (length(p/e)-1.0)*r;}
	if(kind==3){return max(length(p.xz/e.xz)-1.0,abs(p.y)/e.y-1.0)*r;}
	if(kind==4){return max(length(p.xz/e.xz)-(0.5-p.y/(e.y*2.0)),abs(p.y)/e.y-1.0)*r;}
	if(kind==5){r=min(e.x,e.z);p.y-=clamp(p.y,-max(0.0,e.y-r),max(0.0,e.y-r));return length(p)-r;}
	vec3 q=abs(p)-e;return length(max(q,vec3(0.0)))+min(max(q.x,max(q.y,q.z)),0.0);
}
float combine_field(float a,float b,int mode,float strength){
	if(mode==0){return a+b*strength;}
	if(mode==1){return a*mix(1.0,b,clamp(strength,0.0,1.0));}
	if(mode==2){return mix(a,max(a,b),clamp(strength,0.0,1.0));}
	if(mode==3){return mix(a,min(a,b),clamp(strength,0.0,1.0));}
	if(mode==4){return max(0.0,a-b*strength);}
	return mix(a,b,clamp(strength,0.0,1.0));
}
float cloud_concentration(vec3 world){
	vec3 p=(world_to_local*vec4(world,1.0)).xyz/max(volume_dimensions,vec3(0.0001))+vec3(0.5);
	if(has_simulation){p=(simulation_to_unit*vec4(world,1.0)).xyz;}
	if(any(lessThan(p,vec3(0.0)))||any(greaterThan(p,vec3(1.0)))){return 0.0;}
	if(has_simulation){return textureLod(simulation_density,p,0.0).r;}
	if(has_source_field&&field_mode[0].x>0.5&&field_mode[0].w<0.5){
		vec3 q=(field_direction[0].w>0.5?world:p)*field_scale[0].xyz+field_offset[0].xyz;
		float f=field_value[0];
		if(field_mode[0].y>3.5){f=pow(max(0.0,textureLod(field_0,q,0.0).r-field_threshold[0]),field_offset[0].w);}
		if(field_scale[0].w>0.5){f=1.0-f;}
		return max(0.0,combine_field(1.0,f,int(field_mode[0].z),field_params[0].x));
	}
	return 1.0;
}
void fog(){
	vec3 local=(world_to_local*vec4(WORLD_POSITION,1.0)).xyz;
	vec3 unit=local/max(volume_dimensions,vec3(0.0001))+vec3(0.5);
	vec3 pos=world_mapping?WORLD_POSITION:unit;
	vec3 uv=texture_rotation*(pos*texture_scale)+texture_offset;
	if(!texture_tiling){uv=clamp(uv,vec3(0.001),vec3(0.999));}
	float density=base_density;
	if(has_simulation){vec3 sample_point=(simulation_to_unit*vec4(WORLD_POSITION,1.0)).xyz;density*=textureLod(simulation_density,clamp(sample_point,vec3(0.0),vec3(1.0)),0.0).r;}
	vec3 moving_unit=unit;vec3 moving_world=WORLD_POSITION;
	if(procedural_motion){
		moving_unit=motion_rotation*(unit-vec3(0.5))+vec3(0.5)-motion_unit_offset;
		moving_world=motion_rotation*(WORLD_POSITION-OBJECT_POSITION)+OBJECT_POSITION-motion_world_offset;
		vec3 q=local/max(0.001,motion_scale);vec3 displacement=(sin(q.zxy+vec3(motion_phase))-sin(q.zxy+vec3(motion_seed)))*motion_turbulence;
		moving_unit+=displacement/volume_dimensions;moving_world+=displacement;
	}
	vec3 tint=base_color.rgb;
	float g=pos.y;
	if(gradient_mode==2){g=pos.x;}
	if(gradient_mode==3){g=length(pos-vec3(0.5))*2.0;}
	if(gradient_mode==4){g=dot(pos,normalize(gradient_direction+vec3(0.000001)));}
	if(gradient_mode>0){
		float t=ramp(g,gradient_range);
		if(gradient_stops==2){tint=mix(tint,secondary.rgb,t);}
		else if(gradient_stops==3){float p=clamp(gradient_positions.x,0.001,0.999);tint=t<p?mix(tint,secondary.rgb,t/p):mix(secondary.rgb,third_color.rgb,(t-p)/(1.0-p));}
		else{float p=clamp(gradient_positions.x,0.001,0.998);float q=clamp(gradient_positions.y,p+0.001,0.999);tint=t<p?mix(tint,secondary.rgb,t/p):(t<q?mix(secondary.rgb,third_color.rgb,(t-p)/(q-p)):mix(third_color.rgb,fourth_color.rgb,(t-q)/(1.0-q)));}
	}
	vec3 emitted=emission_color.rgb*emission_energy;
	for(int i=0;i<5;i++){
		if(field_mode[i].x<0.5){continue;}
		if(has_simulation&&has_source_field&&i==0&&field_mode[i].w<0.5){continue;}
		vec3 p=(field_direction[i].w>0.5?moving_world:moving_unit)*field_scale[i].xyz+field_offset[i].xyz;
		int mode=int(field_mode[i].y);
		float f=field_value[i];
		if(mode==1){f=p.y;}
		if(mode==2){f=1.0-length(p-vec3(0.5))*2.0;}
		if(mode==3){f=dot(p,normalize(field_direction[i].xyz+vec3(0.000001)));}
		if(mode==4||mode==5||mode==7||mode==8){
			if(i==0){f=textureLod(field_0,p,0.0).r;}
			else if(i==1){f=textureLod(field_1,p,0.0).r;}
			else if(i==2){f=textureLod(field_2,p,0.0).r;}
			else if(i==3){f=textureLod(field_3,p,0.0).r;}
			else{f=textureLod(field_4,p,0.0).r;}
			if(i==0&&mode==8&&cloud_lod){float blend=smoothstep(cloud_detail_distance,cloud_detail_distance*1.5,length(WORLD_POSITION-viewer_position));f=mix(f,textureLod(cloud_low,p,0.0).r,blend);}
			if(mode==8&&field_cloud_ground[i].x>3.5){
				float ground=field_cloud_ground[i].y;
				if(i==0&&scene_ground){ground=textureLod(scene_ground_height,unit.xz,0.0).r;}
				float height_falloff=exp(-max(0.0,WORLD_POSITION.y-ground)/max(0.01,field_cloud_ground[i].z));
				f=field_cloud_ground[i].x>4.5?height_falloff:f*height_falloff;
			}
			f=pow(max(0.0,f-field_threshold[i]),field_offset[i].w);
			if(mode==7&&(any(lessThan(p,vec3(0.0)))||any(greaterThan(p,vec3(1.0))))){f=0.0;}
		}else if(mode==6){
			vec4 q=field_rotation[i];vec3 point=p-vec3(0.5);point+=2.0*cross(-q.xyz,cross(-q.xyz,point)+q.w*point);
			f=smoothstep(0.0,max(0.0001,field_edge[i]),-shape_distance(point,field_shape[i]));
		}else if(mode>0){f=ramp(f,vec3(field_params[i].yz,field_params[i].w));}
		if(field_scale[i].w>0.5){f=1.0-f;}
		float influence=field_params[i].x;
		if(field_has_mask[i]>0.5){
			float mask=1.0;
			if(i==0){mask=textureLod(mask_0,unit,0.0).r;}
			else if(i==1){mask=textureLod(mask_1,unit,0.0).r;}
			else if(i==2){mask=textureLod(mask_2,unit,0.0).r;}
			else if(i==3){mask=textureLod(mask_3,unit,0.0).r;}
			else{mask=textureLod(mask_4,unit,0.0).r;}
			influence*=mask;
		}
		if(field_mode[i].w<0.5){density=combine_field(density,f,int(field_mode[i].z),influence);}
		else if(field_mode[i].w<1.5){tint=mix(tint,field_color[i].rgb,clamp(f*influence,0.0,1.0));}
		else{emitted+=field_color[i].rgb*f*influence;}
	}
	if(has_color){tint*=mix(vec3(1.0),mapped_2d(color_map,uv).rgb,texture_strength);}
	if(has_density){density*=mix(1.0,pow(max(0.0,mapped_2d(density_map,uv).r),texture_contrast),texture_strength);}
	if(has_detail){density*=mix(1.0,pow(max(0.0,mapped_2d(detail_map,uv).r),texture_contrast),texture_strength);}
	if(has_mask){density*=mapped_2d(mask_map,uv).r;}
	if(has_density_volume){density*=textureLod(density_volume,uv,0.0).r;}
	if(has_color_volume){tint*=textureLod(color_volume,uv,0.0).rgb;}
	float boundary=1.0;
	if(!global_volume){
		float distance_inside=-SDF;
		// Capsule and sphere are explicit SDFs; existing native shapes retain their IDs.
		if(shape_kind==5){distance_inside=min(SIZE.x,min(SIZE.y,SIZE.z))*0.5-length(local);}
		if(shape_kind==6){vec3 q=local;float r=min(SIZE.x,SIZE.z)*0.5;q.y-=clamp(q.y,-max(0.0,SIZE.y*0.5-r),max(0.0,SIZE.y*0.5-r));distance_inside=r-length(q);}
		boundary=smoothstep(0.0,max(0.0001,edge_fade),distance_inside);
		if(shape_kind==7){boundary*=has_boundary?textureLod(boundary_map,unit,0.0).r:0.0;}
	}
	density=pow(max(0.0,density+density_offset-threshold),contrast)*density_multiplier;
	if(cloud_lighting||render_style>0){
		float optical_depth=0.0;
		float distance_step=min(volume_dimensions.x,min(volume_dimensions.y,volume_dimensions.z))/6.0;
		for(int sample_index=1;sample_index<=6;sample_index++){
			optical_depth+=cloud_concentration(WORLD_POSITION+sun_direction*distance_step*float(sample_index))*distance_step*max(0.0,base_density)*density_multiplier*opacity;
		}
		float transmission=exp(-optical_depth*cloud_shadow_strength);
		float shade=transmission;
		if(render_style==1){shade=floor(transmission*float(shading_bands))/float(max(shading_bands,1));}
		if(render_style==2){shade=smoothstep(0.15,0.8,transmission);}
		if(render_style==3){shade=mix(transmission,smoothstep(0.1,0.9,transmission),0.5);}
		if(render_style>0){tint=mix(tint,tint*mix(shadow_tint.rgb,vec3(highlight),clamp(shade,0.0,1.0)),stylization);}
		else{tint*=mix(0.35,1.0,transmission);}
		vec3 view_ray=normalize(WORLD_POSITION-viewer_position+vec3(0.000001));
		float backlight=pow(max(0.0,dot(view_ray,normalize(sun_direction))),8.0);
		float edge=exp(-density*2.0)*(1.0-exp(-density*8.0));
		emitted+=sun_color.rgb*silver_lining*backlight*edge*transmission;
	}
	DENSITY=clamp(density*opacity*(1.0+absorption),0.0,maximum_density)*boundary;
	ALBEDO=clamp(tint*scattering/(1.0+absorption),vec3(0.0),vec3(1.0));
	EMISSION=emitted*opacity*boundary;
}
