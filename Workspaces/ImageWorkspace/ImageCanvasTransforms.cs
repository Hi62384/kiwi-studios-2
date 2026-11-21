using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageCanvasSelectionOperations
{
    private static bool IndexIn(int index,params int[] values)=>Array.IndexOf(values,index)>=0;
    private static void SetGuide(GArray guides,float value){guides.Clear();guides.Add(value);}
    private Transform2D ParentInverse(Resource document,Resource layer){var parent=_documents.layer_for_id(document,layer.Get("parent_id").AsString());return parent!=null?_documents.world_transform(document,parent).AffineInverse():Transform2D.Identity;}
    private List<Vector2> SnapTargets(Control canvas)
    {
        var document=canvas.Get("document").As<Resource>();var size=(Vector2)document.Get("canvas_size").AsVector2I();var targets=new List<Vector2>{Vector2.Zero,size*.5f,size};var selected=canvas.Get("selected").AsGodotArray();foreach(var item in document.Get("layers").AsGodotArray()){var other=item.As<Resource>();if(selected.Contains(other.Get("id"))||!other.Get("visible").AsBool())continue;var rect=_documents.world_transform(document,other)*new Rect2(Vector2.Zero,other.Get("dimensions").AsVector2());targets.Add(rect.Position);targets.Add(rect.GetCenter());targets.Add(rect.End);}return targets;
    }
    public void begin_transform(Control canvas,string action)
    {
        canvas.Get("snap_guides_x").AsGodotArray().Clear();canvas.Get("snap_guides_y").AsGodotArray().Clear();canvas.Set("_resize_grab_offset",Vector2.Zero);canvas.Set("_resize_proxy_active",false);
        if(action.StartsWith("resize",StringComparison.Ordinal)){int index=int.Parse(action[6..],System.Globalization.CultureInfo.InvariantCulture);var bounds=canvas.Get("_bounds").AsRect2();float zoom=canvas.Get("zoom").AsSingle();var screen=new Rect2(origin(canvas)+bounds.Position*zoom,bounds.Size*zoom);var actual=ProjectedHandles(canvas,screen)[index];var visible=handles(canvas,screen)[index].AsVector2();canvas.Set("_resize_proxy_active",!actual.IsEqualApprox(visible));var proxy=origin(canvas)+canvas.Get("_start").AsVector2()*zoom;canvas.Set("_resize_proxy_screen",proxy);canvas.Set("_resize_grab_offset",(actual-proxy)/zoom);}
        canvas.Set("_drag",action);var originals=canvas.Get("_originals").AsGodotArray();originals.Clear();var document=canvas.Get("document").As<Resource>();foreach(var item in _documents.selected_roots(document,canvas.Get("selected").AsGodotArray())){var layer=item.As<Resource>();if(!_documents.can_edit(document,layer))continue;var properties=layer.Get("properties").AsGodotDictionary();originals.Add(new Settings{["layer"]=layer,["position"]=layer.Get("position"),["dimensions"]=layer.Get("dimensions"),["rotation"]=layer.Get("rotation"),["world"]=_documents.world_transform(document,layer),["flip_x"]=Get(properties,"flip_x",false),["flip_y"]=Get(properties,"flip_y",false)});}canvas.EmitSignal("gesture_started");canvas.EmitSignal("hint_changed","Ctrl temporarily toggles snap · Shift constrains · Esc cancels · Release commits");
    }
    public void transform(Control canvas,Vector2 point,bool constrained,bool control)
    {
        var guidesX=canvas.Get("snap_guides_x").AsGodotArray();var guidesY=canvas.Get("snap_guides_y").AsGodotArray();guidesX.Clear();guidesY.Clear();var start=canvas.Get("_start").AsVector2();var delta=point-start;canvas.Set("_moved",canvas.Get("_moved").AsBool()||delta.Length()>.1);bool snap=canvas.Get("snapping").AsBool()!=control;string drag=canvas.Get("_drag").AsString();var bounds=canvas.Get("_bounds").AsRect2();var originals=canvas.Get("_originals").AsGodotArray();var document=canvas.Get("document").As<Resource>();float tolerance=7/canvas.Get("zoom").AsSingle();
        if(drag=="move")
        {
            if(constrained){if(Math.Abs(delta.X)>Math.Abs(delta.Y))delta.Y=0;else delta.X=0;}
            if(snap)
            {
                var moved=new Rect2(bounds.Position+delta,bounds.Size);var targets=SnapTargets(canvas);var best=Vector2.One*tolerance;foreach(var target in targets){foreach(float edge in new[]{moved.Position.X,moved.GetCenter().X,moved.End.X})if(Math.Abs(target.X-edge)<Math.Abs(best.X))best.X=target.X-edge;foreach(float edge in new[]{moved.Position.Y,moved.GetCenter().Y,moved.End.Y})if(Math.Abs(target.Y-edge)<Math.Abs(best.Y))best.Y=target.Y-edge;}
                if(Math.Abs(best.X)<tolerance){delta.X+=best.X;var snapped=new Rect2(bounds.Position+delta,bounds.Size);foreach(var target in targets)if(Math.Abs(target.X-snapped.Position.X)<.01||Math.Abs(target.X-snapped.GetCenter().X)<.01||Math.Abs(target.X-snapped.End.X)<.01){guidesX.Add(target.X);break;}}
                if(Math.Abs(best.Y)<tolerance){delta.Y+=best.Y;var snapped=new Rect2(bounds.Position+delta,bounds.Size);foreach(var target in targets)if(Math.Abs(target.Y-snapped.Position.Y)<.01||Math.Abs(target.Y-snapped.GetCenter().Y)<.01||Math.Abs(target.Y-snapped.End.Y)<.01){guidesY.Add(target.Y);break;}}
            }
            foreach(var item in originals){var entry=item.AsGodotDictionary();var layer=entry["layer"].As<Resource>();layer.Set("position",entry["position"].AsVector2()+ParentInverse(document,layer).BasisXform(delta));}
        }
        else if(drag=="rotate")
        {
            var center=bounds.GetCenter();float angle=(start-center).AngleTo(point-center);if(constrained||snap)angle=Mathf.Snapped(angle,Mathf.Pi/12);foreach(var item in originals){var entry=item.AsGodotDictionary();var layer=entry["layer"].As<Resource>();layer.Set("rotation",entry["rotation"].AsDouble()+angle);var dimensions=entry["dimensions"].AsVector2();var worldCenter=entry["world"].AsTransform2D()*(dimensions*.5f);var destination=center+(worldCenter-center).Rotated(angle);layer.Set("position",ParentInverse(document,layer)*destination-dimensions*.5f);}
        }
        else
        {
            int index=int.Parse(drag[6..],System.Globalization.CultureInfo.InvariantCulture);canvas.Set("_resize_proxy_screen",origin(canvas)+point*canvas.Get("zoom").AsSingle());point+=canvas.Get("_resize_grab_offset").AsVector2();if(originals.Count==1){resize_single(canvas,point,index,constrained,snap);canvas.EmitSignal("gesture_changed");return;}var low=bounds.Position;var high=bounds.End;if(IndexIn(index,0,6,7))low.X=point.X;if(IndexIn(index,0,1,2))low.Y=point.Y;if(IndexIn(index,2,3,4))high.X=point.X;if(IndexIn(index,4,5,6))high.Y=point.Y;if(Math.Abs(high.X-low.X)<1)high.X=low.X+(high.X>=low.X?1:-1);if(Math.Abs(high.Y-low.Y)<1)high.Y=low.Y+(high.Y>=low.Y?1:-1);
            if(snap)
            {
                var targets=SnapTargets(canvas);foreach(var target in targets){if(IndexIn(index,0,6,7)&&Math.Abs(low.X-target.X)<tolerance){low.X=target.X;SetGuide(guidesX,target.X);}if(IndexIn(index,2,3,4)&&Math.Abs(high.X-target.X)<tolerance){high.X=target.X;SetGuide(guidesX,target.X);}}
                foreach(var target in targets){if(IndexIn(index,0,1,2)&&Math.Abs(low.Y-target.Y)<tolerance){low.Y=target.Y;SetGuide(guidesY,target.Y);}if(IndexIn(index,4,5,6)&&Math.Abs(high.Y-target.Y)<tolerance){high.Y=target.Y;SetGuide(guidesY,target.Y);}}
            }
            var ratio=(high-low)/bounds.Size.Max(Vector2.One);bool keep=constrained;foreach(var item in originals)if(Get(item.AsGodotDictionary()["layer"].AsGodotObject().Get("properties").AsGodotDictionary(),"keep_aspect",false).AsBool())keep=true;
            if(keep)
            {
                float magnitude;if(IndexIn(index,3,7))magnitude=Math.Abs(ratio.X);else if(IndexIn(index,1,5))magnitude=Math.Abs(ratio.Y);else{magnitude=(ratio*bounds.Size).Dot(bounds.Size)/Math.Max(1,bounds.Size.LengthSquared());float minimum=1/Math.Max(1,Math.Min(bounds.Size.X,bounds.Size.Y));if(Math.Abs(magnitude)<minimum)magnitude=minimum*(magnitude<0?-1:1);}ratio=IndexIn(index,0,2,4,6)?Vector2.One*magnitude:new Vector2(magnitude*(ratio.X<0?-1:1),magnitude*(ratio.Y<0?-1:1));var anchor=bounds.GetCenter();if(IndexIn(index,0,6,7))anchor.X=bounds.End.X;else if(IndexIn(index,2,3,4))anchor.X=bounds.Position.X;if(IndexIn(index,0,1,2))anchor.Y=bounds.End.Y;else if(IndexIn(index,4,5,6))anchor.Y=bounds.Position.Y;low=anchor+(bounds.Position-anchor)*ratio;
            }
            foreach(var item in originals)
            {
                var entry=item.AsGodotDictionary();var layer=entry["layer"].As<Resource>();var world=entry["world"].AsTransform2D();var original=entry["dimensions"].AsVector2();var worldCenter=world*(original*.5f);var inverse=ParentInverse(document,layer);var destination=inverse*(low+(worldCenter-bounds.Position)*ratio);var scaledBasis=new Transform2D(world.X*ratio,world.Y*ratio,Vector2.Zero);var originalBasis=inverse*new Transform2D(world.X,world.Y,Vector2.Zero);var localBasis=inverse*scaledBasis;var dimensions=original*new Vector2(localBasis.X.Length()/Math.Max(.001f,originalBasis.X.Length()),localBasis.Y.Length()/Math.Max(.001f,originalBasis.Y.Length()));_documents.resize_layer(document,layer,dimensions.Max(Vector2.One));var resized=layer.Get("dimensions").AsVector2();localBasis=localBasis.ScaledLocal(original/resized);_layers.set_linear_basis(layer,localBasis);layer.Set("position",destination-resized*.5f);
            }
        }
        canvas.EmitSignal("gesture_changed");
    }
    public void resize_single(Control canvas,Vector2 point,int index,bool constrained,bool snap)
    {
        var entry=canvas.Get("_originals").AsGodotArray()[0].AsGodotDictionary();var layer=entry["layer"].As<Resource>();var uv=HandleUvs[index];var anchor=HandleUvs[(index+4)%8];var original=entry["dimensions"].AsVector2();var world=entry["world"].AsTransform2D();var frame=_layers.projected_bounds(layer,original);var fixedPoint=world*(frame.Position+anchor*frame.Size);var document=canvas.Get("document").As<Resource>();
        if(snap){float tolerance=7/canvas.Get("zoom").AsSingle();var best=Vector2.One*tolerance;foreach(var target in SnapTargets(canvas))for(int axis=0;axis<2;axis++)if(Math.Abs(target[axis]-point[axis])<Math.Abs(best[axis]))best[axis]=target[axis]-point[axis];for(int axis=0;axis<2;axis++)if(Math.Abs(best[axis])<tolerance)point[axis]+=best[axis];}
        var desired=world.AffineInverse().BasisXform(point-fixedPoint);var dimensions=original;var initial=(uv-anchor)*frame.Size;if(constrained||Get(layer.Get("properties").AsGodotDictionary(),"keep_aspect",false).AsBool()){var span=world.BasisXform(initial);float factor=Math.Max(1/Math.Min(original.X,original.Y),(point-fixedPoint).Dot(span)/Math.Max(.0001f,span.LengthSquared()));dimensions=original*factor;}
        else{for(int axis=0;axis<2;axis++)if(!Mathf.IsZeroApprox(uv[axis]-anchor[axis]))dimensions[axis]=original[axis]*desired[axis]/initial[axis];dimensions=dimensions.Clamp(Vector2.One,Vector2.One*100000);}
        _documents.resize_layer(document,layer,dimensions);var inverse=ParentInverse(document,layer);var basis=_layers.local_transform(layer);var resizedFrame=_layers.projected_bounds(layer,dimensions);var localAnchor=resizedFrame.Position+anchor*resizedFrame.Size;layer.Set("position",inverse*fixedPoint-dimensions*.5f-basis.BasisXform(localAnchor-dimensions*.5f));
    }
}
