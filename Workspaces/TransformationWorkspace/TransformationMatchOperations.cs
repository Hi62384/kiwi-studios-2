using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class TransformationMatchOperations : RefCounted
{
    private static GodotObject Host(Control surface)=>surface.Get("host").AsGodotObject();
    private static GodotObject Workspace(Control surface)=>Host(surface).Get("workspace").AsGodotObject();
    private static RefCounted Session(Control surface)=>Workspace(surface).Get("session").As<RefCounted>();
    private static Resource? Key(Control surface)=>Host(surface).Call("key").As<Resource>();
    public Rect2 rect(Control surface,int index)=>new(new Vector2(index*surface.Size.X*.5f+12,30),new Vector2(surface.Size.X*.5f-24,surface.Size.Y-45));
    public void draw(Control surface)
    {
        var host=Host(surface);var key=Key(surface);var document=Session(surface).Get("document").AsGodotObject();var item=document.Call("component",host.Get("component_id")).As<Resource>();if(key==null||item==null)return;bool overlays=host.Get("overlays").AsBool();var a=key.Get("points_a").AsVector2Array();var b=key.Get("points_b").AsVector2Array();if(overlays)for(int index=0;index<a.Length;index++)surface.DrawLine(rect(surface,0).Position+a[index]*rect(surface,0).Size,rect(surface,1).Position+b[index]*rect(surface,1).Size,new Color(.5f,1,.85f,.22f),1,true);
        for(int side=0;side<2;side++){var state=item.Call("state_for_id",side==0?key.Get("state_id"):host.Get("next_state_id")).As<Resource>();if(state==null)continue;var box=rect(surface,side);surface.DrawRect(box,new Color("24323e"));surface.DrawTextureRect(state.Get("artwork").AsGodotObject().Get("texture").As<Texture2D>(),box,false);surface.DrawString(ThemeDB.FallbackFont,box.Position-new Vector2(0,8),state.Get("title").AsString(),HorizontalAlignment.Left,-1,13,new Color("79e0c5"));if(!overlays)continue;var points=side==0?a:b;for(int index=0;index<points.Length;index++){var point=box.Position+points[index]*box.Size;surface.DrawCircle(point,7,new Color("10202b"));surface.DrawCircle(point,5,new Color(surface.Get("selected_pair").AsInt32()==index?"7fe6ce":"ffd18b"));surface.DrawString(ThemeDB.FallbackFont,point+new Vector2(8,-4),(index+1).ToString(),HorizontalAlignment.Left,-1,12,Colors.White);}}
        var pending=surface.Get("pending");if(overlays&&pending.VariantType==Variant.Type.Vector2)surface.DrawCircle(rect(surface,0).Position+pending.AsVector2()*rect(surface,0).Size,6,new Color("7fe6ce"));
    }
    private static void Remove(Resource key,int index){foreach(string name in new[]{"points_a","points_b"}){var points=new List<Vector2>(key.Get(name).AsVector2Array());points.RemoveAt(index);key.Set(name,points.ToArray());}}
    public void input(Control surface,InputEvent input)
    {
        var key=Key(surface);if(key==null||!Host(surface).Get("overlays").AsBool())return;var session=Session(surface);int drag=surface.Get("drag").AsInt32();if(input is InputEventMouseButton mouse)
        {
            if(mouse.ButtonIndex==MouseButton.Left&&!mouse.Pressed&&drag>=0){surface.Set("drag",-1);var errors=session.Get("document").AsGodotObject().Call("validate").AsStringArray();if(errors.Length==0)session.Call("commit","Move morph correspondence");else{session.Call("cancel");Workspace(surface).Get("status").As<Label>().Text=errors[0];}surface.QueueRedraw();surface.AcceptEvent();return;}
            int side=mouse.Position.X<surface.Size.X*.5?0:1;var box=rect(surface,side);var uv=((mouse.Position-box.Position)/box.Size).Clamp(Vector2.Zero,Vector2.One);if(!box.HasPoint(mouse.Position))return;var points=key.Get(side==0?"points_a":"points_b").AsVector2Array();int nearest=-1;for(int index=0;index<points.Length;index++)if((points[index]*box.Size+box.Position).DistanceTo(mouse.Position)<10){nearest=index;break;}
            if(mouse.ButtonIndex==MouseButton.Right&&mouse.Pressed){surface.Set("pending",default(Variant));if(nearest>=0){session.Call("begin");Remove(key,nearest);session.Call("commit","Delete morph correspondence");}}
            else if(mouse.ButtonIndex==MouseButton.Left&&mouse.Pressed){if(nearest>=0){surface.Set("drag",nearest);surface.Set("selected_pair",nearest);surface.Set("side",side);session.Call("begin");}else if(side==0)surface.Set("pending",uv);else if(surface.Get("pending").VariantType==Variant.Type.Vector2&&key.Get("points_a").AsVector2Array().Length<24){session.Call("begin");var first=new List<Vector2>(key.Get("points_a").AsVector2Array());var last=new List<Vector2>(key.Get("points_b").AsVector2Array());first.Add(surface.Get("pending").AsVector2());last.Add(uv);key.Set("points_a",first.ToArray());key.Set("points_b",last.ToArray());session.Call("commit","Add morph correspondence");surface.Set("pending",default(Variant));surface.Set("selected_pair",first.Count-1);}}surface.QueueRedraw();surface.AcceptEvent();
        }
        else if(input is InputEventMouseMotion motion&&drag>=0){int side=surface.Get("side").AsInt32();var box=rect(surface,side);var uv=((motion.Position-box.Position)/box.Size).Clamp(Vector2.Zero,Vector2.One);string name=side==0?"points_a":"points_b";var points=key.Get(name).AsVector2Array();if(drag>=points.Length)return;points[drag]=uv;key.Set(name,points);Workspace(surface).Set("_render_pending",true);surface.QueueRedraw();surface.AcceptEvent();}
    }
    public Variant drag_data(Tree owner,Vector2 at){var item=owner.GetItemAtPosition(at);if(item==null)return default;owner.SetDragPreview(new Label {Text=item.GetText(0)});return new Settings {["transformation_component"]=item.GetMetadata(0)};}
    public bool can_drop(Tree owner,Variant data){owner.DropModeFlags=(int)Tree.DropModeFlagsEnum.Inbetween;return data.VariantType==Variant.Type.Dictionary&&data.AsGodotDictionary().ContainsKey("transformation_component");}
    public void drop(Tree owner,Vector2 at,Settings data){var item=owner.GetItemAtPosition(at);if(item==null)return;var document=owner.Get("session").AsGodotObject().Get("document").AsGodotObject();var target=document.Call("component",item.GetMetadata(0).AsString()).AsGodotObject();var source=document.Call("component",data["transformation_component"].AsString()).AsGodotObject();var components=document.Get("components").AsGodotArray();int index=components.IndexOf(Variant.From(target)),old=components.IndexOf(Variant.From(source));if(owner.GetDropSectionAtPosition(at)<0)index++;if(old<index)index--;owner.EmitSignal("reorder_requested",data["transformation_component"].AsString(),index);}
}
