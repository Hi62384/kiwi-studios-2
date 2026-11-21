using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using static RigUiToolbar;

public partial class RigUiInspector : RefCounted
{
    private readonly RigMath _math=new();
    private readonly RigUiToolbar _toolbar=new();
    private static RigViewport View(Control workspace)=>Canvas(workspace).Get("rig_tool").As<RefCounted>().Get("_native").As<RigViewport>();
    private static RefCounted Session(Control workspace)=>workspace.Get("session").As<RefCounted>();
    private static Settings Bone(RigEditor editor)=>editor.rig()!.Get("bones").AsGodotArray()[editor.selected_bone].AsGodotDictionary();
    private static Control Number(Control workspace,Node parent,string title,double value,double min,double max,double step,Action<double> changed)
        =>workspace.Call("_number",parent,title,value,min,max,step,Callable.From<double>(next=>changed(next))).As<Control>();
    private static void Vector(Control workspace,VBoxContainer parent,string title,Vector3 value,Action<Vector3> changed)
    {
        Label(parent,title);var row=new HBoxContainer();parent.AddChild(row);
        for(int i=0;i<3;i++){int axis=i;var control=Number(workspace,row,new[]{"X","Y","Z"}[axis],value[axis],-10000,10000,.01,next=>{value[axis]=(float)next;changed(value);});control.CustomMinimumSize=new Vector2(55,control.CustomMinimumSize.Y);control.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;}
    }
    public void build_properties(Control workspace,RefCounted state,VBoxContainer parent)
    {
        var editor=Editor(workspace);var tool=View(workspace);void Refresh()=>_toolbar.refresh(workspace);
        Label(parent,"ARMATURE / RIGGING");var rigs=Session(workspace).Get("document").As<Resource>().Get("components").AsGodotArray().Select(v=>v.As<Resource>()).Where(r=>r.Get("is_skeleton").AsBool()).ToList();var armature=editor.rig();
        var picker=new OptionButton{Name="RigPicker",SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,ClipText=true};parent.AddChild(picker);foreach(var rig in rigs) picker.AddItem(rig.Get("title").AsString());if(armature!=null) picker.Select(rigs.IndexOf(armature));
        picker.ItemSelected+=index=>{editor.rig_id=rigs[(int)index].Get("id").AsString();editor.selected_bone=0;Refresh();};
        if(armature==null){Button(parent,"＋ Quick Rig",()=>_toolbar.quick_rig(workspace,state));Button(parent,"Load rig preset…",()=>state.Call("load_preset"));return;}
        var bones=armature.Get("bones").AsGodotArray();
        if(bones.Count>0)
        {
            var input=new OptionButton{Name="AuthoringBonePicker",SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,ClipText=true};parent.AddChild(input);foreach(Variant b in bones) input.AddItem(b.AsGodotDictionary()["name"].AsString());input.Select(editor.selected_bone);input.ItemSelected+=index=>{editor.selected_bone=(int)index;Refresh();};var bone=Bone(editor);
            if(editor.mode is "Edit" or "Draw" or "Envelope")
            {
                var name=new LineEdit{Text=bone["name"].AsString(),PlaceholderText="Bone name"};parent.AddChild(name);name.TextSubmitted+=value=>{editor.rename(value);Refresh();};
                string[] names=new[]{"No parent"}.Concat(bones.Select(v=>v.AsGodotDictionary()["name"].AsString())).ToArray();int parentIndex=bone["parent"].AsInt32();
                Choice(parent,names,parentIndex<0?"No parent":names[parentIndex+1],value=>{editor.parent(Array.IndexOf(names,value)-1,editor.connected);Refresh();});
                Toggle(parent,"Preserve connected joints",editor.connected,value=>editor.connected=value);Toggle(parent,"Mirror edits",editor.symmetry,value=>{editor.symmetry=value;Refresh();});
                if(editor.symmetry)
                {
                    string[] axes={"X symmetry","Y symmetry","Z symmetry"};Choice(parent,axes,axes[editor.symmetry_axis],value=>editor.symmetry_axis=Array.IndexOf(axes,value));
                    Number(workspace,parent,"Mirror plane offset",editor.symmetry_offset,-10000,10000,.01,value=>editor.symmetry_offset=value);
                }
                Number(workspace,parent,"Envelope radius",bone["radius"].AsDouble(),.001,1000,.01,value=>Bone(editor)["radius"]=value);
                Number(workspace,parent,"Roll (degrees)",Mathf.RadToDeg((float)bone["roll"].AsDouble()),-360,360,.1,value=>{var selected=Bone(editor);selected["roll"]=Mathf.DegToRad((float)value);var rest=_math.globals(editor.rig()!.Get("bones").AsGodotArray(),false);editor.move_joint(editor.selected_bone,true,_math.tail(selected,rest[editor.selected_bone]));});
                var world=_math.globals(bones,false);Vector(workspace,parent,"Joint Head",world[editor.selected_bone].Origin,value=>editor.move_joint(editor.selected_bone,false,value));Vector(workspace,parent,"Joint Tail",_math.tail(bone,world[editor.selected_bone]),value=>editor.move_joint(editor.selected_bone,true,value));
            }
            else
            {
                foreach(string channel in new[]{"position","rotation","scale"}) Vector(workspace,parent,"Pose "+channel,bone[channel].AsVector3(),value=>{if(channel=="scale") for(int axis=0;axis<3;axis++) if(Mathf.Abs(value[axis])<.001f) value[axis]=.001f;Bone(editor)[channel]=value;});
                Label(parent,"TEST JOINT BEND");string[] axes={"Bend X","Bend Y","Bend Z"};Choice(parent,axes,axes[state.Get("test_axis").AsInt32()],value=>state.Set("test_axis",Array.IndexOf(axes,value)));
                var slider=new HSlider{MinValue=-150,MaxValue=150,Step=1};parent.AddChild(slider);
                slider.DragStarted+=()=>{Session(workspace).Call("begin");workspace.Set("_property_gesture",true);};
                slider.ValueChanged+=value=>{bool standalone=!workspace.Get("_property_gesture").AsBool();if(standalone) Session(workspace).Call("begin");var selected=Bone(editor);Vector3 rotation=selected["rest"].AsTransform3D().Basis.GetRotationQuaternion().GetEuler()*(180/Mathf.Pi);rotation[state.Get("test_axis").AsInt32()]+=(float)value;selected["rotation"]=rotation;Session(workspace).EmitSignal("changed");if(standalone) Session(workspace).Call("commit","Test bone bend");};
                slider.DragEnded+=_=>{workspace.Set("_property_gesture",false);Session(workspace).Call("commit","Test bone bend");};Button(parent,"↺ Reset selected pose",()=>{editor.reset_pose(false);Refresh();});
            }
        }
        if(editor.mode=="Draw") {Label(parent,"DEPTH PLACEMENT");Choice(parent,new[]{"Inside mesh","Surface","View plane","XY","YZ","XZ"},tool.construction,value=>tool.construction=value);Number(workspace,parent,"Plane / depth",tool.depth,-10000,10000,.01,value=>tool.depth=value);}
        if(editor.mode=="Weight") weight_controls(workspace,state,parent);
        var row=new HBoxContainer();parent.AddChild(row);Button(row,"Save rig…",()=>state.Call("save_preset"));Button(row,"Load rig…",()=>state.Call("load_preset"));
        Toggle(parent,"Show skeleton",editor.show_bones,value=>{editor.show_bones=value;Refresh();});Toggle(parent,"Selected chain only",editor.only_chain,value=>{editor.only_chain=value;Refresh();});Toggle(parent,"Compare rest",tool.compare_rest,value=>{tool.compare_rest=value;Refresh();});
        parent.AddChild(new Label{AutowrapMode=TextServer.AutowrapMode.WordSmart,Text=editor.message,Modulate=new Color("a6bfd0")});
    }
    public void weight_controls(Control workspace,RefCounted state,VBoxContainer parent)
    {
        var editor=Editor(workspace);var tool=View(workspace);void Refresh()=>_toolbar.refresh(workspace);var armature=editor.rig();
        if(armature==null||armature.Get("bones").AsGodotArray().Count==0){Label(parent,"Draw or load bones before painting weights.");return;}
        Label(parent,"WEIGHT BRUSH");Choice(parent,new[]{"Brush","Select vertices","Select faces"},tool.weight_tool,value=>{tool.weight_tool=value;Refresh();});Choice(parent,new[]{"Add","Subtract","Replace","Smooth","Clear"},tool.brush_mode,value=>tool.brush_mode=value);
        Number(workspace,parent,"Radius · Shift+wheel",tool.brush_radius,.005,100,.01,value=>tool.brush_radius=value);Number(workspace,parent,"Strength",tool.brush_strength,.001,1,.01,value=>tool.brush_strength=value);
        if(tool.brush_mode=="Replace") Number(workspace,parent,"Target weight",tool.brush_value,0,1,.01,value=>tool.brush_value=value);Number(workspace,parent,"Region weight",tool.brush_value,0,1,.01,value=>tool.brush_value=value);
        Button(parent,"Assign selected region",()=>{tool.fill_region();Refresh();});Button(parent,"Clear region selection",()=>{tool.region.Clear();Refresh();});
        Toggle(parent,"Paint selected vertices only",tool.selected_only,value=>tool.selected_only=value);Toggle(parent,"Paint hidden / back side",tool.paint_hidden,value=>tool.paint_hidden=value);
        string id=Bone(editor)["id"].AsString();bool locked=editor.meshes().Any(item=>item.Get("binding").As<Resource>() is Resource binding&&binding.Get("locked_bones").AsStringArray().Contains(id));
        Toggle(parent,"Lock selected influence",locked,value=>
        {
            var meshes=editor.meshes();string boneId=Bone(editor)["id"].AsString();var session=Session(workspace);session.Call("begin");
            foreach(var item in meshes)
            {var binding=item.Get("binding").As<Resource>();if(binding==null) continue;var ids=binding.Get("locked_bones").AsStringArray().ToList();if(value&&!ids.Contains(boneId)) ids.Add(boneId);else if(!value) ids.RemoveAll(key=>key==boneId);binding.Set("locked_bones",ids.ToArray());}
            session.Call("commit","Lock bone weights");
        });
        Button(parent,"Adopt imported weights",()=>{editor.message=editor.adopt_imported();Refresh();});
        foreach(string action in new[]{"Fix Weights","Normalize","Mirror weights","Clear influence"}) Button(parent,action,()=>{editor.message=editor.cleanup(action);Refresh();},action=="Mirror weights"?"Copy from the selected bone's side to the opposite side; matching mirrored vertices only.":"");
        Button(parent,"Validate skin weights",()=>{var errors=editor.meshes().Where(item=>item.Get("binding").As<Resource>()!=null).SelectMany(item=>item.Get("binding").As<Resource>().Call("validate",editor.rig()!).AsStringArray()).ToArray();editor.message=errors.Length==0?"Weights valid.":string.Join("\n",errors.Take(5));Refresh();});
    }
}
