using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ImageRepairInteractionOperations
{
    private readonly NaturalMaterialDefinitionOperations _definitions=new();private readonly ImageProceduralTextureOperations _procedural=new();
    public void on_preview(RefCounted owner,Settings result)
    {
        var canvas=Canvas(owner);var workspace=Workspace(owner);var config=Config(owner);
        if(result["kind"].AsString()=="generate")
        {
            if(result["sequence"].AsInt64()!=owner.Get("_generation_sequence").AsInt64())return;
            var recipe=owner.Get("recipe").As<Resource>();var image=result["image"].As<Image>();owner.Set("_cached_procedural",image);owner.Set("_procedural_key",GD.Hash(new GArray{recipe.Get("kind"),recipe.Get("settings")}));owner.Set("source_image",image);owner.Set("source_area",new Rect2I(Vector2I.Zero,image.GetSize()));owner.Set("source_point",Vector2.Zero);owner.Set("pattern_path","");config["sample_mode"]="current";config["sample_shape"]="rectangle";owner.Set("source_points",Array.Empty<Vector2>());
            string targetId=owner.Get("_generation_target").AsString();var document=workspace.Get("document").As<Resource>();
            if(targetId.Length>0&&document==owner.Get("_generation_document").AsGodotObject())
            {
                if(targetId=="::new::")workspace.Call("_action",Callable.From(()=>
                {
                    var target=_layers.create("image",document.Get("canvas_size").AsVector2I());target.Set("label",recipe.Get("kind").AsString().Capitalize()+" texture");target.Set("texture",ImageTexture.CreateFromImage(image));target.Set("paint_base",target.Get("texture"));target.Get("properties").AsGodotDictionary()["texture_recipe"]=_procedural.copy_recipe(recipe);target.Set("opacity",config["opacity"]);target.Set("blend",Get(config,"blend",0));target.Set("clip_to_below",config["clip_alpha"]);document.Get("layers").AsGodotArray().Add(target);var selected=canvas.Get("selected").AsGodotArray();selected.Clear();selected.Add(target.Get("id"));
                }));
                else{var target=_documents.layer_for_id(document,targetId);if(target!=null)workspace.Call("_action",Callable.From(()=>{target.Set("texture",ImageTexture.CreateFromImage(image));target.Get("properties").AsGodotDictionary()["texture_recipe"]=_procedural.copy_recipe(recipe);}));}
            }
            owner.Set("_generation_target","");canvas.EmitSignal("hint_changed","Procedural texture ready");owner.EmitSignal("settings_changed");return;
        }
        var item=owner.Get("_owner").As<Resource>();if(!owner.Get("active").AsBool()||canvas.Get("document").AsGodotObject()!=owner.Get("_document").AsGodotObject()||_documents.layer_for_id(canvas.Get("document").As<Resource>(),item.Get("id").AsString())!=item)return;
        var editing=owner.Get("_editing").As<Image>();bool editable=owner.Get("_editable_texture").AsBool();var patch=result[editable?"coverage":"image"].As<Image>();editing.BlitRect(patch,new Rect2I(Vector2I.Zero,patch.GetSize()),result["area"].AsRect2I().Position);
        if(editable)item.Get("properties").AsGodotDictionary()["texture_material"].AsGodotObject().Set("coverage",ImageTexture.CreateFromImage(editing));else item.Get("texture").As<ImageTexture>().Update(editing);
        owner.Set("_completed",result["sequence"]);owner.Set("_changed",true);canvas.EmitSignal("gesture_changed");canvas.QueueRedraw();
    }
    public void refresh_selection_preview(RefCounted owner){if(owner.Get("selection_preview").AsBool()&&owner.Get("active").AsBool()){if(owner.Get("_repair_new_layer").AsBool()!=Config(owner)["new_layer"].AsBool()){cancel(owner);owner.Call("fill_selection");}else queue(owner,true,false);}}
    public void configure(RefCounted owner,string key,Variant value){Config(owner)[key]=value;refresh_selection_preview(owner);}
    public void choose_material(RefCounted owner,string id)
    {
        var material=owner.Get("material").As<Resource>();var instances=owner.Get("material_instances").AsGodotDictionary();if(material!=null)instances[material.Get("material_id")]=_materials.copy_material(material);var saved=Get(instances,id).As<Resource>();owner.Set("material",saved!=null?_materials.copy_material(saved):_definitions.create(id));var recent=new System.Collections.Generic.List<string>(owner.Get("recent").AsStringArray());recent.Remove(id);recent.Insert(0,id);if(recent.Count>20)recent.RemoveRange(20,recent.Count-20);owner.Set("recent",recent.ToArray());owner.Set("texture_source","procedural");apply_material_settings(owner,false);owner.Call("refresh_material");owner.EmitSignal("settings_changed");
    }
    public void switch_mode(RefCounted owner,string next)
    {
        string previous=owner.Get("main_mode").AsString();if(next==previous)return;cancel(owner);var saved=owner.Get("mode_settings").AsGodotDictionary();saved[previous]=Config(owner).Duplicate(true);owner.Set("main_mode",next);if(saved.ContainsKey(next))Config(owner).Merge(saved[next].AsGodotDictionary(),true);owner.Set("source_image",default(Variant));owner.Set("_has_alignment",false);if(next=="texture")owner.Call("refresh_material");
    }
    public void apply_material_settings(RefCounted owner,bool live)
    {
        var item=layer(owner);if(item==null)return;var properties=item.Get("properties").AsGodotDictionary();var old=Get(properties,"texture_material").As<Resource>();if(old==null)return;
        void Operation(){var current=properties["texture_material"].As<Resource>();var updated=_materials.copy_material(owner.Get("material").As<Resource>());updated.Set("coverage",current.Get("coverage"));updated.Set("source",current.Get("source"));properties["texture_material"]=updated;}
        var workspace=Workspace(owner);if(live){workspace.Call("_begin");Operation();workspace.Call("_preview");}else workspace.Call("_action",Callable.From(Operation));
    }
    public void generate(RefCounted owner,string targetId)
    {
        var document=Workspace(owner).Get("document").As<Resource>();owner.Set("_generation_target",targetId);owner.Set("_generation_document",document);var item=layer(owner);var extent=targetId=="::new::"?document.Get("canvas_size").AsVector2I():item!=null&&targetId.Length>0?(Vector2I)item.Get("dimensions").AsVector2().Ceil():new Vector2I(256,256);double ratio=Math.Min(1,1024.0/Math.Max(extent.X,extent.Y));var job=new Settings{["kind"]="generate",["recipe"]=_procedural.copy_recipe(owner.Get("recipe").As<Resource>()),["size"]=((Vector2I)((Vector2)extent*(float)ratio).Round()).Max(Vector2I.One),["target"]=targetId};owner.Set("_generation_sequence",_engine.submit(Engine(owner),job));Canvas(owner).EmitSignal("hint_changed","Generating texture…");
    }
}
