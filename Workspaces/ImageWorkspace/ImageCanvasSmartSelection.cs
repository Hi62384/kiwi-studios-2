using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageCanvasSelectionOperations
{
    private readonly PixelSelectionEngineOperations _smart=new();
    public void prepare_smart_selection(Control canvas)
    {
        var source=canvas.Get("pixel_source").As<Image>();var domain=canvas.Get("pixel_domain").AsRect2I();var smart=canvas.Get("smart_selection").As<Node>();if(source!=null&&domain.HasArea()&&smart.Get("source").AsGodotObject()!=source){_smart.prepare(smart,source,domain);canvas.Get("_edge_follower").AsGodotObject().Set("previous",-1);}
    }
    public void set_object_threshold(Control canvas,double value)
    {
        value=Math.Clamp(value,0,1);canvas.Set("object_threshold",value);var committed=canvas.Get("_object_committed").AsGodotDictionary();string drag=canvas.Get("_drag").AsString();if(drag.Length==0&&committed.Count>0&&canvas.Get("pixel_mode").AsString()=="object"&&canvas.Get("tool").AsString()=="pixel_select")
        {
            var selected=canvas.Get("selected").AsGodotArray();var document=canvas.Get("document").AsGodotObject();if(document.Get("pixel_selection").AsGodotObject()==committed["texture"].AsGodotObject()&&canvas.Get("pixel_source").AsGodotObject()==committed["source"].AsGodotObject()&&selected.Count>0&&selected[selected.Count-1].AsString()==committed["owner"].AsString()){canvas.EmitSignal("gesture_started");canvas.Set("_smart_base",committed["base"].As<Image>().Duplicate());canvas.Set("_smart_seed",committed["seed"]);canvas.Set("_smart_subtract",committed["subtract"]);canvas.Set("_drag","object_preview");canvas.Set("_smart_apply_when_ready",false);}else committed.Clear();
        }
        if(canvas.Get("_drag").AsString()=="object_preview"){canvas.Set("_smart_ready",false);canvas.Set("_smart_request",request_smart_mask(canvas,"object",canvas.Get("_smart_seed").AsVector2(),value,1));canvas.EmitSignal("hint_changed","Updating object selection…");}
    }
    public void commit_object_selection(Control canvas)
    {
        string drag=canvas.Get("_drag").AsString();if(drag=="pan"&&canvas.Get("_pan_previous_drag").AsString()=="object_preview"){canvas.Set("_smart_apply_when_ready",true);return;}if(drag!="object_preview")return;if(!canvas.Get("_smart_ready").AsBool()){canvas.Set("_smart_apply_when_ready",true);return;}
        var selected=canvas.Get("selected").AsGodotArray();var context=new Settings{["base"]=canvas.Get("_smart_base").As<Image>().Duplicate(),["seed"]=canvas.Get("_smart_seed"),["subtract"]=canvas.Get("_smart_subtract"),["source"]=canvas.Get("pixel_source"),["owner"]=selected[selected.Count-1]};canvas.Set("_drag","pixel_select");canvas.Call("_finish",canvas.Get("_smart_seed"));context["texture"]=canvas.Get("document").AsGodotObject().Get("pixel_selection");canvas.Set("_object_committed",context);
    }
    public void smart_proposed(Control canvas,Image? mask,string kind,long request)
    {
        string drag=canvas.Get("_drag").AsString(),action=drag=="pan"?canvas.Get("_pan_previous_drag").AsString():drag;if(request!=canvas.Get("_smart_request").AsInt64()||action is not ("object_preview" or "edge_pending"))return;
        if(mask==null){if(kind=="object"){canvas.Set("selection",canvas.Get("_smart_base").As<Image>().Duplicate());canvas.Set("_smart_ready",false);canvas.Set("_smart_has_proposal",false);canvas.Set("_smart_apply_when_ready",false);update_selection_preview(canvas);canvas.EmitSignal("hint_changed","No confident boundary · Adjust Object Threshold or Esc to cancel");return;}canvas.Call("cancel_gesture");canvas.EmitSignal("hint_changed",kind=="object"?"No confident object boundary found":"No connected edge found");return;}
        canvas.Set("selection",mask);canvas.Set("_smart_ready",true);canvas.Set("_smart_has_proposal",true);update_selection_preview(canvas);if(kind=="edge"){canvas.Set("_drag","pixel_select");canvas.Call("_finish",canvas.Get("_smart_seed"));}else if(canvas.Get("_smart_apply_when_ready").AsBool())commit_object_selection(canvas);else canvas.EmitSignal("hint_changed","Object preview · Click adds · Ctrl-click subtracts · Threshold adjusts this object · Enter applies · Esc cancels");
    }
    public long request_smart_mask(Control canvas,string kind,Vector2 point,double threshold,double width)=>_smart.request(canvas.Get("smart_selection").As<Node>(),kind,point,threshold,width,new Settings{["base"]=canvas.Get("_smart_base"),["alpha"]=canvas.Get("selection_alpha"),["falloff"]=canvas.Get("selection_falloff"),["subtract"]=canvas.Get("_smart_subtract"),["origin"]=canvas.Get("pixel_domain").AsRect2I().Position});
    public void begin_pixel_selection(Control canvas,Vector2 point,bool lasso)
    {
        if(canvas.Get("selected").AsGodotArray().Count==0||canvas.Get("pixel_source").AsGodotObject()==null||!canvas.Get("pixel_domain").AsRect2I().HasPoint((Vector2I)point))return;if(canvas.Get("_drag").AsString()=="object_preview")commit_object_selection(canvas);string mode=canvas.Get("pixel_mode").AsString();bool magnet=canvas.Get("edge_magnet").AsBool(),box=canvas.Get("pixel_box_select").AsBool();
        if(magnet&&(mode is "brush" or "fill")&&!box)
        {
            prepare_smart_selection(canvas);var edges=canvas.Get("smart_selection").AsGodotObject().Get("edges").AsGodotObject();if(edges==null){canvas.EmitSignal("hint_changed","Analyzing edges… try again when ready");return;}if(edges.Get("_kernel").As<PixelEdgeFieldKernel>().nearest(point,canvas.Get("edge_threshold").AsDouble(),-1,Vector2.Zero)<0){canvas.EmitSignal("hint_changed","No nearby edge at this threshold");return;}
        }
        if(mode=="object")prepare_smart_selection(canvas);canvas.EmitSignal("gesture_started");canvas.Set("selection_texture",default(Variant));var selection=canvas.Get("selection").As<Image>();var size=canvas.Get("document").AsGodotObject().Get("canvas_size").AsVector2I();selection=selection==null||selection.GetSize()!=size?Image.CreateEmpty(size.X,size.Y,false,Image.Format.Rgba8):(Image)selection.Duplicate();canvas.Set("selection",selection);canvas.Set("_drag","pixel_select");canvas.Set("_last",point);canvas.Set("_pixel_alpha_base",selection.Duplicate());canvas.Set("_pixel_alpha_ink",Image.CreateEmpty(selection.GetWidth(),selection.GetHeight(),false,Image.Format.Rgba8));canvas.Get("_edge_follower").AsGodotObject().Set("previous",-1);
        if(box&&(mode is "brush" or "erase")){canvas.Set("_start",point);canvas.Set("_pixel_area_base",selection.Duplicate());canvas.Set("_pixel_area_previous",new Rect2I());canvas.Set("_drag",lasso?"pixel_lasso":"pixel_box");if(lasso)canvas.Set("_points",new[]{point});}
        else if(mode=="object"||mode=="fill"&&magnet){canvas.Set("_smart_base",selection.Duplicate());canvas.Set("_smart_seed",point);canvas.Set("_smart_subtract",canvas.Get("_erase_modifier"));foreach(string key in new[]{"_smart_ready","_smart_has_proposal","_smart_apply_when_ready"})canvas.Set(key,false);canvas.Set("_drag",mode=="object"?"object_preview":"edge_pending");canvas.Set("_smart_request",request_smart_mask(canvas,mode=="object"?"object":"edge",point,canvas.Get(mode=="object"?"object_threshold":"edge_threshold").AsDouble(),canvas.Get("brush_size").AsDouble()));canvas.EmitSignal("hint_changed",mode=="object"?"Finding object…":"Following connected edge…");}
        else if(mode=="fill"){pixel_flood(canvas,(Vector2I)point);canvas.Call("_finish",point);}else pixel_brush_line(canvas,point,point);update_selection_preview(canvas);
    }
    public Vector2 snap_polygon_point(Control canvas,Vector2 at,bool control)
    {
        if(canvas.Get("snapping").AsBool()==control)return at;var document=canvas.Get("document").As<Resource>();var size=(Vector2)document.Get("canvas_size").AsVector2I();var targets=new System.Collections.Generic.List<Vector2>{Vector2.Zero,size*.5f,size};var points=canvas.Get("_points").AsVector2Array();int selected=canvas.Get("_polygon_index").AsInt32();for(int i=0;i<points.Length;i++)if(i!=selected)targets.Add(points[i]);foreach(var value in document.Get("layers").AsGodotArray()){var layer=value.As<Resource>();if(layer.Get("id").AsString()==canvas.Get("path_layer_id").AsString()||!_documents.can_edit(document,layer))continue;var bounds=_documents.world_transform(document,layer)*new Rect2(Vector2.Zero,layer.Get("dimensions").AsVector2());targets.Add(bounds.Position);targets.Add(bounds.GetCenter());targets.Add(bounds.End);}var best=Vector2.One*7/canvas.Get("zoom").AsSingle();var result=at;foreach(var target in targets){float x=Math.Abs(target.X-at.X),y=Math.Abs(target.Y-at.Y);if(x<best.X){best.X=x;result.X=target.X;}if(y<best.Y){best.Y=y;result.Y=target.Y;}}return result;
    }
    public int polygon_insert(Control canvas,Vector2 at)
    {
        var points=canvas.Get("_points").AsVector2Array();if(points.Length<2)return points.Length;int nearest=0;float distance=float.PositiveInfinity;for(int i=0;i<points.Length;i++){int next=(i+1)%points.Length;if(points[i].IsEqualApprox(points[next]))continue;float cost=Geometry2D.GetClosestPointToSegment(at,points[i],points[next]).DistanceSquaredTo(at);if(cost<distance){distance=cost;nearest=i+1;}}return nearest;
    }
}
