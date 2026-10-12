extends RefCounted
## Original premultiplied layer texture is sampled once, through a smoothly
## interpolated inverse displacement. No bitmap is resampled during editing.
const CODE="""shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D deformation : filter_linear, repeat_disable;
uniform vec2 field_size=vec2(65.0);
uniform vec2 content_size=vec2(1280.0,720.0);
uniform bool enabled=true;
vec2 value_at(vec2 cell){return texture(deformation,(clamp(cell,vec2(0.0),field_size-1.0)+.5)/field_size).rg;}
vec4 cubic(float t){return vec4(-.5*t+t*t-.5*t*t*t,1.0-2.5*t*t+1.5*t*t*t,.5*t+2.0*t*t-1.5*t*t*t,-.5*t*t+.5*t*t*t);}
vec2 displacement_at(vec2 uv){
 vec2 p=clamp(uv,vec2(0.0),vec2(1.0))*(field_size-1.0); vec2 base=floor(p);
 vec4 wx=cubic(fract(p.x)); vec4 wy=cubic(fract(p.y)); vec2 sum=vec2(0.0);
 for(int y=0;y<4;y++){for(int x=0;x<4;x++){sum+=value_at(base+vec2(float(x-1),float(y-1)))*wx[x]*wy[y];}}
 return sum;
}
void fragment(){
 vec2 p=(UV/TEXTURE_PIXEL_SIZE-vec2(48.0))/content_size;
 vec2 q=p+(enabled ? displacement_at(p) : vec2(0.0));
 vec2 source=(q*content_size+vec2(48.0))*TEXTURE_PIXEL_SIZE;
 COLOR=any(lessThan(q,vec2(0.0))) || any(greaterThan(q,vec2(1.0))) ? vec4(0.0) : texture(TEXTURE,source);
}
"""
