using Godot;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderWorkspaceOperations
{
    public Resource? noise_from_parameter(Variant value)
    {
        if(value.VariantType!=Variant.Type.Object||value.AsGodotObject() is not Resource reference||!ScriptType(reference,"res://scripts/actors/core/actor_object_reference.gd"))return null;
        var resolved=reference.Call("resolve",Callable.From<string,Variant>(path=>{string localized=ProjectSettings.LocalizePath(path);if(!ResourceLoader.Exists(localized))return default;var loaded=ResourceLoader.Load(localized,"",ResourceLoader.CacheMode.Ignore);return loaded!=null&&ScriptType(loaded,"res://scripts/actors/core/actor_object_data.gd")?Variant.From(loaded):default;})).As<Resource>();return resolved!=null&&resolved.Get("type_id").AsStringName()==new StringName("noise_image")?resolved:null;
    }
    public void set_parameter_image_path(Control owner,StringName name,string path)
    {
        string localized=godot_project_path(path);if(path.GetExtension().ToLowerInvariant() is "tres" or "res"){var loaded=ResourceLoader.Load(localized,"",ResourceLoader.CacheMode.Ignore);if(loaded!=null&&ScriptType(loaded,"res://scripts/actors/core/actor_object_data.gd")&&loaded.Get("type_id").AsString()=="noise_image"){owner.Get("parameter_expanded").AsGodotDictionary()[name]=true;set_preview_parameter(owner,name,ActorObjectReference.from_asset(localized,new StringName("noise_image")),"edit",default);rebuild_parameters(owner);return;}}set_preview_parameter(owner,name,localized,"edit",default);rebuild_parameters(owner);
    }
    public void add_noise_property(Control owner,VBoxContainer parent,StringName parameterName,Resource noise,Resource definition,Resource property,TextureRect preview)
    {
        var row=Row(parent);Attach(row,new Label {Text=property.Get("label").AsString(),CustomMinimumSize=new Vector2(104,0)});var current=definition.Call("value_for",noise,property);var options=property.Get("options").AsGodotDictionary();var id=property.Get("id").AsStringName();int type=property.Get("value_type").AsInt32();var values=owner.Get("parameter_values").AsGodotDictionary();Settings origin=new();Variant working=default;
        void Begin(){origin=CopyValue(current_parameter_values(owner)).AsGodotDictionary();working=CopyValue(values.TryGetValue(parameterName,out var existing)?existing:default);}
        void Apply(Variant next,string mode="edit",Variant original=default,Variant owned=default){var reference=owned.VariantType!=Variant.Type.Nil?owned:CopyValue(values.TryGetValue(parameterName,out var existing)?existing:default);var data=noise_from_parameter(reference);if(data==null)return;data.Call("set_value",id,CopyValue(next));if(data.ResourcePath.Length>0)ResourceSaver.Save(data,data.ResourcePath);values[parameterName]=reference;preview.Texture=Texture(data).As<Texture2D>();set_preview_parameter(owner,parameterName,reference,mode,original);}
        void Restore(){if(!origin.TryGetValue(parameterName,out var before))return;var reference=CopyValue(before);values[parameterName]=reference;var data=noise_from_parameter(reference);preview.Texture=data!=null?Texture(data).As<Texture2D>():null;set_preview_parameter(owner,parameterName,reference,"preview",default);working=default;}
        if(options.TryGetValue("choices",out var choices)){var picker=Attach(row,new OptionButton {SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});foreach(var option in choices.AsGodotArray())picker.AddItem(option.ToString());picker.Select(current.AsInt32());picker.ItemSelected+=index=>Apply(index);return;}
        if(type==(int)Variant.Type.Bool){var toggle=Attach(row,new CheckButton {ButtonPressed=current.AsBool()});toggle.Toggled+=next=>Apply(next);}
        else if(type is (int)Variant.Type.Int or (int)Variant.Type.Float){var number=Attach(row,Number(current.AsDouble(),options.TryGetValue("step",out var step)?step.AsDouble():type==(int)Variant.Type.Int?1:.01));number.Name=parameterName+"_noise_"+id;Variant Normalize(double next)=>type==(int)Variant.Type.Int?Variant.From((long)next):Variant.From(next);number.Connect("interaction_started",Callable.From(Begin));number.Connect("preview_changed",Callable.From<double>(next=>Apply(Normalize(next),"preview",default,working)));number.Connect("drag_committed",Callable.From<double>(next=>{Apply(Normalize(next),"commit",origin,working);working=default;}));number.Connect("drag_cancelled",Callable.From(Restore));number.ValueChanged+=next=>Apply(Normalize(next));}
        else if(type==(int)Variant.Type.Color){var color=new LiveColorPickerButton();color.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;color.Color=current.AsColor();row.AddChild(color);color.Connect("interaction_started",Callable.From(Begin));color.Connect("preview_changed",Callable.From<Color>(next=>Apply(next,"preview",default,working)));color.Connect("drag_committed",Callable.From<Color,Color>((before,next)=>{Apply(next,"commit",origin,working);working=default;}));color.Connect("drag_cancelled",Callable.From<Color>(before=>Restore()));}
    }
}
