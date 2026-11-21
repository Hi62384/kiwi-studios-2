using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderWorkspaceOperations
{
    private static Variant Value(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public void open_source(Control owner,Variant source,Settings state,Settings binding)
    {
        owner.Set("_loading",true);owner.Set("current_source",source);string path=Value(state,"path",source.VariantType==Variant.Type.String?source:Variant.From("")).AsString();owner.Set("current_path",path);bool requires=Value(state,"requires_path",false).AsBool();owner.Set("requires_path",requires);Item<Button>(owner,"load_shader_button").Visible=requires&&path.Length==0;
        var code=Code(owner);if(state.TryGetValue("code",out var text))code.Text=text.AsString();else if(source.VariantType==Variant.Type.Object&&source.AsGodotObject() is Shader shader)code.Text=shader.Code;else{using var file=FileAccess.Open(path,FileAccess.ModeFlags.Read);code.Text=file!=null?file.GetAsText():"shader_type spatial;\n\nvoid fragment() {\n    ALBEDO = vec3(0.7);\n}\n";}
        var editor=Item<Control>(owner,"editor");editor.Set("current_shader",source.VariantType==Variant.Type.Object&&source.AsGodotObject() is Shader?source:default);editor.Set("current_path",path);editor.Get("title").As<Label>().Text=document_title(owner);var shape=Item<OptionButton>(owner,"shape_picker");shape.Select(shape.ItemCount>0?Math.Clamp(Value(state,"shape",0).AsInt32(),0,shape.ItemCount-1):-1);foreach(var field in new[]{("_mesh_mode","mesh_mode","shape"),("_mesh_path","mesh_path",""),("_environment_path","environment_path",""),("_canvas_image_path","canvas_image_path","")})owner.Set(field.Item1,Value(state,field.Item2,field.Item3));
        owner.Set("linked_parameter_reader",Value(binding,"reader",default(Callable)));owner.Set("linked_parameter_writer",Value(binding,"writer",default(Callable)));bool valid=Binding(owner,"both"),linked=valid&&Value(state,"parameters_linked",true).AsBool();var link=Item<CheckButton>(owner,"parameter_link");link.Visible=valid;owner.Set("parameters_linked",linked);link.SetPressedNoSignal(linked);if(linked){var values=owner.Call("_read_linked_parameters");owner.Set("parameter_values",values.VariantType==Variant.Type.Dictionary?values.AsGodotDictionary().Duplicate(true):new Settings());}else owner.Set("parameter_values",Value(state,"parameters",new Settings()).AsGodotDictionary().Duplicate(true));Item<VSplitContainer>(owner,"parameter_code_split").SplitOffsets=new[]{Value(state,"parameter_split",185).AsInt32()};if(state.TryGetValue("camera_transform",out var camera))Item<Node3D>(owner,"camera_rig").Transform=camera.AsTransform3D();owner.Set("_loading",false);apply_environment(owner);rebuild_mesh(owner);code_changed(owner);code.GrabFocus();
    }
    public Settings capture_state(Control owner)
    {
        var split=Item<VSplitContainer>(owner,"parameter_code_split").SplitOffsets;return new Settings {["code"]=Code(owner).Text,["path"]=owner.Get("current_path"),["source"]=owner.Get("current_source"),["shape"]=Item<OptionButton>(owner,"shape_picker").Selected,["mesh_mode"]=owner.Get("_mesh_mode"),["mesh_path"]=owner.Get("_mesh_path"),["environment_path"]=owner.Get("_environment_path"),["camera_transform"]=Item<Node3D>(owner,"camera_rig").Transform,["canvas_image_path"]=owner.Get("_canvas_image_path"),["parameter_split"]=split.Length>0?split[0]:0,["parameters"]=owner.Get("parameter_values").AsGodotDictionary().Duplicate(true),["parameters_linked"]=owner.Get("parameters_linked"),["requires_path"]=owner.Get("requires_path")};
    }
    public ShaderWorkspaceFileJob? save(Control owner)
    {
        if(owner.Get("requires_path").AsBool())return file_action(owner,"save_as",new StringName(""),false);commit_linked_parameters(owner);string path=owner.Get("current_path").AsString();var source=owner.Get("current_source");if(path.Length==0){if(source.VariantType==Variant.Type.Object&&source.AsGodotObject() is Shader shader){shader.Code=Code(owner).Text;shader.EmitChanged();owner.EmitSignal("shader_saved",shader);Item<Label>(owner,"status").Text="Saved embedded shader";}else return file_action(owner,"save_as",new StringName(""),false);return null;}
        using(var file=FileAccess.Open(path,FileAccess.ModeFlags.Write)){if(file==null){Item<Label>(owner,"status").Text="Could not write shader file.";return null;}file.StoreString(Code(owner).Text);file.Flush();if(file.GetError()!=Error.Ok){Item<Label>(owner,"status").Text="Could not write shader file.";return null;}}ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Replace);owner.EmitSignal("shader_saved",path);Item<Label>(owner,"status").Text="Saved · "+path.GetFile();return null;
    }
    public ShaderWorkspaceFileJob file_action(Control owner,string kind,StringName parameter,bool fromClipboard)
    {var job=new ShaderWorkspaceFileJob();owner.AddChild(job);job.start(owner,kind,parameter,fromClipboard);return job;}
}
