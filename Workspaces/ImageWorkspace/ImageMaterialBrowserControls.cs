using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageMaterialBrowserOperations
{
    private static void Number(Control owner,Node parent,string caption,double current,double min,double max,double step,System.Action<double> callback)
    {
        var row=new HBoxContainer();parent.AddChild(row);var label=new Label{Text=caption,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};label.AddThemeFontSizeOverride("font_size",11);row.AddChild(label);var slider=new HSlider{MinValue=min,MaxValue=max,Step=step,Value=current,CustomMinimumSize=new Vector2(72,0)};row.AddChild(slider);var number=new SpinBox{MinValue=min,MaxValue=max,Step=step,Value=current,CustomMinimumSize=new Vector2(78,0)};row.AddChild(number);slider.ValueChanged+=next=>{number.SetValueNoSignal(next);callback(next);};slider.DragEnded+=_=>Commit(owner);number.ValueChanged+=next=>{slider.SetValueNoSignal(next);callback(next);Commit(owner);};
    }
    private static void Choice(Control owner,Node parent,string caption,GArray captions,GArray ids,string current,System.Action<string> callback)
    {
        var row=new HBoxContainer();parent.AddChild(row);var label=new Label{Text=caption,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};label.AddThemeFontSizeOverride("font_size",11);row.AddChild(label);var choice=new OptionButton{SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,FitToLongestItem=false,CustomMinimumSize=new Vector2(120,0)};foreach(var text in captions)choice.AddItem(text.AsString());choice.Select(Math.Max(0,ids.IndexOf(current)));row.AddChild(choice);choice.ItemSelected+=index=>{callback(ids[(int)index].AsString());Commit(owner);};
    }
    public Button button(Control owner,Node parent,string caption,Variant callback)=>Button(parent,caption,()=>owner.Call("_invoke_action",callback));
    public void number(Control owner,Node parent,string caption,double current,double min,double max,double step,Variant callback)=>Number(owner,parent,caption,current,min,max,step,next=>owner.Call("_invoke_value",callback,next));
    public void choice(Control owner,Node parent,string caption,GArray captions,GArray ids,string current,Variant callback)=>Choice(owner,parent,caption,captions,ids,current,next=>owner.Call("_invoke_value",callback,next));
    public void rebuild_fields(Control owner)
    {
        var fields=owner.Get("fields").As<VBoxContainer>();Clear(fields);var value=Value(owner);var parameters=value.Get("parameters").AsGodotDictionary();var studio=Studio(owner);var name=new LineEdit{Text=value.Get("label").AsString()};fields.AddChild(name);name.TextSubmitted+=next=>{value.Set("label",next);changed(owner);Commit(owner);};
        foreach(string key in new[]{"primary","secondary"})
        {
            var row=new HBoxContainer();fields.AddChild(row);row.AddChild(new Label{Text=key=="primary"?"Primary color":"Secondary color",SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});var picker=new ColorPickerButton{Color=Get(parameters,key,Colors.White).AsColor(),CustomMinimumSize=new Vector2(92,26)};row.AddChild(picker);picker.ColorChanged+=next=>{parameters[key]=next;changed(owner);};picker.PopupClosed+=()=>Commit(owner);
        }
        void Property(Node parent,string caption,string key,double min,double max,double step)=>Number(owner,parent,caption,value.Get(key).AsDouble(),min,max,step,next=>{value.Set(key,next);changed(owner);});
        void Parameter(Node parent,string caption,string key,double fallback,double min,double max,double step,bool integer=false)=>Number(owner,parent,caption,Get(parameters,key,fallback).AsDouble(),min,max,step,next=>{parameters[key]=integer?Variant.From((int)next):Variant.From(next);changed(owner);});
        Property(fields,"Texture Size","texture_size",2,2048,1);
        if(value.Get("image").AsGodotObject()==null)foreach(var parameter in _definitions.schema(value.Get("material_id").AsString())){var item=parameter.AsGodotDictionary();Parameter(fields,item["label"].AsString(),item["key"].AsString(),item["default"].AsDouble(),item["min"].AsDouble(),item["max"].AsDouble(),item["step"].AsDouble());}
        var emboss=new CheckButton{Text=studio!=null?"Emboss":"Surface relief",ButtonPressed=!Mathf.IsZeroApprox(value.Get("relief").AsDouble())};fields.AddChild(emboss);emboss.Toggled+=enabled=>{value.Set("relief",enabled?.6:0);changed(owner);Commit(owner);rebuild_fields(owner);};
        if(!Mathf.IsZeroApprox(value.Get("relief").AsDouble())){Property(fields,studio!=null?"Emboss strength":"Relief strength","relief",0,2,.01);if(studio!=null)Property(fields,"Shadow direction","light_direction",0,360,1);}
        var advanced=new VBoxContainer();Button(fields,"Advanced",()=>{bool open=!owner.Get("_advanced_open").AsBool();owner.Set("_advanced_open",open);advanced.Visible=open;});fields.AddChild(advanced);advanced.Visible=owner.Get("_advanced_open").AsBool();Property(advanced,"Rotation","rotation",-180,180,1);Parameter(advanced,"Seed","seed",0,0,100000,1,true);Parameter(advanced,"Contrast","contrast",1,0,3,.01);
        var mapping=new OptionButton{Visible=studio!=null};advanced.AddChild(mapping);foreach(string caption in new[]{"Canvas aligned","Layer aligned","Stroke direction aligned"})mapping.AddItem(caption);var mappings=new[]{"canvas","layer","stroke"};mapping.Select(Math.Max(0,Array.IndexOf(mappings,value.Get("alignment").AsString())));mapping.ItemSelected+=index=>{value.Set("alignment",mappings[index]);changed(owner);Commit(owner);};
        if(value.Get("image").AsGodotObject()!=null){Property(advanced,"Image tint","tint_strength",0,1,.01);Choice(owner,advanced,"Image tiling",new GArray{"Repeat","Mirror","Clamp"},new GArray{"repeat","mirror","clamp"},value.Get("tiling").AsString(),next=>{value.Set("tiling",next);changed(owner);});}
        if(studio!=null)
        {
            Choice(owner,advanced,"Brush application",new GArray{"Continuous","Stamps","Scatter"},new GArray{"continuous","stamp","scatter"},value.Get("application").AsString(),next=>{value.Set("application",next);changed(owner);rebuild_fields(owner);});
            if(value.Get("application").AsString()!="continuous")
            {
                Property(advanced,"Stamp spacing","spacing",.1,3,.05);if(value.Get("application").AsString()=="scatter")Property(advanced,"Scatter spread","jitter",0,1,.01);Property(advanced,"Random rotation","random_rotation",0,180,1);Property(advanced,"Random scale","random_scale",0,1,.01);var follow=new CheckButton{Text="Follow stroke direction",ButtonPressed=value.Get("follow_direction").AsBool()};advanced.AddChild(follow);follow.Toggled+=next=>{value.Set("follow_direction",next);changed(owner);Commit(owner);};
            }
        }
        var blendIds=new GArray{""};var blendNames=new GArray{"No second material"};foreach(var id in _definitions.ids()){blendIds.Add(id);using var preset=_definitions.create(id.AsString());blendNames.Add(preset.Get("label"));}var custom=owner.Get("custom_materials").AsGodotDictionary();foreach(var pair in custom){blendIds.Add(pair.Key);blendNames.Add(pair.Value.AsGodotObject().Get("label"));}var second=value.Get("secondary").As<Resource>();
        Choice(owner,advanced,"Mix material",blendNames,blendIds,second?.Get("material_id").AsString()??"",next=>{var selected=custom.ContainsKey(next)?_resources.copy_material(custom[next].As<Resource>()):next.Length>0?_definitions.create(next):null;value.Set("secondary",selected==null?default(Variant):Variant.From(selected));if(selected!=null){selected.Set("secondary",default(Variant));value.Set("mix_amount",Math.Max(.5,value.Get("mix_amount").AsDouble()));}changed(owner);rebuild_fields(owner);});
        if(second!=null){Property(advanced,"Mix amount","mix_amount",0,1,.01);Choice(owner,advanced,"Mix distribution",new GArray{"Uniform","Noise","Patches"},new GArray{"uniform","noise","patches"},value.Get("mix_distribution").AsString(),next=>{value.Set("mix_distribution",next);changed(owner);});Number(owner,advanced,"Second texture size",second.Get("texture_size").AsDouble(),2,2048,1,next=>{second.Set("texture_size",next);changed(owner);});Number(owner,advanced,"Second rotation",second.Get("rotation").AsDouble(),-180,180,1,next=>{second.Set("rotation",next);changed(owner);});}
    }
}
