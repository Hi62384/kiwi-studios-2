using Godot;
using System;
using System.Globalization;

public partial class EnvironmentWorkspaceOperations
{
    public double transform_value(Resource item,string kind,int axis)
    {var transform=item.Get("transform").AsTransform3D();return kind=="Position"?transform.Origin[axis]:kind=="Rotation"?Mathf.RadToDeg(transform.Basis.GetEuler()[axis]):transform.Basis.Scale[axis];}
    public void edit_transform(Control owner,Resource item,string kind,int axis,double value)
    {
        if(Mathf.IsEqualApprox(transform_value(item,kind,axis),value))return;var session=Session(owner);if(_models.component(Document(session),item.Get("id").AsString())!=item)return;
        session.Call("begin");var transform=item.Get("transform").AsTransform3D();if(kind=="Position"){var origin=transform.Origin;origin[axis]=(float)value;transform.Origin=origin;}
        else{var rotation=transform.Basis.GetEuler();var scale=transform.Basis.Scale;if(kind=="Rotation")rotation[axis]=Mathf.DegToRad((float)value);else scale[axis]=Math.Abs(value)>.0001?(float)value:.0001f;transform.Basis=Basis.FromEuler(rotation)*Basis.FromScale(scale);}
        item.Set("transform",transform);session.Call("commit","Change component "+kind.ToLowerInvariant());
    }
    public void changed(Control owner)
    {
        owner.Get("canvas").As<Control>().Call("request_sync");owner.EmitSignal("document_changed");owner.Set("_refresh_pending",true);var session=Session(owner);var item=session.Call("primary").As<Resource>();if(item==null)return;
        foreach(var entry in owner.Get("_transform_inputs").AsGodotDictionary())
        {
            var input=entry.Value.As<SpinBox>();if(!GodotObject.IsInstanceValid(input)||input.Get("_pressed").AsBool()||input.GetLineEdit().HasFocus())continue;string[] key=entry.Key.AsString().Split(':');input.SetValueNoSignal(transform_value(item,key[0],int.Parse(key[1],CultureInfo.InvariantCulture)));
        }
    }
    public void process(Control owner)
    {
        poll_generation(owner);var session=Session(owner);var canvas=owner.Get("canvas").As<Control>();var renderer=canvas.Get("renderer").As<Node3D>();var jobs=Jobs(owner);var bake=owner.Get("_terrain_bake").As<RefCounted>();owner.Get("_generation_cancel").As<Button>().Visible=bake!=null||jobs.Count>0||renderer.Get("scatter_jobs").AsGodotDictionary().Count>0||session.Call("_pending_source_valid").AsBool();
        if(bake!=null)Status(owner,"Baking full terrain · "+Math.Round(bake.Get("progress").AsDouble()*100,MidpointRounding.AwayFromZero).ToString(CultureInfo.InvariantCulture)+"%");
        string tool=canvas.Get("environment_tool").AsString();string helper=tool.StartsWith("Cave ",StringComparison.Ordinal)?"cave_tool":tool=="Water paths"?"water_tool":"";
        if(helper.Length>0&&jobs.Count==0){var editor=canvas.Get(helper).As<RefCounted>();if(editor.Call("target").AsGodotDictionary().Count==0){editor.Call("cancel");canvas.Set("environment_tool","Select");owner.Set("_refresh_pending",true);}}
        bool gesture=canvas.Get("_painting").AsBool()||canvas.Get("_drag").AsBool();
        if(owner.IsVisibleInTree()&&!gesture&&jobs.Count==0)
        {
            foreach(var value in Document(session).Get("components").AsGodotArray())
            {
                string id=value.As<Resource>().Get("id").AsString();var terrain=_documents.terrain(Document(session),id);if(terrain==null)continue;bool valid=terrain.Call("water_valid").AsBool()&&_terrain.biomes_valid(terrain)&&_terrain.volumes_valid(terrain)&&_terrain.cave_biomes_valid(terrain);
                if(!valid&&Get(State(owner,"_failed_volumes"),id,-1L).AsInt64()!=_terrain.signature(terrain)){regenerate_terrain(owner,id,new Godot.Collections.Dictionary(),false,true);break;}
            }
            if(jobs.Count==0)GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_dependencies.gd").Call("poll",owner);
        }
        if(!owner.Get("_refresh_pending").AsBool()||!owner.IsVisibleInTree()||gesture)return;owner.Set("_refresh_pending",false);owner.Get("title").As<Label>().Text="ENVIRONMENT  /  "+Document(session).Get("title").AsString();owner.Call("_refresh_tree");owner.Call("_refresh_context");owner.Call("_refresh_properties");var errors=renderer.Get("errors").AsStringArray();if(errors.Length>0)Status(owner,errors[0]);
    }
}
