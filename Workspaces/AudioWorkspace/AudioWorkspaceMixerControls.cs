using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class AudioWorkspaceOperations
{
    public void bind_mixer_slider(Control o,Slider slider,Settings target,Settings track)
    {
        var owner=Field<RefCounted>(o,"session");var document=owner.Get("document").As<RefCounted>();var state=new Settings{["held"]=false,["blocked"]=false,["automation"]=false,["epoch"]=0,["changed"]=false,["gesture"]=o.Call("_new_parameter_gesture")};Items(o,"_mixer_gestures").Add(state);
        bool Editable()=>mixer_context_current(o,slider,owner,document)&&o.Call("_mixer_target_editable",target).AsBool();
        slider.DragStarted+=()=>
        {
            if(!Editable())return;finish_mixer_gesture(o,state,true);state["blocked"]=false;state["automation"]=o.Call("_automation_consumes",target);state["changed"]=false;if(state["automation"].AsBool()){commit_parameter_edit(o);o.Call("_automation_gesture_start");}else
            {
                o.Call("_finish_automation_pass","Mixer edit ended the pass");var pending=Field<RefCounted>(o,"_parameter_gesture");if(pending.Call("valid",owner).AsBool()&&o.Get("_parameter_control_id").AsUInt64()==slider.GetInstanceId()){state["gesture"]=pending;state["changed"]=true;o.Set("_parameter_gesture",o.Call("_new_parameter_gesture"));Field<Timer>(o,"_edit_timer").Stop();o.Set("_parameter_control_id",0);}else{commit_parameter_edit(o);state["gesture"].AsGodotObject().Call("begin",owner,"Mix volume");}
            }
            state["epoch"]=o.Get("_interaction_epoch");state["held"]=true;
        };
        slider.ValueChanged+=value=>
        {
            if(state["blocked"].AsBool()||!Editable())return;if(state["held"].AsBool())
            {
                if(state["epoch"].AsInt64()!=o.Get("_interaction_epoch").AsInt64())return;if(state["automation"].AsBool()){if(o.Call("_automation_consumes",target).AsBool())o.Call("_automation_control_changed",value);return;}if(!state["gesture"].AsGodotObject().Call("valid",owner).AsBool())return;if(Mathf.IsEqualApprox(Get(track,"volume_db",0).AsDouble(),value))return;track["volume_db"]=value;state["changed"]=true;owner.Call("preview");
            }
            else
            {
                if(o.Call("_automation_consumes",target).AsBool()){o.Call("_automation_control_changed",value);return;}var previous=o.Get("_edit_control_id");o.Set("_edit_control_id",slider.GetInstanceId());try{edit(o,"Mix volume",Callable.From(()=>track["volume_db"]=value));}finally{o.Set("_edit_control_id",previous);}
            }
            Field<Node>(o,"playback").Call("synchronize");
        };
        slider.DragEnded+=_=>{finish_mixer_gesture(o,state,true);state["blocked"]=false;};slider.FocusExited+=()=>finish_mixer_gesture(o,state,true);slider.FocusEntered+=()=>{if(!state["held"].AsBool())state["blocked"]=false;};slider.TreeExiting+=()=>finish_mixer_gesture(o,state,true);slider.GuiInput+=input=>{if(input is InputEventKey key&&key.Pressed&&key.Keycode==Key.Escape){finish_mixer_gesture(o,state,false);slider.AcceptEvent();}};
    }
}
