using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class ImageRepairInteractionOperations
{
    public Resource? prepare_fill(RefCounted owner)
    {
        if(owner.Get("active").AsBool()&&owner.Get("selection_preview").AsBool()){queue(owner,true,false);return null;}
        var item=layer(owner);var canvas=Canvas(owner);if(item==null||item.Get("texture").AsGodotObject()==null||canvas.Get("selection").AsGodotObject()==null){canvas.EmitSignal("hint_changed","Select pixels on a raster layer first");return null;}
        if(owner.Get("main_mode").AsString()=="repair"&&ScriptIs(Get(item.Get("properties").AsGodotDictionary(),"texture_material").AsGodotObject(),"texture_material")){canvas.EmitSignal("hint_changed","Bake this material layer before repairing pixels");return null;}return item;
    }
    public bool accept_fill_mask(RefCounted owner,Resource item,Resource document,Texture2D? texture)
    {
        var canvas=Canvas(owner);if(texture==null||canvas.Get("document").AsGodotObject()!=document||layer(owner)!=item)return false;
        var mask=texture.GetImage();var image=item.Get("texture").As<Texture2D>();if(mask.GetSize()!=(Vector2I)image.GetSize())mask.Resize(image.GetWidth(),image.GetHeight(),Image.Interpolation.Bilinear);owner.Set("_fill_mask",mask);var bounds=mask.GetUsedRect();owner.Set("_fill_bounds",bounds);if(!bounds.HasArea()){canvas.EmitSignal("hint_changed","Select pixels first");return false;}owner.Set("_fill_bounds",bounds.Grow(4));owner.Set("mode",owner.Get("main_mode").AsString()=="texture"?"pattern_fill":owner.Get("repair_source").AsString()=="nearby"?"patch":owner.Get("repair_method").AsString()=="exact"?"clone":"heal");return true;
    }
    public void complete_fill(RefCounted owner,Resource item)
    {
        var config=Config(owner);config["source_mode"]=owner.Get("main_mode").AsString()=="repair"&&owner.Get("repair_source").AsString()=="nearby"?"nearby":"manual";
        if(owner.Get("mode").AsString()=="procedural"){var source=owner.Get("_cached_procedural").As<Image>();if(source==null){generate(owner,"");return;}owner.Set("source_image",source);owner.Set("source_area",new Rect2I(Vector2I.Zero,source.GetSize()));}
        if(owner.Get("source_image").AsGodotObject()==null&&config["source_mode"].AsString()!="nearby"){Canvas(owner).EmitSignal("hint_changed","Sample a source first");return;}begin(owner,item,item.Get("texture").As<Texture2D>().GetSize()*.5f,true);
    }
    public Settings prepare_material(RefCounted owner)
    {
        var material=owner.Get("material").As<Resource>();if(material==null)return new Settings();owner.Set("source_image",default(Variant));
        if(Get(Config(owner),"editable_texture",true).AsBool()&&material.Get("application").AsString()=="continuous"){var source=Image.CreateEmpty(1,1,false,Image.Format.Rgba8);source.Fill(Colors.White);owner.Set("source_image",source);owner.Set("source_area",new Rect2I(0,0,1,1));return new Settings();}
        long generation=owner.Get("_material_generation").AsInt64()+1;owner.Set("_material_generation",generation);var document=Workspace(owner).Get("document").As<Resource>();var preview=_materials.copy_material(material);preview.Set("coverage",default(Variant));preview.Set("blending","replace");preview.Set("rotation",0.0);preview.Set("texture_size",material.Get("application").AsString()!="continuous"?256.0:64.0);var size=new Vector2I(256,256);var extent=(Vector2)size;var frame=Transform2D.Identity;var item=layer(owner);
        if(material.Get("application").AsString()=="continuous"&&item!=null){preview=_materials.copy_material(material);preview.Set("coverage",default(Variant));preview.Set("source",item.Get("texture"));size=(Vector2I)item.Get("texture").As<Texture2D>().GetSize();extent=item.Get("dimensions").AsVector2();frame=_documents.world_transform(document,item);}
        return new Settings{["value"]=preview,["size"]=size,["extent"]=extent,["frame"]=frame,["generation"]=generation,["document"]=document};
    }
    public void complete_material(RefCounted owner,Settings request,Image? result)
    {
        if(result==null||request["generation"].AsInt64()!=owner.Get("_material_generation").AsInt64()||Workspace(owner).Get("document").AsGodotObject()!=request["document"].AsGodotObject())return;
        owner.Set("source_image",result);owner.Set("source_area",new Rect2I(Vector2I.Zero,result.GetSize()));owner.Set("source_point",Vector2.Zero);Config(owner)["source_mode"]="manual";Config(owner)["scale"]=1.0;Canvas(owner).EmitSignal("hint_changed",owner.Get("material").AsGodotObject().Get("label").AsString()+" ready · Paint or Fill selection");
    }
    public void draw(RefCounted owner)
    {
        var canvas=Canvas(owner);var item=layer(owner);var config=Config(owner);var origin=canvas.Call("origin").AsVector2();float zoom=canvas.Get("zoom").AsSingle();
        Func<Vector2,Vector2>? screen=null;Func<Vector2,Vector2>? local=null;
        if(item!=null&&item.Get("texture").AsGodotObject()!=null)
        {
            var projection=new ImageLayerProjection(item);var frame=_documents.world_transform(canvas.Get("document").As<Resource>(),item);var inverse=frame.AffineInverse();var size=item.Get("texture").As<Texture2D>().GetSize();
            screen=p=>origin+frame*projection.Project(p/size*projection.Dimensions,new Vector2(-1,-1))*zoom;
            local=p=>projection.Unproject(inverse*p)/projection.Dimensions*size;
            if(canvas.GetGlobalRect().HasPoint(canvas.GetGlobalMousePosition())){var center=local(canvas.Call("to_document",canvas.Get("_mouse")).AsVector2());var outline=new Vector2[49];for(int i=0;i<49;i++){double angle=Math.Tau*i/48;outline[i]=screen(center+new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle))*(float)(config["size"].AsDouble()*.5));}canvas.DrawPolyline(outline,Colors.Black,3,true);canvas.DrawPolyline(outline,new Color("a2e9e0"),1,true);}
        }
        if(owner.Get("source_image").AsGodotObject()==null||owner.Get("main_mode").AsString()!="repair")return;
        var point=origin+owner.Get("sample_document_point").AsVector2()*zoom;
        if(owner.Get("active").AsBool()&&(owner.Get("mode").AsString() is "clone" or "heal")&&config["sample_mode"].AsString()=="current")point=to_screen(owner,owner.Get("_stroke_source_anchor").AsVector2()+owner.Get("_last").AsVector2()-owner.Get("_anchor").AsVector2(),owner.Get("_owner").As<Resource>());
        canvas.DrawLine(point-new Vector2(9,0),point+new Vector2(9,0),new Color("ffc578"),2,true);canvas.DrawLine(point-new Vector2(0,9),point+new Vector2(0,9),new Color("ffc578"),2,true);if(owner.Get("active").AsBool())canvas.DrawLine(point,canvas.Get("_mouse").AsVector2(),new Color(1,.75f,.4f,.4f),1,true);
        var area=owner.Get("source_area").AsRect2I();if(!area.HasArea())return;var color=new Color(1,.75f,.4f,.7f);
        if(config["sample_mode"].AsString()!="current"||screen==null){canvas.DrawRect(new Rect2(origin+(Vector2)area.Position*zoom,(Vector2)area.Size*zoom),color,false,1);return;}
        var sourcePoints=owner.Get("source_points").AsVector2Array();var points=new List<Vector2>();string shape=config["sample_shape"].AsString();
        if(shape=="lasso"&&sourcePoints.Length>2){points.AddRange(sourcePoints);points.Add(sourcePoints[0]);}
        else if(shape=="circle")for(int i=0;i<49;i++){double angle=Math.Tau*i/48;points.Add(((Rect2)area).GetCenter()+new Vector2((float)Math.Cos(angle),(float)Math.Sin(angle))*(Vector2)area.Size*.5f);}
        else points.AddRange(new[]{(Vector2)area.Position,new Vector2(area.End.X,area.Position.Y),(Vector2)area.End,new Vector2(area.Position.X,area.End.Y),(Vector2)area.Position});
        for(int i=0;i<points.Count;i++)points[i]=screen(points[i]);canvas.DrawPolyline(points.ToArray(),color,1,true);
    }
}
