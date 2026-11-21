using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ImageRepairInteractionOperations:RefCounted
{
    private readonly ImageDocumentOperations _documents=new();private readonly ImageLayerOperations _layers=new();private readonly ImageMaterialResourceOperations _materials=new();private readonly ImageRepairEngineOperations _engine=new();
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    private static Control Canvas(RefCounted owner)=>owner.Get("canvas").As<Control>();
    private static Control Workspace(RefCounted owner)=>owner.Get("workspace").As<Control>();
    private static Node Engine(RefCounted owner)=>owner.Get("engine").As<Node>();
    private static Settings Config(RefCounted owner)=>owner.Get("config").AsGodotDictionary();
    private static void Assign(GArray array,GArray values){var copy=values.Duplicate();array.Clear();foreach(var value in copy)array.Add(value);}
    public Resource? layer(RefCounted owner){var canvas=Canvas(owner);var selected=canvas.Get("selected").AsGodotArray();return selected.Count==0?null:_documents.layer_for_id(canvas.Get("document").As<Resource>(),selected[selected.Count-1].AsString());}
    public Vector2 to_pixel(RefCounted owner,Vector2 point,Resource item){var projection=new ImageLayerProjection(item);return projection.Unproject(_documents.world_transform(Canvas(owner).Get("document").As<Resource>(),item).AffineInverse()*point)/projection.Dimensions*item.Get("texture").As<Texture2D>().GetSize();}
    public Vector2 to_screen(RefCounted owner,Vector2 pixel,Resource item){var canvas=Canvas(owner);var projection=new ImageLayerProjection(item);return canvas.Call("origin").AsVector2()+_documents.world_transform(canvas.Get("document").As<Resource>(),item)*projection.Project(pixel/item.Get("texture").As<Texture2D>().GetSize()*projection.Dimensions,new Vector2(-1,-1))*(float)canvas.Get("zoom").AsDouble();}
    public void begin(RefCounted owner,Resource item,Vector2 point,bool fill)
    {
        if(owner.Get("active").AsBool()||_engine.busy(Engine(owner)))return;
        var canvas=Canvas(owner);var studio=Workspace(owner);var config=Config(owner);studio.Call("_finish_pending");canvas.EmitSignal("gesture_started");Assign(owner.Get("_selected_before").AsGodotArray(),canvas.Get("selected").AsGodotArray());
        owner.Set("_owner",item);owner.Set("_document",canvas.Get("document"));using var source=item.Get("texture").As<Texture2D>().GetImage();var original=(Image)source.Duplicate();owner.Set("_original",original);var editing=(Image)original.Duplicate();owner.Set("_editing",editing);
        var selection=canvas.Get("selection").As<Image>();owner.Set("_selection",selection!=null&&(config["selection_only"].AsBool()||fill)?Variant.From(selection.Duplicate()):default(Variant));
        var mask=item.Get("mask").As<Texture2D>();if(mask!=null){using var image=mask.GetImage();owner.Set("_layer_mask",image.Duplicate());}else owner.Set("_layer_mask",default(Variant));
        owner.Set("_repair_new_layer",config["new_layer"].AsBool());var material=owner.Get("material").As<Resource>();bool editable=owner.Get("main_mode").AsString()=="texture"&&material.Get("application").AsString()=="continuous"&&Get(config,"editable_texture",true).AsBool();owner.Set("_editable_texture",editable);
        var document=canvas.Get("document").As<Resource>();var selected=canvas.Get("selected").AsGodotArray();var layers=document.Get("layers").AsGodotArray();var current=item;
        if(editable)
        {
            var properties=item.Get("properties").AsGodotDictionary();var existing=Get(properties,"texture_material").As<Resource>();
            if(existing==null||material.Get("alignment").AsString()=="stroke")
            {
                var overlay=_layers.copy_layer(item);overlay.Set("id",NewId());overlay.Set("label",material.Get("label").AsString()+" material");overlay.Set("kind","basic");overlay.Get("effects").AsGodotArray().Clear();overlay.Set("mask",default(Variant));overlay.Set("warp",default(Variant));overlay.Get("properties").AsGodotDictionary().Clear();overlay.Set("texture",item.Get("texture"));overlay.Set("paint_base",item.Get("texture"));layers.Add(overlay);selected.Clear();selected.Add(overlay.Get("id"));current=overlay;owner.Set("_owner",overlay);
                existing=_materials.copy_material(material);existing.Set("source",item.Get("texture"));overlay.Get("properties").AsGodotDictionary()["texture_material"]=existing;
                if(material.Get("alignment").AsString()=="stroke"){existing.Set("mapping_origin",point/(Vector2)original.GetSize()*item.Get("dimensions").AsVector2());using var rng=new RandomNumberGenerator{Seed=unchecked((uint)GD.Hash(new GArray{point,Get(material.Get("parameters").AsGodotDictionary(),"seed",0)}))};existing.Set("rotation",existing.Get("rotation").AsDouble()+rng.RandfRange(-1,1)*material.Get("random_rotation").AsDouble());}
            }
            var coverage=existing.Get("coverage").As<Texture2D>();Image coverageBase;if(coverage!=null){using var image=coverage.GetImage();coverageBase=(Image)image.Duplicate();}else coverageBase=Image.CreateEmpty(original.GetWidth(),original.GetHeight(),false,Image.Format.Rgba8);
            owner.Set("_coverage_base",coverageBase);editing=(Image)coverageBase.Duplicate();owner.Set("_editing",editing);existing.Set("coverage",ImageTexture.CreateFromImage(editing));
        }
        if(config["new_layer"].AsBool()&&!editable)
        {
            var copy=_layers.copy_layer(item);copy.Set("id",NewId());copy.Set("label",owner.Get("mode").AsString().Replace("_"," ").Capitalize()+" repair");copy.Set("kind","basic");copy.Get("effects").AsGodotArray().Clear();copy.Set("mask",default(Variant));copy.Set("warp",default(Variant));copy.Set("opacity",1.0);copy.Get("properties").AsGodotDictionary().Remove("texture_recipe");editing=Image.CreateEmpty(original.GetWidth(),original.GetHeight(),false,Image.Format.Rgba8);owner.Set("_editing",editing);copy.Set("texture",ImageTexture.CreateFromImage(editing));copy.Set("paint_base",copy.Get("texture"));layers.Add(copy);selected.Clear();selected.Add(copy.Get("id"));current=copy;owner.Set("_owner",copy);
        }
        owner.Set("_points",new[]{point});owner.Set("_last",point);owner.Set("_area",new Rect2I());owner.Set("_changed",false);owner.Set("active",true);owner.Set("ending",false);owner.Set("_pending",true);owner.Set("_pressures",new[]{1f});if(!editable)current.Set("texture",ImageTexture.CreateFromImage(editing));owner.Set("_anchor",point);
        string mode=owner.Get("mode").AsString();if(owner.Get("source_image").AsGodotObject()==null||(mode is "spot" or "pattern_heal" or "patch")&&config["source_mode"].AsString()=="nearby"){owner.Set("source_image",original);owner.Set("source_area",new Rect2I(Vector2I.Zero,original.GetSize()));owner.Set("source_point",point);}
        if(config["aligned"].AsBool()){if(!owner.Get("_has_alignment").AsBool()){owner.Set("_aligned_offset",owner.Get("source_point").AsVector2()-point);owner.Set("_has_alignment",true);}owner.Set("_stroke_source_anchor",point+owner.Get("_aligned_offset").AsVector2());}else owner.Set("_stroke_source_anchor",owner.Get("source_point"));
        if(fill){owner.Set("_pending",false);owner.Set("selection_preview",true);queue(owner,true,false);}canvas.Set("_drag","repair");canvas.EmitSignal("hint_changed",(owner.Get("main_mode").AsString()=="texture"?"Painting "+material.Get("label").AsString():"Repair preview…")+" · Esc cancels");
    }
    private static string NewId()=>ActorData.new_id();
    public void process(RefCounted owner){if(!owner.Get("active").AsBool()||owner.Get("ending").AsBool()||!owner.Get("_pending").AsBool()||Canvas(owner).Get("_drag").AsString()=="pan")return;queue(owner,false,false);owner.Set("_pending",false);}
    public void queue(RefCounted owner,bool fill,bool final)
    {
        var canvas=Canvas(owner);var config=Config(owner);var original=owner.Get("_original").As<Image>();var extent=original.GetSize();double radius=config["size"].AsDouble()*.5;var material=owner.Get("material").As<Resource>();bool texture=owner.Get("main_mode").AsString()=="texture",editable=owner.Get("_editable_texture").AsBool();if(texture&&material.Get("application").AsString()=="scatter")radius*=1+material.Get("jitter").AsDouble()*2;
        var points=owner.Get("_points").AsVector2Array();var bounds=new Rect2(points[0],Vector2.Zero);foreach(var p in points)bounds=bounds.Expand(p);var area=new Rect2I((Vector2I)(bounds.Position.Floor()-Vector2.One*(float)radius),(Vector2I)(bounds.Size.Ceil()+Vector2.One*(float)(radius*2))).Intersection(new Rect2I(Vector2I.Zero,extent));var fillBounds=owner.Get("_fill_bounds").AsRect2I();if(fill)area=fillBounds.HasArea()?fillBounds.Intersection(new Rect2I(Vector2I.Zero,extent)):new Rect2I(Vector2I.Zero,extent);owner.Set("_area",area);if(!area.HasArea())return;
        var settings=config.Duplicate(true);if(texture)
        {
            settings["rotation"]=material.Get("rotation");settings["scale"]=material.Get("texture_size").AsDouble()/64;settings["sample_shape"]="rectangle";settings["behavior"]="exact";foreach(string key in new[]{"application","jitter","random_rotation","random_scale","follow_direction"})settings[key]=material.Get(key);settings["material_blending"]=material.Get("blending");settings["stamp_extent"]=material.Get("texture_size");if(material.Get("application").AsString()!="continuous")settings["scale"]=material.Get("texture_size").AsDouble()/256;else if(!editable){settings["scale"]=1.0;settings["rotation"]=0.0;settings["material_blending"]="replace";}
        }
        settings["sample_points"]=owner.Get("source_points");settings["pressures"]=owner.Get("_pressures");settings["source_center"]=owner.Get("source_point");settings["new_layer"]=owner.Get("_repair_new_layer");if(!final)settings["quality"]=0;
        string mode=owner.Get("mode").AsString();var item=owner.Get("_owner").As<Resource>();var document=canvas.Get("document").As<Resource>();var frame=_documents.world_transform(document,item);
        var job=new Settings{["kind"]=mode,["original"]=original,["sample"]=owner.Get("source_image"),["source_area"]=owner.Get("source_area"),["source_anchor"]=owner.Get("_stroke_source_anchor"),["destination_anchor"]=owner.Get("_anchor"),["settings"]=settings,["area"]=area,["points"]=points,["fill"]=fill,["automatic"]=(mode is "spot" or "pattern_heal" or "patch")&&config["source_mode"].AsString()=="nearby",["reference"]=_layers.copy_layer(item),["frame"]=frame,["layer_mask"]=owner.Get("_layer_mask"),["editable_texture"]=editable};
        if(editable)job["prior_coverage"]=owner.Get("_coverage_base");if(owner.Get("_selection").AsGodotObject()!=null){job["selection"]=owner.Get("_selection");job["selection_inverse"]=canvas.Get("selection_inverse");if(owner.Call("_has_selection_inverse").AsBool()){var reference=document.Get("pixel_selection_reference").As<Resource>();job["selection_reference"]=reference==null?default(Variant):Variant.From(_layers.copy_layer(reference));job["selection_world"]=document.Get("pixel_selection_reference_world");}}
        if(fill&&owner.Get("_fill_mask").AsGodotObject()!=null)job["local_selection"]=owner.Get("_fill_mask");if(settings["sample_mode"].AsString()!="current")job["sample_basis"]=frame.ScaledLocal(item.Get("dimensions").AsVector2()/(Vector2)original.GetSize());owner.Set("_latest",_engine.submit(Engine(owner),job));
    }
    public void finish(RefCounted owner)
    {
        if(!owner.Get("active").AsBool())return;bool selection=owner.Get("selection_preview").AsBool();owner.Set("selection_preview",false);string mode=owner.Get("mode").AsString();if(mode is "patch" or "pattern_heal"||(mode is "pattern_fill" or "procedural")&&Config(owner)["behavior"].AsString()=="synthesis")queue(owner,selection,true);else if(owner.Get("_pending").AsBool()){queue(owner,false,false);owner.Set("_pending",false);}if(!owner.Get("_area").AsRect2I().HasArea()){cancel(owner);return;}owner.Set("ending",true);on_idle(owner);
    }
    public void cancel(RefCounted owner)
    {
        _engine.cancel(Engine(owner));owner.Set("_generation_target","");owner.Set("_material_generation",owner.Get("_material_generation").AsInt64()+1);foreach(string key in new[]{"selection_preview","sampling","_patch_drag","_sample_down","pick_source"})owner.Set(key,false);if(!owner.Get("active").AsBool())return;foreach(string key in new[]{"active","ending","_pending"})owner.Set(key,false);var canvas=Canvas(owner);canvas.Set("_drag","");canvas.EmitSignal("gesture_cancelled");Assign(canvas.Get("selected").AsGodotArray(),owner.Get("_selected_before").AsGodotArray());canvas.EmitSignal("selection_changed");canvas.QueueRedraw();
    }
    public void on_idle(RefCounted owner)
    {
        if(!owner.Get("active").AsBool()||!owner.Get("ending").AsBool()||_engine.busy(Engine(owner))||owner.Get("_completed").AsInt64()!=owner.Get("_latest").AsInt64())return;owner.Set("active",false);owner.Set("ending",false);var canvas=Canvas(owner);canvas.Set("_drag","");if(owner.Get("_changed").AsBool()){if(!owner.Get("_editable_texture").AsBool())owner.Get("_owner").AsGodotObject().Set("texture",ImageTexture.CreateFromImage(owner.Get("_editing").As<Image>()));canvas.EmitSignal("gesture_finished");}else canvas.EmitSignal("gesture_cancelled");canvas.EmitSignal("hint_changed",owner.Get("main_mode").AsString()=="texture"?"Texture paint complete":"Repair complete");canvas.QueueRedraw();
    }
}
