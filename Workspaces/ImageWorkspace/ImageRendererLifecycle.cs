using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;
public partial class ImageRendererOperations
{
    public void ready(Node owner)
    {
        owner.Get("_shader").As<Shader>().Code=GD.Load<GDScript>("res://Workspaces/ImageWorkspace/image_renderer.gd").GetScriptConstantMap()["EFFECT_CODE"].AsString();owner.Get("_warp_shader").As<Shader>().Code=ImageWarpShader.Code;var viewport=owner.Get("viewport").As<SubViewport>();var export=owner.Get("export_viewport").As<SubViewport>();foreach(var target in new[]{viewport,export}){target.TransparentBg=true;target.RenderTargetClearMode=SubViewport.ClearMode.Always;target.Disable3D=true;target.RenderTargetUpdateMode=SubViewport.UpdateMode.Always;owner.AddChild(target);}var straight=owner.Get("_straight_shader").As<Shader>();straight.Code="shader_type canvas_item; render_mode unshaded, blend_disabled; void fragment() { vec4 c = texture(TEXTURE, UV); COLOR = vec4(c.rgb / max(c.a, 0.00001), c.a); }";var display=owner.Get("_export_display").As<TextureRect>();display.Texture=viewport.GetTexture();display.Material=new ShaderMaterial{Shader=straight};export.AddChild(display);var composition=owner.Get("composition_viewport").As<SubViewport>();composition.TransparentBg=true;composition.Disable3D=true;composition.World2D=viewport.World2D;composition.RenderTargetUpdateMode=SubViewport.UpdateMode.Disabled;owner.AddChild(composition);owner.Call("_connect_frame");owner.SetProcess(false);
    }
    public SubViewport surface(Node owner,Vector2I dimensions){var target=new SubViewport{Size=dimensions.Max(Vector2I.One),TransparentBg=true,RenderTargetClearMode=SubViewport.ClearMode.Always,Disable3D=true,RenderTargetUpdateMode=SubViewport.UpdateMode.Always};owner.AddChild(target);return target;}
    public Texture2D texture(Node owner)=>owner.Get("viewport").As<SubViewport>().GetTexture();
    public Texture2D composition_texture(Node owner)=>owner.Get("composition_viewport").As<SubViewport>().GetTexture();
    public void set_composition_preview_enabled(Node owner,bool enabled){owner.Set("_composition_enabled",enabled);owner.Get("composition_viewport").As<SubViewport>().RenderTargetUpdateMode=enabled?SubViewport.UpdateMode.Always:SubViewport.UpdateMode.Disabled;}
    public Vector2 content_dimensions(Resource layer)=>_layers.content_dimensions(layer);
    public void set_enabled(Node owner,bool enabled)
    {
        owner.Set("_enabled",enabled);foreach(string key in new[]{"viewport","export_viewport"})owner.Get(key).As<SubViewport>().RenderTargetUpdateMode=enabled?SubViewport.UpdateMode.Always:SubViewport.UpdateMode.Disabled;foreach(var value in Views(owner).Values){var view=value.AsGodotDictionary();bool render=enabled&&(owner.Get("exporting").AsBool()||Get(view,"dynamic",false).AsBool()||Get(view,"frames_left",0).AsInt32()>0);set_layer_update_mode(view,(int)(render?SubViewport.UpdateMode.Always:SubViewport.UpdateMode.Disabled));}owner.Get("composition_viewport").As<SubViewport>().RenderTargetUpdateMode=enabled&&owner.Get("_composition_enabled").AsBool()?SubViewport.UpdateMode.Always:SubViewport.UpdateMode.Disabled;
    }
    public void sync_transforms(Node owner,Resource document)
    {
        owner.Set("document",document);owner.Get("_live_signatures").AsGodotDictionary().Clear();var views=Views(owner);float scale=owner.Get("render_scale").AsSingle();foreach(var value in document.Get("layers").AsGodotArray()){var layer=value.As<Resource>();var id=layer.Get("id");if(!views.ContainsKey(id))continue;var view=views[id].AsGodotDictionary();string kind=layer.Get("kind").AsString();if(kind=="text"){view["stable_text_surface"]=true;update_layer(owner,layer,view);continue;}if(kind=="group"){update_layer(owner,layer,view);continue;}var transform=_layers.local_transform(layer);transform.Origin*=scale;view["root"].As<Node2D>().Transform=transform;var dimensions=layer.Get("dimensions").AsVector2();var previewScale=dimensions/Get(view,"allocated_dimensions",dimensions).AsVector2().Max(Vector2.One);var output=view["output"].As<Sprite2D>();output.Scale=previewScale;output.Position=-Vector2.One*Pad*previewScale;float opacity=layer.Get("opacity").AsSingle();output.Modulate=layer.Get("blend").AsInt32()==0?new Color(opacity,opacity,opacity,opacity):new Color(1,1,1,opacity);}schedule_cached_layers(owner);
    }
    public void set_preview_scale(Node owner,double requested)
    {
        if(owner.Get("exporting").AsBool()||owner.Get("document").AsGodotObject()==null)return;var document=Document(owner);var views=Views(owner);foreach(var value in document.Get("layers").AsGodotArray()){var layer=value.As<Resource>();var id=layer.Get("id");if(layer.Get("kind").AsString()!="text"||!views.ContainsKey(id))continue;var drawing=views[id].AsGodotDictionary()["direct_text"].As<Node2D>();var world=_documents.world_transform(document,layer);double detail=Math.Max(1,requested*Math.Max(world.X.Length(),world.Y.Length()));if(!Mathf.IsEqualApprox(drawing.Get("text_detail").AsDouble(),detail)){drawing.Set("text_detail",detail);drawing.QueueRedraw();}}apply_preview_resolution(owner);
    }
    public void set_interactive_preview(Node owner,bool active)
    {
        if(owner.Get("_interactive_preview").AsBool()==active)return;owner.Set("_interactive_preview",active);if(active){owner.Set("_refine_at_usec",0);owner.SetProcess(false);apply_preview_resolution(owner);}else{owner.Set("_refine_at_usec",Time.GetTicksUsec()+350000);owner.SetProcess(true);}
    }
    public void process(Node owner)
    {
        long refine=owner.Get("_refine_at_usec").AsInt64();if(refine==0||owner.Get("_interactive_preview").AsBool()){owner.SetProcess(false);return;}if(owner.Get("exporting").AsBool()||Time.GetTicksUsec()<(ulong)refine)return;owner.Set("_refine_at_usec",0);owner.SetProcess(false);apply_preview_resolution(owner);
    }
    public void apply_preview_resolution(Node owner)
    {
        if(owner.Get("exporting").AsBool()||owner.Get("document").AsGodotObject()==null||owner.Get("preview_size").AsVector2I()==Vector2I.Zero)return;double desired=requested_preview_resolution(owner);if(Mathf.IsEqualApprox(desired,owner.Get("render_scale").AsDouble()))return;owner.Set("render_scale",desired);owner.Set("preview_transform",new Transform2D(0,owner.Get("_preview_origin").AsVector2()).ScaledLocal(Vector2.One*(float)(owner.Get("_preview_zoom").AsDouble()/desired)));sync(owner,Document(owner));
    }
    public double requested_preview_resolution(Node owner)
    {
        double desired=Math.Clamp(Math.Pow(2,Math.Ceiling(Math.Log(Math.Max(.0625,owner.Get("_preview_zoom").AsDouble()))/Math.Log(2))),.0625,1);if(owner.Get("_interactive_preview").AsBool()||owner.Get("_refine_at_usec").AsInt64()!=0){var document=Document(owner);var size=document.Get("canvas_size").AsVector2I();double extent=Math.Max(size.X,size.Y);foreach(var value in document.Get("layers").AsGodotArray()){var dimensions=content_dimensions(value.As<Resource>());extent=Math.Max(extent,Math.Max(dimensions.X,dimensions.Y));}desired=Math.Min(desired,owner.Get("preview_interactive_limit").AsDouble()/Math.Max(1,extent));}return desired;
    }
    public void set_preview_camera(Node owner,Vector2 dimensions,Vector2 origin,double zoom)
    {
        if(owner.Get("exporting").AsBool())return;if(owner.Get("preview_size").AsVector2I()==Vector2I.Zero||!Mathf.IsEqualApprox(owner.Get("_preview_zoom").AsDouble(),zoom)){owner.Set("_refine_at_usec",Time.GetTicksUsec()+350000);owner.SetProcess(true);}var size=((Vector2I)dimensions.Ceil()).Max(Vector2I.One);owner.Set("preview_size",size);owner.Set("_preview_zoom",Math.Max(.001,zoom));owner.Set("_preview_origin",origin);var transform=new Transform2D(0,origin).ScaledLocal(Vector2.One*(float)(owner.Get("_preview_zoom").AsDouble()/owner.Get("render_scale").AsDouble()));owner.Set("preview_transform",transform);var viewport=owner.Get("viewport").As<SubViewport>();viewport.Size=size;viewport.CanvasTransform=transform;set_preview_scale(owner,zoom);
    }
    public Settings prepare_flattened(Node owner)
    {
        owner.Set("exporting",true);double previous=owner.Get("render_scale").AsDouble();owner.Set("render_scale",1.0);var document=Document(owner);sync(owner,document);set_enabled(owner,true);int frames=3;foreach(var value in document.Get("layers").AsGodotArray()){var layer=value.As<Resource>();int passes=4+(layer.Get("warp").AsGodotObject()!=null?2:0);Resource? current=layer;var seen=new HashSet<string>();while(current!=null&&seen.Add(current.Get("id").AsString())){var effects=current.Get("effects").AsGodotArray();passes+=4+effects.Count*(Get(current.Get("properties").AsGodotDictionary(),"effects_selection_only",false).AsBool()?2:1);foreach(var effect in effects){string kind=Get(effect.AsGodotDictionary(),"type","").AsString();if(kind is "shader" or "blur")passes++;}current=_documents.layer_for_id(document,current.Get("parent_id").AsString());}frames=Math.Max(frames,passes);}return new Settings{["scale"]=previous,["frames"]=frames};
    }
    public Image complete_flattened(Node owner,Settings request){var image=owner.Get("export_viewport").As<SubViewport>().GetTexture().GetImage();owner.Set("exporting",false);owner.Set("render_scale",request["scale"]);sync(owner,Document(owner));return image;}
}
