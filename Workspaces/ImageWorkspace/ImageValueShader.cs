using Godot;
using System;
using System.Globalization;
using System.Text;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageValueOperations
{
    private static string Number(double value){string text=value.ToString("G17",CultureInfo.InvariantCulture);return text.Contains('.')||text.Contains('E')||text.Contains('e')?text:text+".0";}
    public string operand_code(Settings operand)
    {
        string kind=Get(operand,"kind","pixel").AsString();if(kind=="float")return "vec4("+Number(Get(operand,"value",0).AsDouble())+")";if(kind=="vector"){var parts=new System.Collections.Generic.List<string>();foreach(var channel in Get(operand,"channels",new GArray{1.0,1.0,1.0,1.0}).AsGodotArray())parts.Add(channel.VariantType==Variant.Type.String?"v."+channel.AsString():Number(channel.AsDouble()));return "vec4("+string.Join(", ",parts)+")";}return "v";
    }
    public string operation_code(Settings operation)
    {
        string a=operand_code(operation["a"].AsGodotDictionary()),b=operand_code(operation["b"].AsGodotDictionary()),c=operand_code(Get(operation,"c",new Settings{["kind"]="float",["value"]=1.0}).AsGodotDictionary());return operation["type"].AsString() switch{"add"=>a+"+"+b,"multiply"=>a+"*"+b,"subtract"=>a+"-"+b,"divide"=>a+"/safe_denominator("+b+")","power"=>"pow(max("+a+",vec4(0.0)),max("+b+",vec4(.0001)))","minimum"=>"min("+a+","+b+")","maximum"=>"max("+a+","+b+")","clamp"=>"clamp("+a+",min("+b+","+c+"),max("+b+","+c+"))","lerp"=>"mix("+a+","+b+","+c+")","absolute"=>"abs("+a+")","invert"=>"vec4(vec3(1.0)-("+a+").rgb,("+a+").a)","smoothstep"=>"smoothstep(min("+b+","+c+"),max("+b+","+c+")+vec4(.00001),"+a+")","snap"=>(Get(operation,"preserve_hue",true).AsBool()?"snap_hue(":"snap_channels(")+a+","+b+")",_=>a};
    }
    public string expression(string kind,double amount)
    {
        string a=Number(amount);return kind switch
        {
            "multiply" => "c * " + a,
            "divide" => "c / " + Number(Math.Max(.001,amount)),
            "add" or "brightness" => "c + vec3("+a+")",
            "subtract" => "c - vec3("+a+")",
            "power" => "pow(max(c,vec3(0.0)),vec3("+Number(Math.Max(.001,amount))+"))",
            "gamma" => "pow(max(c,vec3(0.0)),vec3("+Number(1.0/Math.Max(.001,amount)) +"))",
            "exposure" => "c * " + Number(Math.Pow(2,amount)),
            "snap" => "floor(c * "+Number(Math.Max(1,amount))+" + .5) / "+Number(Math.Max(1,amount)),
            "invert" => "vec3(1.0)-c",
            "contrast" => "(c-vec3(.5))*"+a+"+vec3(.5)",
            "saturation" => "mix(vec3(dot(c,vec3(.2126,.7152,.0722))),c,"+a+")",
            "hue" => "rotate_hue(c,"+a+")",
            "minimum" => "min(c,vec3("+a+"))",
            "maximum" => "max(c,vec3("+a+"))",
            "temperature" => "c+vec3("+a+",0.0,"+Number(-amount)+")",
            "tint" => "c+vec3(0.0,"+a+",0.0)",
            "red" => "c*vec3("+a+",1.0,1.0)",
            "green" => "c*vec3(1.0,"+a+",1.0)",
            "blue" => "c*vec3(1.0,1.0,"+a+")",
            "vibrance" => "mix(vec3(dot(c,vec3(.2126,.7152,.0722))),c,1.0+"+a+"*(1.0-clamp(max(c.r,max(c.g,c.b))-min(c.r,min(c.g,c.b)),0.0,1.0)))",
            "grayscale" => "mix(c,vec3(dot(c,vec3(.2126,.7152,.0722))),"+a+")",
            "sepia" => "mix(c,vec3(dot(c,vec3(.393,.769,.189)),dot(c,vec3(.349,.686,.168)),dot(c,vec3(.272,.534,.131))),"+a+")",
            "posterize" => "floor(c*"+Number(Math.Max(2,amount))+"+.5)/"+Number(Math.Max(2,amount)),
            "solarize" => "mix(c,vec3(1.0)-c,step(vec3("+a+"),c))",
            "shadows" => "c+vec3("+a+")*pow(1.0-clamp(dot(c,vec3(.2126,.7152,.0722)),0.0,1.0),2.0)",
            "highlights" => "c+vec3("+a+")*pow(clamp(dot(c,vec3(.2126,.7152,.0722)),0.0,1.0),2.0)",
            "black_point" => "(c-vec3("+a+"))/"+Number(Math.Max(.001,1-amount)),
            "white_point" => "c/"+Number(Math.Max(.001,amount)),
            "midtones" => "c+vec3("+a+")*(4.0*clamp(dot(c,vec3(.2126,.7152,.0722)),0.0,1.0)*(1.0-clamp(dot(c,vec3(.2126,.7152,.0722)),0.0,1.0)))",
            "lift" => "c+(vec3(1.0)-c)*"+a,
            "fade" => "mix(c,vec3(.5),"+a+")",
            "threshold" => "vec3(step("+a+",dot(c,vec3(.2126,.7152,.0722))))",
            "cyan_red" => "c+vec3("+a+","+Number(-amount*.5)+","+Number(-amount*.5)+")",
            "magenta_green" => "c+vec3("+Number(-amount*.5)+","+a+","+Number(-amount*.5)+")",
            "yellow_blue" => "c+vec3("+Number(-amount*.5)+","+Number(-amount*.5)+","+a+")",
            "shadow_warmth" => "c+vec3("+a+",0.0,"+Number(-amount)+")*pow(1.0-clamp(dot(c,vec3(.2126,.7152,.0722)),0.0,1.0),2.0)",
            "highlight_warmth" => "c+vec3("+a+",0.0,"+Number(-amount)+")*pow(clamp(dot(c,vec3(.2126,.7152,.0722)),0.0,1.0),2.0)",
            "colorize" => "mix(c,vec3(dot(c,vec3(.2126,.7152,.0722)))*vec3(1.35,.95,.65),"+a+")",
            _=>"c"
        };
    }
    public string shader_code(Resource layer)
    {
        var code=new StringBuilder(ShaderPrefix);foreach(var raw in operations(layer)){var operation=raw.AsGodotDictionary();if(!Get(operation,"enabled",true).AsBool())continue;if(operation.ContainsKey("a"))code.Append("{vec4 next=").Append(operation_code(operation)).Append("; v=").Append(Get(operation,"affect_alpha",false).AsBool()?"next":"vec4(next.rgb,v.a)").Append("; c=v.rgb;}\n");else code.Append("c=").Append(expression(operation["type"].AsString(),Get(operation,"amount",1).AsDouble())).Append("; v.rgb=c;\n");}return code.Append(ShaderSuffix).ToString();
    }
    private const string ShaderPrefix="shader_type canvas_item;\nrender_mode unshaded, blend_disabled;\nuniform sampler2D selection_mask;\nuniform bool selection_only=false;\nuniform bool has_selection=false;\nuniform bool selection_local=false;\nuniform vec2 selection_origin;\nuniform vec2 selection_x;\nuniform vec2 selection_y;\nuniform vec2 document_size;\nuniform vec2 content_extent;\nvec3 rotate_hue(vec3 c,float a) { vec3 k=vec3(.577350269); return c*cos(a)+cross(k,c)*sin(a)+k*dot(k,c)*(1.0-cos(a)); }\nvec4 safe_denominator(vec4 x){ return mix(vec4(1.0),vec4(-1.0),lessThan(x,vec4(0.0)))*max(abs(x),vec4(.0001)); }\nvec4 snap_channels(vec4 a,vec4 b){ vec4 step=max(abs(b),vec4(.0001)); return floor(a/step+.5)*step; }\nvec4 snap_hue(vec4 a,vec4 b){ float peak=max(a.r,max(a.g,a.b)); float step=max(abs(b.r),.0001); return vec4(a.rgb*(floor(peak/step+.5)*step/max(peak,.00001)),a.a); }\nvoid fragment(){ vec4 original=texture(TEXTURE,UV); vec3 c=original.rgb/max(original.a,.00001); vec4 v=vec4(c,original.a);\n";
    private const string ShaderSuffix="vec2 p=UV/TEXTURE_PIXEL_SIZE-vec2(48.0); vec2 q=selection_local ? p/content_extent : (selection_origin+selection_x*p.x+selection_y*p.y)/document_size; float mask=selection_only ? (has_selection && all(greaterThanEqual(q,vec2(0.0))) && all(lessThanEqual(q,vec2(1.0))) ? texture(selection_mask,q).a : 0.0) : 1.0; v=clamp(v,vec4(0.0),vec4(1.0)); if(original.a==0.0 && (any(lessThan(p,vec2(0.0))) || any(greaterThan(p,content_extent)))) {v.a=0.0;} COLOR=mix(original,vec4(v.rgb*v.a,v.a),mask); }";
}
