using Godot;

using GArray = Godot.Collections.Array;

using Settings = Godot.Collections.Dictionary;



public partial class AudioWorkspaceLayoutOperations : RefCounted

{

    private static Node Workspace(Node owner)=>owner.GetParent();

    private static T Field<T>(GodotObject owner,string key) where T:GodotObject=>(T)owner.Get(key).AsGodotObject();

    public MenuButton menu(Node owner,Node parent,string label,GArray items)

    {

        var w=Workspace(owner);var button=new MenuButton{Text=label+" ▾"};parent.AddChild(button);

        var popup=button.GetPopup();popup.AddThemeStyleboxOverride("panel",w.Call("_box",new Color("162430"),new Color("3c5868"),8).As<StyleBox>());popup.AddThemeFontSizeOverride("font_size",12);popup.AddThemeConstantOverride("v_separation",10);

        var callbacks=new Settings();foreach(var raw in items)

        {

            if(raw.VariantType==Variant.Type.String){popup.AddSeparator(raw.AsString());continue;}

            var entry=raw.AsGodotArray();int id=popup.ItemCount;popup.AddItem(entry[0].AsString(),id);callbacks[id]=entry[1];

        }

        // Preserve script callables as Variants; dispatch them through their owning language.

        popup.IdPressed+=id=>owner.Call("_dispatch_menu",callbacks,(int)id);return button;

    }

    public HBoxContainer group(Node owner,Node parent)

    {

        var panel=new PanelContainer();panel.AddThemeStyleboxOverride("panel",Workspace(owner).Call("_box",new Color("16232e"),new Color("293f50"),6).As<StyleBox>());parent.AddChild(panel);var row=new HBoxContainer();row.AddThemeConstantOverride("separation",4);panel.AddChild(row);return row;

    }

    public VBoxContainer fold(Node owner,Node parent,string key,string label,bool open)

    {

        var folds=owner.Get("folds").AsGodotDictionary();bool enabled=folds.TryGetValue(key,out var saved)?saved.AsBool():open;

        var box=new VBoxContainer();parent.AddChild(box);var button=new Button{Alignment=HorizontalAlignment.Left,ToggleMode=true,ButtonPressed=enabled};box.AddChild(button);var body=new VBoxContainer();body.AddThemeConstantOverride("separation",6);box.AddChild(body);

        void Update(bool value){button.Text=(value?"▾  ":"▸  ")+label;body.Visible=value;folds[key]=value;}

        button.Toggled+=Update;Update(enabled);return body;

    }

    public void toggle_automation(Node owner)

    {

        var panel=Field<VBoxContainer>(owner,"automation_panel");if(panel.Visible){Workspace(owner).Call("_finish_automation_pass","Automation controls closed");panel.Hide();}else panel.Show();

    }

    public void show_detail(Node owner,int index)

    {

        var w=Workspace(owner);var clip=Field<RefCounted>(w,"session").Call("primary_clip").AsGodotObject();if(index==0&&clip!=null)w.Call("edit_clip",clip.Get("id"));var bottom=Field<TabContainer>(w,"bottom");bottom.Show();bottom.CurrentTab=index;

    }

    public void selected(Node owner)

    {

        owner.Set("inspector_view","");var actions=Field<Control>(owner,"clip_actions");if(actions!=null)actions.Visible=Field<RefCounted>(Workspace(owner),"session").Get("selected_ids").AsGodotArray().Count>0;

    }

    public void sync(Node owner)

