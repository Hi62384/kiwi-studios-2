using Godot;
using System;
using System.Collections.Generic;
using Settings=Godot.Collections.Dictionary;

public partial class WorldRoadTool : RefCounted
{
    public Control? canvas {get;set;}
    public Settings _drag {get;set;}=new();
    public Variant _first {get;set;}
    public Variant _hover {get;set;}
    public int road_index {get;set;}
    public int point_index {get;set;}
    public string _world_id {get;set;}="";
    public WorldDistrictTool district_tool {get;set;}=new();
    private readonly RoadGeometryOperations _geometry=new();
    private readonly WorldTerrainOperations _terrain=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    internal Control Owner=>canvas??throw new InvalidOperationException("Road tool has no viewport.");
    internal CanvasItem Overlay=>Owner.Get("overlay").As<CanvasItem>();
    internal Camera3D Camera=>Owner.Get("camera").As<Camera3D>();
    internal Vector2 Project(Vector3 point)=>Owner.Call("project",point).AsVector2();
    internal string Mode=>Owner.Get("environment_tool").AsString();
    internal bool Navigating=>Owner.Get("_navigating").AsBool()||Owner.Get("_panning").AsBool()||Owner.Get("_orbiting").AsBool();
    public Settings target()
    {
        if(canvas==null)return new Settings();var session=canvas.Call("environment_session").As<RefCounted>();if(session==null)return new Settings();var item=session.Call("primary").As<Resource>();var document=session.Get("document").As<Resource>();var worlds=new WorldSessionOperations();var visited=new HashSet<string>();
        while(item!=null&&visited.Add(item.Get("id").AsString())){if(worlds.source(item)!=null)return new Settings {["id"]=item.Get("id"),["source"]=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").Call("source",session,item.Get("id")),["pose"]=document.Call("world_transform",item)};item=document.Call("component",item.Get("parent_id")).As<Resource>();}return new Settings();
    }
    public void cancel(){_drag=new Settings();_first=default;_hover=default;district_tool.canvas=canvas;district_tool.cancel();if(canvas!=null)Overlay.QueueRedraw();}
    public Variant _position(Settings info,Vector2 screen,Vector3 at,bool ctrl)
    {
        var pose=info["pose"].AsTransform3D();var normal=(pose.Basis*Vector3.Up).Normalized();var ray=Owner.Call("ray",screen).AsGodotDictionary();Vector3? hit=new Plane(normal,pose*at).IntersectsRay(ray["origin"].AsVector3(),ray["direction"].AsVector3());var source=info["source"].As<Resource>();var roads=source.Get("roads").AsGodotArray();bool ground=Mode is "Draw road" or "District boundary"||road_index>=0&&road_index<roads.Count&&Get(roads[road_index].AsGodotDictionary(),"mode","Ground").AsString()=="Ground";string terrainId=source.Get("terrain_id").AsString();
        if(ground&&terrainId.Length>0){var surface=Owner.Call("pick_terrain",screen).AsGodotDictionary();if(surface.Count>0&&surface["id"].AsString()==terrainId)hit=surface["point"].AsVector3()+normal*.03f;}if(hit==null)return default;var local=pose.AffineInverse()*hit.Value;
        if(Owner.Get("snap").AsBool()!=ctrl){local.X=(float)Mathf.Snapped((double)local.X,.5);local.Z=(float)Mathf.Snapped((double)local.Z,.5);if(ground&&terrainId.Length>0){var context=_terrain.context(Owner.Call("environment_session").As<RefCounted>(),info["id"].AsString(),source);if(context["error"].AsString().Length==0){var surface=_terrain.sample(context,new Vector2(local.X,local.Z));if(surface.Count>0)local.Y=surface["height"].AsSingle();}}}return local;
    }
    private bool InvalidDrag(Resource source)
    {var roads=source.Get("roads").AsGodotArray();return road_index<0||road_index>=roads.Count||roads[road_index].AsGodotDictionary()["id"].AsString()!=_drag["road_id"].AsString()||point_index<0||point_index>=roads[road_index].AsGodotDictionary()["points"].AsVector3Array().Length;}
    public bool input(InputEvent input)
    {
        if(canvas==null)return false;district_tool.canvas=canvas;if(Mode=="District boundary")return district_tool.input(input);if(Mode is not ("Draw road" or "Road points"))return false;
        if(input is InputEventKey key&&key.Pressed&&key.Keycode==Key.Escape){cancel();return true;}if(input is InputEventMouseButton right&&right.Pressed&&right.ButtonIndex==MouseButton.Right&&(_drag.Count>0||_first.VariantType!=Variant.Type.Nil)){cancel();return true;}if(Navigating)return false;var info=target();if(info.Count==0)return false;if(_world_id!=info["id"].AsString()){cancel();_world_id=info["id"].AsString();}var source=info["source"].As<Resource>();if(_drag.Count>0&&InvalidDrag(source)){cancel();return true;}
        if(input is InputEventKey deletion&&deletion.Pressed&&deletion.Keycode is Key.Delete or Key.Backspace&&Mode=="Road points")
        {var result=new RoadEditingOperations().remove_point(source,road_index,point_index);var next=Get(result,"source").As<Resource>();if(next==null)Owner.EmitSignal("notice",result["error"]);else{_drag=new Settings();Owner.EmitSignal("world_replaced",info["id"].AsString(),next);}return true;}
        if(input is InputEventMouseMotion motion)
        {if(_first.VariantType==Variant.Type.Vector3&&Mode=="Draw road"){_hover=_position(info,motion.Position,_first.AsVector3(),motion.CtrlPressed);Overlay.QueueRedraw();return true;}if(_drag.Count>0){var point=_position(info,motion.Position,_drag["point"].AsVector3(),motion.CtrlPressed);if(point.VariantType==Variant.Type.Vector3){_drag["point"]=point;Overlay.QueueRedraw();}return true;}}
        if(input is not InputEventMouseButton mouse||mouse.ButtonIndex!=MouseButton.Left)return false;
        if(!mouse.Pressed)
        {
            if(_drag.Count==0)return false;var next=new WorldSourceOperations().copy(source);var roads=next.Get("roads").AsGodotArray();var road=roads[road_index].AsGodotDictionary();var points=road["points"].AsVector3Array();var point=_drag["point"].AsVector3();_drag=new Settings();if(points[point_index].IsEqualApprox(point))return true;points[point_index]=point;road["points"]=points;
            if(point_index==0||point_index==points.Length-1){var node=road[point_index==0?"from":"to"];next.Get("nodes").AsGodotDictionary()[node]=point;foreach(var value in roads){var entry=value.AsGodotDictionary();var controls=entry["points"].AsVector3Array();if(entry["from"].AsString()==node.AsString())controls[0]=point;if(entry["to"].AsString()==node.AsString())controls[^1]=point;entry["points"]=controls;}}Owner.EmitSignal("world_replaced",info["id"].AsString(),next);return true;
        }
        Owner.GrabFocus();if(Mode=="Draw road")
        {var point=_position(info,mouse.Position,Vector3.Zero,mouse.CtrlPressed);if(point.VariantType!=Variant.Type.Vector3)return true;if(_first.VariantType==Variant.Type.Nil){_first=point;_hover=point;Overlay.QueueRedraw();return true;}if(_first.AsVector3().DistanceTo(point.AsVector3())<1)return true;var next=new WorldSessionOperations().add_road(source,_first.AsVector3(),point.AsVector3());_first=default;_hover=default;Owner.EmitSignal("world_replaced",info["id"].AsString(),next);return true;}
        double best=12;var nearest=new Settings();var pose=info["pose"].AsTransform3D();var entries=source.Get("roads").AsGodotArray();for(int road=0;road<entries.Count;road++){var points=entries[road].AsGodotDictionary()["points"].AsVector3Array();for(int index=0;index<points.Length;index++){var world=pose*points[index];if(Camera.IsPositionBehind(world))continue;double distance=Project(world).DistanceTo(mouse.Position);if(distance<best){best=distance;nearest=new Settings {["road"]=road,["index"]=index,["point"]=points[index]};}}}
        if(nearest.Count>0){road_index=nearest["road"].AsInt32();point_index=nearest["index"].AsInt32();_drag=new Settings {["point"]=nearest["point"],["road_id"]=entries[road_index].AsGodotDictionary()["id"]};return true;}
        if(mouse.ShiftPressed)
        {
            double bestEdge=double.PositiveInfinity;var edgeInfo=new Settings();for(int road=0;road<entries.Count;road++){var points=entries[road].AsGodotDictionary()["points"].AsVector3Array();for(int edge=0;edge<points.Length-1;edge++){var a=pose*points[edge];var b=pose*points[edge+1];if(Camera.IsPositionBehind(a)||Camera.IsPositionBehind(b))continue;double distance=mouse.Position.DistanceTo(Geometry2D.GetClosestPointToSegment(mouse.Position,Project(a),Project(b)));if(distance<bestEdge){bestEdge=distance;edgeInfo=new Settings {["road"]=road,["edge"]=edge,["point"]=points[edge].Lerp(points[edge+1],.5f)};}}}
            if(edgeInfo.Count>0){var point=_position(info,mouse.Position,edgeInfo["point"].AsVector3(),mouse.CtrlPressed);if(point.VariantType==Variant.Type.Vector3){var next=new WorldSourceOperations().copy(source);var road=next.Get("roads").AsGodotArray()[edgeInfo["road"].AsInt32()].AsGodotDictionary();var points=new List<Vector3>(road["points"].AsVector3Array());points.Insert(edgeInfo["edge"].AsInt32()+1,point.AsVector3());road["points"]=points.ToArray();Owner.EmitSignal("world_replaced",info["id"].AsString(),next);}}
        }
        return true;
    }
}
