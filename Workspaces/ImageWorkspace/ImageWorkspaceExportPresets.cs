using Godot;
using System;
public partial class ImageWorkspaceOperations
{
    public void export_presets_panel(Control owner)
    {
        var ui=workflow_window(owner,"Quick export presets",new Vector2(650,430));var body=ui["body"].As<VBoxContainer>();var presets=panel_card(body,"Image sizes","Uses the current output folder and adds a size suffix. If no output exists, choose a destination once.");var buttons=new HFlowContainer();presets.AddChild(buttons);var size=Document(owner).Get("canvas_size").AsVector2I();foreach(var entry in new[]{("Original PNG",size,"original","png"),("2× PNG",size*2,"2x","png"),("½ PNG",(Vector2I)((Vector2)size*.5f),"half","png"),("Thumbnail 512",new Vector2I(512,Mathf.RoundToInt(512.0*size.Y/size.X)),"thumb","webp"),("Square 1080",new Vector2I(1080,1080),"square","png"),("Story 1080×1920",new Vector2I(1080,1920),"story","jpg")})button(owner,buttons,entry.Item1,Callable.From(()=>owner.Call("_quick_export",entry.Item2,entry.Item3,entry.Item4)),"","");var special=panel_card(body,"Layer exports","");var actions=new HFlowContainer();special.AddChild(actions);button(owner,actions,"Export selected layer…",new Callable(owner,"_export_selected_layer"),"","");button(owner,actions,"Export every top-level layer…",new Callable(owner,"_export_layers"),"","");button(owner,actions,"Custom export…",Callable.From(()=>export_image(owner)),"","");ui["popup"].As<PopupPanel>().PopupCentered();
    }
    public void complete_quick_export(Control owner,Image? bitmap,Vector2I size,string destination,string suffix,string format)
    {
        if(bitmap==null)return;using var copy=(Image)bitmap.Duplicate();copy.Resize(Math.Max(1,size.X),Math.Max(1,size.Y),Image.Interpolation.Lanczos);string output=Document(owner).Get("output_path").AsString().Length==0?destination:destination.GetBaseName()+"-"+suffix+"."+format;var error=write_bitmap(copy,output);owner.Get("status").As<Label>().Text=error==Error.Ok?"Exported "+output.GetFile():"Export failed";if(error==Error.Ok)owner.Call("_refresh_project_files");
    }
}
