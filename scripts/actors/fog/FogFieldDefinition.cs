using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class FogFieldOperations
{
    private readonly ActorPropertyOperations _properties=new();
    private Resource Add(Resource definition,string key,string title,Variant value,bool keyed=false){var p=_properties.create(new StringName(key),title,value,keyed);definition.Get("properties").AsGodotArray().Add(p);return p;}
    public Resource definition()
    {
        var d=new ActorObjectDefinition();d.Set("type_id",new StringName("fog_field"));d.Set("display_name","Fog Density Field");var constants=Bridge.GetScriptConstantMap();foreach(var item in constants["FIELD_ROWS"].AsGodotArray()){var row=item.AsGodotArray();string key=row[0].AsString();var p=Add(d,key,row[1].AsString(),row[2],true);var options=p.Get("options").AsGodotDictionary();options.Merge(row[3].AsGodotDictionary());options["group"]="Field";void Visible(GArray values)=>options["visible_when"]=new Settings{["property"]="mode",["values"]=values};if(key is "noise_type" or "seed" or "frequency" or "octaves" or "lacunarity" or "gain" or "contrast" or "threshold")Visible(new GArray{4});if(key is "noise_type" or "seed" or "frequency" or "octaves" or "lacunarity" or "gain")options["group"]="Noise";if(key is "contrast" or "threshold")Visible(new GArray{4,5,7});if(key.StartsWith("shape",StringComparison.Ordinal)){Visible(new GArray{6});options["group"]="Shape mask";}if(key is "world_space" or "scale" or "offset")options["group"]="Mapping";if(key is "resolution" or "custom_resolution")options["group"]="Quality";if(key=="value")Visible(new GArray{0});if(key is "mode" or "resolution")options["refresh_inspector"]=true;}
        foreach(var item in constants["PAINT_ROWS"].AsGodotArray()){var row=item.AsGodotArray();var p=Add(d,row[0].AsString(),row[1].AsString(),row[2]);var options=p.Get("options").AsGodotDictionary();options.Merge(row[3].AsGodotDictionary());options["group"]="Painting";options["no_keyframes"]=true;}
        Add(d,"volume","3D texture","").Get("options").AsGodotDictionary().Merge(new Settings{["group"]="Volume",["file_picker"]=true,["extensions"]=new GArray{"tres","res"},["native_resource_types"]=new GArray{"Texture3D"},["file_resource_mode"]="uneditable"});Add(d,"boundary_mesh","Closed exclusion mesh","").Get("options").AsGodotDictionary().Merge(new Settings{["group"]="Volume",["file_picker"]=true,["extensions"]=new GArray{"tres","res","mesh"},["native_resource_types"]=new GArray{"Mesh"},["file_resource_mode"]="uneditable",["visible_when"]=new Settings{["property"]="mode",["values"]=new GArray{7}}});Add(d,"paint","Painted voxels",new Settings()).Set("options",new Settings{["default"]=new Settings(),["fog_paint"]=true,["group"]="Volume"});var mask=Add(d,"mask","Local volume mask",default);mask.Set("object_type",new StringName("fog_field"));mask.Get("options").AsGodotDictionary().Merge(new Settings{["group"]="Mask",["tooltip"]="Uses this field as a local-space influence mask. Nested mask chains are not evaluated."});_cloud.extend_definition(d);return d;
    }
}
