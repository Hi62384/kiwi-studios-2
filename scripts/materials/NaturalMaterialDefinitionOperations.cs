using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class NaturalMaterialDefinitionOperations:RefCounted
{
    private static Settings Constant(string name)=>name switch { "CATEGORIES"=>NaturalMaterialCatalog.categories(), "STRUCTURE"=>NaturalMaterialCatalog.structure(), _=>throw new ArgumentException("Unknown material table: "+name) };
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    public string slug(string value)=>value.ToLowerInvariant().Replace(" ","_");
    public string category(string id)=>id.Split('/')[0].Capitalize();
    public int variant(string id){var groups=Constant("CATEGORIES");string group=category(id);if(!groups.ContainsKey(group))return 0;var names=groups[group].AsGodotArray();string[] parts=id.Split('/');string name=parts.Length>1?parts[1]:"";for(int i=0;i<names.Count;i++)if(slug(names[i].AsString())==name)return i;return 0;}
    public GArray ids(){var result=new GArray();foreach(var pair in Constant("CATEGORIES"))foreach(var name in pair.Value.AsGodotArray())result.Add(pair.Key.AsString().ToLowerInvariant()+"/"+slug(name.AsString()));return result;}
    public GArray controls(string id)
    {
        string group=category(id);int i=variant(id);string[] keys=group switch
        {
            "Noise"=>In(i,0,1,5,6,12)?new[]{"density","contrast"}:new[]{"frequency","octaves","gain","lacunarity"},
            "Metal"=>In(i,2,8,9)?new[]{"density","roughness","distortion"}:new[]{"density","roughness","distortion","detail"},
            "Wood"=>i==6?new[]{"density","distortion","detail"}:new[]{"density","distortion","knots","detail"},
            "Fabric"=>new[]{"density","thickness","distortion","detail"},
            "Ground"=>In(i,0,4,6,7,9,10,12,14)?new[]{"density","thickness","distortion","detail"}:new[]{"density","distortion","detail"},
            "Geometry"=>In(i,0,1,5,6,7,8)?new[]{"density","distortion"}:new[]{"density","thickness","distortion"},
            "Stone"=>In(i,0,2,3,4,10,12)?new[]{"density","distortion","detail"}:new[]{"density","thickness","distortion","detail"},
            "Organic"=>In(i,3,4,5,6,7,8,9)?new[]{"density","distortion","detail"}:new[]{"density","thickness","distortion","detail"},
            "Weathering"=>In(i,3,4,7,11,14)?new[]{"density","thickness","distortion","detail"}:new[]{"density","distortion","detail"},
            "Illustration"=>In(i,6,9,11,12,13)?new[]{"density","distortion","detail"}:new[]{"density","thickness","distortion"},_=>Array.Empty<string>()
        };var result=new GArray();foreach(string key in keys)result.Add(key);return result;
    }
    private static bool In(int index,params int[] values)=>Array.IndexOf(values,index)>=0;
    private static readonly Settings Specific=Json.ParseString("{\"stone/marble\":{\"density\":\"Vein density\",\"thickness\":\"Vein sharpness\",\"distortion\":\"Vein wandering\",\"detail\":\"Mineral detail\"},\"stone/granite\":{\"density\":\"Mineral size\",\"distortion\":\"Mineral variation\",\"detail\":\"Crystal grain\"},\"stone/concrete\":{\"density\":\"Aggregate density\",\"thickness\":\"Pore size\",\"distortion\":\"Aggregate variation\",\"detail\":\"Fine aggregate\"},\"metal/hammered_metal\":{\"density\":\"Hammer mark density\",\"distortion\":\"Dent depth\",\"detail\":\"Fine scratches\",\"roughness\":\"Surface roughness\"},\"metal/rusted_metal\":{\"density\":\"Corrosion scale\",\"distortion\":\"Corrosion coverage\",\"detail\":\"Pitting detail\",\"roughness\":\"Bare metal roughness\"},\"fabric/knitted_fabric\":{\"density\":\"Stitch density\",\"thickness\":\"Yarn thickness\",\"distortion\":\"Stitch irregularity\",\"detail\":\"Yarn fibers\"},\"fabric/leather\":{\"density\":\"Pore density\",\"thickness\":\"Pore size\",\"distortion\":\"Crease depth\",\"detail\":\"Fine grain\"},\"ground/grass\":{\"density\":\"Blade density\",\"thickness\":\"Blade width\",\"distortion\":\"Blade bend\",\"detail\":\"Fine blades\"},\"ground/sand\":{\"density\":\"Dune spacing\",\"thickness\":\"Grain size\",\"distortion\":\"Dune wandering\",\"detail\":\"Sand grain\"},\"ground/gravel\":{\"density\":\"Stone density\",\"thickness\":\"Stone separation\",\"distortion\":\"Stone variation\",\"detail\":\"Fine grit\"}}").AsGodotDictionary();
    private static readonly Settings Common=Json.ParseString("{\"density\":\"Detail density\",\"thickness\":\"Feature width\",\"roughness\":\"Surface roughness\",\"distortion\":\"Structure distortion\",\"detail\":\"Fine detail\",\"knots\":\"Knot density\",\"frequency\":\"Frequency\",\"octaves\":\"Octaves\",\"gain\":\"Noise gain\",\"lacunarity\":\"Lacunarity\"}").AsGodotDictionary();
    private static readonly Settings Labels=Json.ParseString("{\"Wood\":{\"density\":\"Grain frequency\",\"knots\":\"Knots\",\"distortion\":\"Grain warp\",\"detail\":\"Fiber detail\"},\"Fabric\":{\"density\":\"Weave density\",\"thickness\":\"Thread thickness\",\"distortion\":\"Thread irregularity\",\"detail\":\"Fiber grain\"},\"Metal\":{\"density\":\"Brush density\",\"detail\":\"Micro-scratches\",\"roughness\":\"Surface roughness\"}}").AsGodotDictionary();
    public string control_label(string id,string key)
    {
        var specific=Get(Specific,id,new Settings()).AsGodotDictionary();if(specific.ContainsKey(key))return specific[key].AsString();return Get(Get(Labels,category(id),new Settings()).AsGodotDictionary(),key,Get(Common,key,key.Capitalize())).AsString();
    }
    public GArray schema(string id)
    {
        var result=new GArray();using var preset=create(id);var defaults=preset.Get("parameters").AsGodotDictionary();
        foreach(var field in controls(id)){string key=field.AsString();double min=.01,max=1,step=.01;switch(key){case "density":min=.2;max=6;break;case "contrast":min=.2;max=2;break;case "frequency":min=.005;max=.3;step=.001;break;case "octaves":min=1;max=8;step=1;break;case "lacunarity":min=1;max=4;break;}result.Add(new Settings{["key"]=key,["label"]=control_label(id,key),["min"]=min,["max"]=max,["step"]=step,["default"]=Get(defaults,key,1.0)});}return result;
    }
    public Settings definition(string id)
    {
        using var value=create(id);return new Settings{["id"]=id,["name"]=value.Get("label"),["category"]=category(id),["version"]=2,["parameters"]=schema(id),["defaults"]=value.Get("parameters").AsGodotDictionary().Duplicate(true),["outputs"]=new GArray{"albedo","height","normal","roughness","metallic"},["preview"]=new Settings{["texture_size"]=value.Get("texture_size"),["geometry"]=category(id)=="Metal"?"sphere":"plane"},["tags"]=new GArray{category(id).ToLowerInvariant(),value.Get("label").AsString().ToLowerInvariant()}};
    }
    public Resource create(string id)
    {
        var result=new KiwiTextureMaterial();result.Set("material_id",id);string group=category(id);int i=variant(id);var categories=Constant("CATEGORIES");result.Set("label",categories.ContainsKey(group)?categories[group].AsGodotArray()[i]:Variant.From("Image"));
        var palette=group switch{"Metal"=>("656e77","d1dde3"),"Wood"=>("50321e","ba8951"),"Fabric"=>("233b60","7291af"),"Stone"=>("484946","b4b2a7"),"Ground"=>("423520","768d3e"),"Organic"=>("375b39","b1bd70"),"Weathering"=>("4b2416","c67a39"),"Illustration"=>("18212a","f1e7cd"),"Geometry"=>("274d64","8bddd0"),"Noise"=>("182530","d4e5e9"),_=>("000000","ffffff")};
        var p=new Settings{["primary"]=new Color(palette.Item1),["secondary"]=new Color(palette.Item2),["density"]=1.0,["thickness"]=.15,["roughness"]=.45,["distortion"]=.35,["detail"]=.6,["knots"]=.35,["contrast"]=1.0,["brightness"]=0.0,["seed"]=i*137,["frequency"]=.035,["octaves"]=4,["gain"]=.5,["lacunarity"]=2.0,["tileable"]=true};
        void Colors(string a,string b){p["primary"]=new Color(a);p["secondary"]=new Color(b);}void Size(double value)=>result.Set("texture_size",value);
        if(group=="Metal"){if(i==6)Colors("63321e","deac7e");if(i==7)Colors("554325","bba061");if(i==8)Colors("866217","ffe6a0");p["roughness"]=In(i,1,2,5,8,9)?.2:.7;if(i==11)Colors("5d686c","ac562f");}
        if(group=="Wood"){p["density"]=new[]{1.0,.7,1.4,1.6,.8,2.0,1.1,1.5,1.0,1.0,.8,1.0,.6,1.2}[i];p["knots"]=In(i,1,11,12)?.8:.25;if(In(i,2,3,13))Colors("28170e","795232");if(In(i,1,4,5))Colors("95753e","e0c79a");}
        if(group=="Fabric"){Size(96);p["thickness"]=.7;p["density"]=In(i,0,2,4,5)?1.4:.7;if(In(i,0,2,8,11))Colors("82735b","d8c9a4");if(In(i,3,13))Colors("454646","a5a7a3");if(In(i,6,7))Colors("352018","885739");if(i==5)Colors("291c39","705985");}
        if(group=="Stone"&&In(i,7,8,9,14))Size(128);
        if(group=="Ground"){if(In(i,8,9))Colors("b4cdd3","f0fafb");if(In(i,2,3,4,12,13))Colors("3d281b","94754a");if(i==5)Colors("b08b50","efd29b");if(In(i,6,7,10))Colors("46463f","aaa58f");}
        if(group=="Organic"){if(i==0)Colors("b18366","e8c6a9");if(In(i,3,4,7))Colors("483022","b29761");if(i==8)Colors("a59f81","ece5c7");if(i==9)Colors("9d7163","ecd1bd");}
        if(group=="Weathering"){if(In(i,1,2,9,11))Colors("38332c","a49573");if(In(i,7,8,12))Colors("161a1d","555143");if(i==13)Colors("26352a","718d55");}
        if(group=="Geometry")p["distortion"]=0.0;if(group=="Wood")Size(192);if(group=="Stone"&&i==1){Colors("454343","eeede7");Size(192);}if(group=="Stone"&&In(i,5,6))p["thickness"]=.5;
        if(group=="Ground"&&In(i,0,1)){Colors("192c10","8caa45");Size(128);}if(group=="Ground"&&i==5)Size(160);if(group=="Metal"&&In(i,10,13,14))Size(256);if(group=="Stone"&&In(i,0,9,11,13))Size(192);if(group=="Ground"&&In(i,4,6,7,10,12))Size(384);if(group=="Ground"&&In(i,0,1,11,14,15))Size(256);if(group=="Organic"&&In(i,1,2,5,6,9,10))Size(256);if(group=="Weathering")Size(192);
        result.Set("parameters",p);return result;
    }
}