    {

        var w=Workspace(owner);var session=Field<RefCounted>(w,"session");var empty=Field<Control>(owner,"empty_state");if(empty!=null)empty.Visible=session.Get("document").AsGodotObject().Get("clips").AsGodotArray().Count==0;

        var actions=Field<Control>(owner,"clip_actions");if(actions!=null)actions.Visible=session.Get("selected_ids").AsGodotArray().Count>0;

        var detail=Field<Button>(owner,"detail_button");if(detail!=null){bool visible=Field<Control>(w,"bottom").Visible;detail.Text=visible?"Close editor":"Open editor";detail.Disabled=!visible&&session.Call("primary_clip").AsGodotObject()==null;detail.TooltipText=detail.Disabled?"Select a clip to open its editor. View opens the mixer and other editors.":"Double-click a clip to edit. Close editor returns the space to the timeline.";}

        bool busy=Field<GodotObject>(w,"jobs").Call("busy").AsBool()||Field<GodotObject>(Field<GodotObject>(w,"_optional_tools"),"jobs").Call("busy").AsBool()||w.Get("_record_busy").AsBool()||Field<GodotObject>(w,"_portable_jobs").Call("busy").AsBool()||Field<GodotObject>(w,"_recovery_jobs").Call("busy").AsBool();Field<Control>(w,"progress").Visible=busy;

        var busyButton=Field<Button>(owner,"busy_button");if(busyButton!=null)busyButton.Visible=busy;var automation=Field<Control>(owner,"automation_panel");if(automation!=null&&Field<GodotObject>(w,"automation_recording").Get("mode").AsString()!="Read")automation.Show();

    }



    public void organize_inspector(Node owner)

    {

        var w=Workspace(owner);var parent=Field<VBoxContainer>(w,"inspector");var children=parent.GetChildren();var tabs=new HBoxContainer();parent.AddChild(tabs);parent.MoveChild(tabs,0);

        var groups=new System.Collections.Generic.Dictionary<string,VBoxContainer>();foreach(string id in new[]{"clip","track","project"}){var body=new VBoxContainer();body.AddThemeConstantOverride("separation",8);parent.AddChild(body);groups[id]=body;}

        string key=Field<RefCounted>(w,"session").Call("primary_clip").AsGodotObject()!=null?"clip":"track";

        foreach(var child in children){if(child is Label label){if(label.Text.StartsWith("CLIP ·"))key="clip";else if(label.Text.StartsWith("TRACK ·"))key="track";else if(label.Text=="PROJECT")key="project";}child.Reparent(groups[key]);}

        string view=owner.Get("inspector_view").AsString();if(view.Length==0||!groups.ContainsKey(view)||groups[view].GetChildCount()==0)view=groups["clip"].GetChildCount()>0?"clip":groups["track"].GetChildCount()>0?"track":"project";owner.Set("inspector_view",view);

        foreach(var pair in groups){string id=pair.Key;var body=pair.Value;body.Visible=id==view;if(body.GetChildCount()==0)continue;var button=new Button{Text=id.Capitalize(),ToggleMode=true,ButtonPressed=id==view,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill};tabs.AddChild(button);button.Pressed+=()=>{owner.Set("inspector_view",id);w.Call("_refresh_inspector");};}

        VBoxContainer? timing=null,instrument=null;bool instrumentRows=false;

        foreach(var child in groups["clip"].GetChildren())

        {

            if(child is Label label){if(label.Text=="INSTRUMENT"){instrument=fold(owner,groups["clip"],"clip_instrument","Instrument settings",false);instrumentRows=true;}else if(label.Text=="SELECTED NOTE")instrumentRows=false;}

            if(instrumentRows){child.Reparent(instrument!);continue;}

            string caption=child is HBoxContainer&&child.GetChildCount()>0&&child.GetChild(0) is Label first?first.Text:"";

            if(caption is "Start (s)" or "Duration (s)" or "Source offset" or "Speed" or "Pitch (semi)" || child is CheckBox check&&check.Text is "Loop source" or "Reverse (rendered)"){timing??=fold(owner,groups["clip"],"clip_timing","Timing & playback",false);child.Reparent(timing);}

        }

        VBoxContainer? tools=null;foreach(var child in groups["track"].GetChildren())

        {

            bool advanced=child is Button&&child is not ColorPickerButton;if(child is HBoxContainer&&child.GetChildCount()>0&&child.GetChild(0) is Label label)advanced=label.Text=="Output";

            if(advanced){tools??=fold(owner,groups["track"],"track_tools","Routing & track tools",false);child.Reparent(tools);}

        }

    }



