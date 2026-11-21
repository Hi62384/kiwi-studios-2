using Godot;
using System;
using System.Collections.Generic;

public partial class TerrainSliceView : PopupPanel
{
    public Resource? source {get;set;}
    public TextureRect preview {get;set;}=new();
    public Label progress {get;set;}=new();
    public TerrainSliceJob? _job {get;private set;}
    public Godot.Collections.Array<TerrainSliceJob> _retired {get;set;}=new();
    private readonly Godot.Collections.Array<TerrainSliceJob> _pins=new();
    private bool _exiting;
    public override void _Ready()
    {
        var margin=new MarginContainer();AddChild(margin);foreach(string side in new[]{"left","right","top","bottom"})margin.AddThemeConstantOverride("margin_"+side,12);
        var column=new VBoxContainer {CustomMinimumSize=new Vector2(620,420)};margin.AddChild(column);var row=new HBoxContainer();column.AddChild(row);row.AddChild(new Label {Text="DENSITY SLICE",SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});var close=new Button {Text="×"};row.AddChild(close);close.Pressed+=Hide;
        var controls=new HBoxContainer();column.AddChild(controls);controls.AddChild(new Label {Text="Height (Y)"});var height=new DragNumber();height.MinValue=-100000;height.MaxValue=100000;height.Step=.1;height.CustomMinimumSize=new Vector2(140,0);controls.AddChild(height);height.ValueChanged+=_generate;height.Connect("drag_committed",Callable.From<double>(_generate));
        progress.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;controls.AddChild(progress);column.AddChild(new Label {Text="Brown: solid    Teal: air    White: boundary"});preview.CustomMinimumSize=new Vector2(600,340);preview.ExpandMode=TextureRect.ExpandModeEnum.IgnoreSize;preview.StretchMode=TextureRect.StretchModeEnum.KeepAspectCentered;column.AddChild(preview);PopupHide+=QueueFree;_generate(0);
    }
    public void _generate(double height)
    {
        if(source==null||_exiting)return;if(_job!=null){_job.cancel();_retired.Add(_job);}_job=new TerrainSliceJob();_pins.Add(_job);_job.start(source,height);progress.Text="Sampling…";
    }
    public override void _Process(double delta)
    {
        for(int index=_retired.Count-1;index>=0;index--)if(_retired[index].complete()){var job=_retired[index];job.collect();_retired.RemoveAt(index);_pins.Remove(job);}
        if(_job==null||!_job.complete())return;var current=_job;current.collect();
        if(!current.canceled()&&current.pixels.Length==96*96*4){using var image=Image.CreateFromData(96,96,false,Image.Format.Rgba8,current.pixels);preview.Texture=ImageTexture.CreateFromImage(image);progress.Text=$"Y = {current.height:F2} m";}
        else if(current.error.Length>0)progress.Text=current.error;_job=null;_pins.Remove(current);
    }
    public override void _ExitTree()
    {
        _exiting=true;if(_job!=null){_job.cancel();_retired.Add(_job);}foreach(var job in _retired)job.cancel();foreach(var job in _retired)job.collect();_retired.Clear();_job=null;_pins.Clear();
    }
}
