using Godot;
using System;
using System.Text;

public partial class TerrainBiomeRender
{
    public Shader shader()
    {
        if(_shader!=null)return _shader;
        string source=GD.Load<Shader>("res://Workspaces/EnvironmentWorkspace/terrain/terrain_paint.gdshader").Code;int start=source.IndexOf("vec3 triplanar_color",StringComparison.Ordinal),end=source.IndexOf("void fragment()",StringComparison.Ordinal);
        var code=new StringBuilder("shader_type spatial;\nuniform vec2 terrain_size=vec2(32.0);\nuniform sampler2D weights0: filter_linear_mipmap, repeat_disable;\nuniform sampler2D weights1: filter_linear_mipmap, repeat_disable;\nuniform bool has_cave_fields=false;uniform sampler3D cave_weights:hint_default_black,filter_linear,repeat_disable;uniform sampler3D cave_presence:hint_default_black,filter_linear,repeat_disable;uniform vec3 cave_origin=vec3(0.0);uniform vec3 cave_extent=vec3(1.0);\nvarying vec3 local_position; varying vec3 local_normal; varying mat3 normal_to_view;\nvoid vertex(){local_position=VERTEX;local_normal=NORMAL;normal_to_view=mat3(VIEW_MATRIX)*MODEL_NORMAL_MATRIX;}\n");code.Append(source.AsSpan(start,end-start));
        if(capacity()>4)code.Append("uniform sampler2D weights2:filter_linear_mipmap,repeat_disable;uniform sampler3D cave_weights1:hint_default_black,filter_linear,repeat_disable;\n");
        for(int index=0;index<capacity()+2;index++)
        {
            string prefix=$"layer{index}_";
            code.Append($"uniform sampler2D {prefix}texture:source_color,hint_default_white,filter_linear_mipmap,repeat_enable;\n");
            code.Append($"uniform sampler2D {prefix}normal:hint_normal,filter_linear_mipmap,repeat_enable;\n");
            foreach(string name in new[]{"roughness_texture","metallic_texture"})code.Append($"uniform sampler2D {prefix}{name}:hint_default_white,filter_linear_mipmap,repeat_enable;\n");
            code.Append($"uniform vec4 {prefix}color:source_color=vec4(1.0);\nuniform vec3 {prefix}scale=vec3(1.0);\nuniform vec3 {prefix}offset=vec3(0.0);\n");
            foreach(string name in new[]{"roughness_channel","metallic_channel"})code.Append($"uniform vec4 {prefix}{name}=vec4(1.0,0.0,0.0,0.0);\n");
            code.Append($"uniform float {prefix}roughness=1.0;\nuniform float {prefix}metallic=0.0;\nuniform float {prefix}normal_strength=0.0;\n");
        }
        code.Append("void fragment(){vec3 normal=normalize(local_normal);vec3 weights=pow(abs(normal),vec3(4.0));weights/=max(dot(weights,vec3(1.0)),0.00001);vec3 signs=sign(normal+vec3(0.000001));vec2 map_uv=local_position.xz/terrain_size+vec2(0.5);vec4 a=texture(weights0,map_uv);vec4 b=texture(weights1,map_uv);vec3 color=vec3(0.0);vec3 mapped=vec3(0.0);float roughness=0.0;float metallic=0.0;float total=0.0;\n");
        if(capacity()>4)code.Append("vec4 c=texture(weights2,map_uv);\n");
        code.Append("if(has_cave_fields){vec3 uv=(local_position-cave_origin)/max(cave_extent,vec3(0.0001));float inside=step(0.0,uv.x)*step(0.0,uv.y)*step(0.0,uv.z)*step(uv.x,1.0)*step(uv.y,1.0)*step(uv.z,1.0);vec4 cave=texture(cave_weights,uv);float coverage=smoothstep(0.01,0.2,texture(cave_presence,uv).r)*inside;float paint=a.g;float amount=dot(cave,vec4(1.0));");
        if(capacity()>4)code.Append("vec4 cave1=texture(cave_weights1,uv);amount+=dot(cave1,vec4(1.0));");
        code.Append("a=mix(a,vec4((1.0-paint)*(1.0-clamp(amount,0.0,1.0)),paint,(1.0-paint)*cave.r,(1.0-paint)*cave.g),coverage);");
        code.Append(capacity()>4?"b=mix(b,vec4((1.0-paint)*cave.b,(1.0-paint)*cave.a,(1.0-paint)*cave1.r,(1.0-paint)*cave1.g),coverage);c=mix(c,vec4((1.0-paint)*cave1.b,(1.0-paint)*cave1.a,0.0,0.0),coverage); }\n":"b=mix(b,vec4((1.0-paint)*cave.b,(1.0-paint)*cave.a,0.0,0.0),coverage); }\n");
        for(int index=0;index<capacity()+2;index++)
        {
            string p=$"layer{index}_",weight=new[]{"a","b","c"}[index/4]+"."+new[]{"r","g","b","a"}[index%4];
            code.Append("{float w=max(0.0,").Append(weight).Append(");if(w>0.00001){vec3 uv=local_position*").Append(p).Append("scale+").Append(p).Append("offset;color+=w*").Append(p).Append("color.rgb*triplanar_color(").Append(p).Append("texture,uv,weights);roughness+=w*").Append(p).Append("roughness*triplanar_value(").Append(p).Append("roughness_texture,uv,weights,").Append(p).Append("roughness_channel);metallic+=w*").Append(p).Append("metallic*triplanar_value(").Append(p).Append("metallic_texture,uv,weights,").Append(p).Append("metallic_channel);mapped+=w*normalize(mix(normal,triplanar_normal(").Append(p).Append("normal,uv,weights,signs),").Append(p).Append("normal_strength));total+=w;}}\n");
        }
        code.Append("ALBEDO=color/max(total,0.00001);ROUGHNESS=roughness/max(total,0.00001);METALLIC=metallic/max(total,0.00001);NORMAL=normalize(normal_to_view*normalize(mapped));}\n");
        _shader=new Shader {Code=code.ToString()};return _shader;
    }
}