    private static Button Button(GodotObject w,Node parent,string text,System.Action action,string hint="")=>w.Call("_button",parent,text,Callable.From(action),hint).As<Button>();

    public void header(Node owner,Node parent,GArray sections)

    {

        var w=Workspace(owner);var row=new HBoxContainer();row.AddThemeConstantOverride("separation",5);parent.AddChild(row);var title=Field<Label>(w,"title_label");title.Text="Audio";title.CustomMinimumSize=new Vector2(120,title.CustomMinimumSize.Y);title.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;title.TextOverrunBehavior=TextServer.OverrunBehavior.TrimEllipsis;title.AddThemeFontSizeOverride("font_size",17);title.AddThemeColorOverride("font_color",new Color("7bdcc4"));row.AddChild(title);

        foreach(var raw in sections){var section=raw.AsGodotArray();var button=menu(owner,row,section[0].AsString(),section[1].AsGodotArray());if(section[0].AsString()=="View")owner.Get("_menus").AsGodotDictionary()["view"]=button;}

        Button(w,row,"Save",()=>w.Call("save"),"Save composition · Ctrl+S");var send=new Button();send.Hide();owner.AddChild(send);w.Set("send_scene_button",send);send.Pressed+=()=>w.Call("send_to_scene");var recovery=Field<Control>(w,"_recovery_status");recovery.Hide();owner.AddChild(recovery);

    }

    public void detail_controls(Node owner,Node parent)

    {

        var w=Workspace(owner);var row=new HBoxContainer();parent.AddChild(row);var caption=w.Call("_label",row,"TIMELINE").As<Label>();caption.AddThemeColorOverride("font_color",new Color("7bdfc6"));caption.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;

        Button(w,row,"+ Track",()=>w.Call("add_track_dialog"),"Add an audio, instrument or automation track");owner.Set("detail_button",Button(w,row,"Open editor",()=>{var bottom=Field<Control>(w,"bottom");if(bottom.Visible){bottom.Hide();return;}var actor=Field<RefCounted>(w,"session").Call("primary_actor").AsGodotObject();using var edits=new AudioEditSessionOperations();show_detail(owner,actor!=null&&edits.is_note_source(actor)?1:0);},"Double-click an audio clip to edit its waveform. View opens every other editor."));Button(w,row,"Fit",()=>w.Call("fit_timeline"),"Fit clips in the visible timeline");

    }

    public void install_empty_state(Node owner,GArray items)

    {

        var w=Workspace(owner);var empty=new CenterContainer{MouseFilter=Control.MouseFilterEnum.Ignore};empty.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);empty.OffsetLeft=174;empty.OffsetTop=70;Field<Control>(w,"canvas").AddChild(empty);owner.Set("empty_state",empty);

        var content=new VBoxContainer{MouseFilter=Control.MouseFilterEnum.Ignore};content.AddThemeConstantOverride("separation",10);empty.AddChild(content);var title=w.Call("_label",content,"Start with a sound").As<Label>();title.HorizontalAlignment=HorizontalAlignment.Center;title.AddThemeFontSizeOverride("font_size",21);var hint=w.Call("_label",content,"Import a file, or drag a sound from the library onto this timeline.").As<Label>();hint.HorizontalAlignment=HorizontalAlignment.Center;hint.CustomMinimumSize=new Vector2(240,0);hint.AddThemeColorOverride("font_color",new Color("91a6b5"));var actions=new HBoxContainer{Alignment=BoxContainer.AlignmentMode.Center};content.AddChild(actions);Button(w,actions,"+ Import audio",()=>w.Call("import_audio"));menu(owner,actions,"Create",items);

    }

}

