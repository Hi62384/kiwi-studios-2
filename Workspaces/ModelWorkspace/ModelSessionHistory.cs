using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ModelSessionHistory : RefCounted
{
    private static Variant Value(Settings values,string key,Variant fallback)=>values.TryGetValue(key,out var value)?value:fallback;
    private static void Changed(RefCounted owner)=>owner.EmitSignal("changed");
    private static void Increment(RefCounted owner,string field)=>owner.Set(field,owner.Get(field).AsInt64()+1);
    private static bool ScriptType(Resource value,string path)
    {var script=value.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    public Resource? primary(RefCounted owner)
    {var selected=owner.Get("selected").AsGodotArray();return selected.Count==0?null:owner.Get("document").As<Resource>().Call("component",selected[^1]).As<Resource>();}
    public Settings snapshot(RefCounted owner)=>new(){["document"]=owner.Get("document").As<Resource>().Call("snapshot"),["selected"]=owner.Get("selected").AsGodotArray().Duplicate(false),["mode"]=owner.Get("mode"),["elements"]=owner.Get("elements").AsInt32Array(),["rig_selection"]=owner.Get("rig_selection").AsGodotDictionary().Duplicate(false)};
    public void restore(RefCounted owner,Settings state)
    {
        owner.Set("document",state["document"].As<Resource>().Call("snapshot"));var restoredSelection=state["selected"].AsGodotArray().Duplicate(false);var selected=owner.Get("selected").AsGodotArray();selected.Clear();foreach(Variant value in restoredSelection)selected.Add(value);
        owner.Set("mode",state["mode"]);owner.Set("elements",state["elements"].AsInt32Array());owner.Set("rig_selection",Value(state,"rig_selection",new Settings()).AsGodotDictionary().Duplicate(false));Changed(owner);
    }
    public void begin(RefCounted owner)
    {owner.Call("_invoke_pending_source_cancel");if(owner.Get("_gesture").AsGodotDictionary().Count==0)owner.Set("_gesture",owner.Call("snapshot"));}
    public void cancel(RefCounted owner)
    {var gesture=owner.Get("_gesture").AsGodotDictionary();if(gesture.Count==0)return;owner.Set("_gesture",new Settings());owner.Call("restore",gesture);}
    public void commit(RefCounted owner,string label)
    {
        var gesture=owner.Get("_gesture").AsGodotDictionary();if(gesture.Count==0)return;
        if(owner.Call("_signature",owner.Get("document")).AsInt64()==owner.Call("_signature",gesture["document"]).AsInt64()){owner.Set("_gesture",new Settings());Changed(owner);return;}
        var undo=owner.Get("_undo").AsGodotArray();undo.Add(new Settings{["label"]=label,["before"]=gesture,["after"]=owner.Call("snapshot")});owner.Set("_gesture",new Settings());owner.Get("_redo").AsGodotArray().Clear();
        long budget=0;for(int i=undo.Count-1;i>=0;i--)
        {
            var entry=undo[i].AsGodotDictionary();if(entry.ContainsKey("custom")){budget+=Value(entry,"cost",0).AsInt64();continue;}
            budget+=owner.Call("_history_entry_cost",entry).AsInt64();if(budget>1500000||undo.Count>40){undo.RemoveAt(0);break;}
        }
        owner.Set("dirty",true);Increment(owner,"revision");owner.Set("last_command",label);Changed(owner);
    }
    public void undo(RefCounted owner)
    {
        if(owner.Call("_pending_source_valid").AsBool()){Increment(owner,"history_revision");owner.Call("_invoke_pending_source_cancel");return;}
        if(owner.Get("_gesture").AsGodotDictionary().Count>0){Increment(owner,"history_revision");owner.Call("cancel");return;}
        var undo=owner.Get("_undo").AsGodotArray();if(undo.Count==0)return;Increment(owner,"history_revision");var entry=undo[^1].AsGodotDictionary();undo.RemoveAt(undo.Count-1);owner.Get("_redo").AsGodotArray().Add(entry);owner.Set("dirty",true);Increment(owner,"revision");
        if(entry.ContainsKey("custom")){owner.Call("_invoke_custom_history",entry,"undo");Changed(owner);}else owner.Call("restore",entry["before"]);
    }
    public void redo(RefCounted owner)
    {
        if(owner.Call("_pending_source_valid").AsBool()){Increment(owner,"history_revision");owner.Call("_invoke_pending_source_cancel");return;}
        var redo=owner.Get("_redo").AsGodotArray();if(redo.Count==0)return;Increment(owner,"history_revision");var entry=redo[^1].AsGodotDictionary();redo.RemoveAt(redo.Count-1);owner.Get("_undo").AsGodotArray().Add(entry);owner.Set("dirty",true);Increment(owner,"revision");
        if(entry.ContainsKey("custom")){owner.Call("_invoke_custom_history",entry,"redo");Changed(owner);}else owner.Call("restore",entry["after"]);
    }
    public void finish_custom_action(RefCounted owner,string label)
    {var undo=owner.Get("_undo").AsGodotArray();while(undo.Count>40)undo.RemoveAt(0);owner.Set("dirty",true);Increment(owner,"revision");owner.Set("last_command",label);Changed(owner);}
    public long _signature(Resource data)
    {
        var entries=new GArray();
        foreach(Variant value in data.Get("components").AsGodotArray())
        {
            var item=value.As<Resource>();var geometry=new GArray();var mesh=item.Get("mesh").As<Resource>();if(mesh!=null)foreach(string key in new[]{"vertices","faces","uv","materials","smooth"})geometry.Add(mesh.Get(key));
            var growth=item.Get("growth").As<Resource>();
            if(growth!=null)
            {
                var appearance=growth.Get("appearance").As<Resource>();if(appearance!=null)geometry.Add(appearance.Call("signature"));var style=growth.Get("growth_style").As<Resource>();if(style!=null)geometry.Add(new GArray{style.Get("asset_id"),style.Get("title"),style.Get("values")});
                geometry.Add(new GArray{growth.Get("rendering"),growth.Get("brush_presets"),growth.Get("individual")});
                foreach(Variant regionValue in growth.Get("regions").AsGodotArray())
                {
                    var region=regionValue.AsGodotDictionary();var materialValue=Value(region,"material",default);var regionStyleValue=Value(region,"style",default);var material=materialValue.VariantType==Variant.Type.Object?materialValue.As<Resource>():null;var regionStyle=regionStyleValue.VariantType==Variant.Type.Object?regionStyleValue.As<Resource>():null;
                    geometry.Add(new GArray{Value(region,"id",default),Value(region,"name",default),Value(region,"roots",default),Value(region,"faces",default),Value(region,"enabled",true),Value(region,"all",false),material!=null&&ScriptType(material,"res://Workspaces/ModelWorkspace/growth/growth_material.gd")?material.Call("signature"):Variant.From(0),regionStyle!=null&&ScriptType(regionStyle,"res://Workspaces/ModelWorkspace/growth/growth_style.gd")?Variant.From(new GArray{regionStyle.Get("asset_id"),regionStyle.Get("title"),regionStyle.Get("values")}):Variant.From(new Settings())});
                }
            }
            var entry=new GArray();foreach(string key in new[]{"id","title","parent_id","transform","pivot","visible","locked","generator","parameters","modifiers","surface_materials"})entry.Add(item.Get(key));entry.Add(geometry);foreach(string key in new[]{"is_skeleton","bones","skin","skin_mesh","skeleton_id"})entry.Add(item.Get(key));var binding=item.Get("binding").As<Resource>();entry.Add(binding!=null?binding.Call("signature"):Variant.From(0));foreach(string key in new[]{"geometry_source","geometry_source_hash","structural"})entry.Add(item.Get(key));entry.Add(growth!=null?new GArray{growth.Get("source_id"),growth.Get("settings"),growth.Get("groom"),growth.Get("groom_layers"),growth.Get("guides"),growth.Get("groom_enabled")}:new GArray());entries.Add(entry);
        }
        return GD.Hash(entries);
    }
}
