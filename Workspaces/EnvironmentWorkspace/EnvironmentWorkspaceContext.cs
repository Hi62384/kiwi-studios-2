using Godot;
using System;
using System.Linq;

public partial class EnvironmentWorkspaceOperations
{
    private static readonly string[] BrushTools={"Raise","Lower","Smooth","Flatten","Level to height","Terrace","Noise","Ridge","Valley","Pinch / sharpen","Relax","Erode brush","Stamp"};
    public void refresh_context(Control owner)
    {
        var parent=owner.Get("_context").As<HBoxContainer>();Clear(parent);var canvas=owner.Get("canvas").As<Control>();string tool=canvas.Get("environment_tool").AsString();
        if(BrushTools.Contains(tool)||new[]{"Paint material","Paint biome","Erase biome","Paint scatter","Erase scatter"}.Contains(tool))
        {
            parent.AddChild(new Label {Text=tool});foreach(var spec in new[]{("Radius","brush_radius",.05,1000.0,.05),("Strength","brush_strength",.001,10.0,.01),("Falloff","brush_falloff",.01,8.0,.01),("Spacing","brush_spacing",.05,1.0,.05)})Number(parent,spec.Item1,canvas.Get(spec.Item2).AsDouble(),spec.Item3,spec.Item4,spec.Item5,value=>canvas.Set(spec.Item2,value));
            if(tool is "Paint biome" or "Erase biome")
            {
                var editor=canvas.Get("biome_tool").As<RefCounted>();var info=editor.Call("target").AsGodotDictionary();if(info.Count>0){var chooser=new OptionButton {FitToLongestItem=false};parent.AddChild(chooser);var biomes=info["terrain"].As<Resource>().Get("biomes").As<Resource>();foreach(var entry in biomes.Get("definitions").AsGodotArray()){var definition=entry.AsGodotDictionary();if(!Get(definition,"enabled",true).AsBool()||Get(definition,"domain","surface").AsString()!="surface")continue;string id=definition["id"].AsString();chooser.AddItem(Get(definition,"name","Biome").AsString());chooser.SetItemMetadata(chooser.ItemCount-1,id);if(id==editor.Get("biome_id").AsString())chooser.Select(chooser.ItemCount-1);}chooser.ItemSelected+=index=>{editor.Set("biome_id",chooser.GetItemMetadata((int)index).AsString());canvas.Call("request_sync");};}
            }
            if(tool=="Level to height")Number(parent,"Height",canvas.Get("brush_target_height").AsDouble(),-10000,10000,.1,value=>canvas.Set("brush_target_height",value));if(tool=="Terrace")Number(parent,"Step",canvas.Get("brush_terrace_step").AsDouble(),.01,1000,.1,value=>canvas.Set("brush_terrace_step",value));
            var settings=new MenuButton {Text="Brush ▾"};parent.AddChild(settings);var popup=settings.GetPopup();string[] keys={"brush_square","brush_symmetry_x","brush_symmetry_z"};string[] labels={"Square brush","Mirror X","Mirror Z"};for(int index=0;index<3;index++){popup.AddCheckItem(labels[index]);popup.SetItemChecked(index,canvas.Get(keys[index]).AsBool());}popup.HideOnCheckableItemSelection=false;popup.IdPressed+=index=>{string key=keys[index];bool value=!canvas.Get(key).AsBool();canvas.Set(key,value);popup.SetItemChecked((int)index,value);};if(tool=="Stamp"){string path=canvas.Get("stamp_path").AsString();Button(parent,path.Length==0?"Choose stamp…":path.GetFile(),()=>owner.Call("_choose_stamp"));}
        }
        else if(tool is "Cave dig" or "Cave fill" or "Cave smooth")
        {parent.AddChild(new Label {Text=tool});Number(parent,"Radius",canvas.Get("brush_radius").AsDouble(),.1,100,.1,value=>canvas.Set("brush_radius",value));var editor=canvas.Get("cave_tool").As<RefCounted>();Number(parent,"Strength",editor.Get("strength").AsDouble(),.05,1,.05,value=>editor.Set("strength",value));}
        else if(tool is "Cave path" or "Water paths")parent.AddChild(new Label {Text="Drag a point · Shift-click inserts · Right-click removes · Esc cancels"});
        else if(tool=="Place"){string asset=canvas.Get("placement_asset").AsString();Button(parent,asset.Length>0?asset.GetFile():"Choose a model…",()=>owner.Call("choose_asset"));}
        parent.Visible=parent.GetChildCount()>0;
    }
}
