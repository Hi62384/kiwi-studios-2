using Godot;
using Settings=Godot.Collections.Dictionary;
[GlobalClass]
public partial class KiwiAudioLibrary : VBoxContainer
{
    [Signal] public delegate void selectedEventHandler(Settings entry);
    [Signal] public delegate void preview_requestedEventHandler(Settings entry);
    [Signal] public delegate void add_requestedEventHandler(Settings entry);
    public const string CONFIG_PATH="user://audio_workspace/library.cfg";
    public const int MAX_TAG_FILTER_ITEMS=128;
    public LineEdit search {get;set;}=new();
    public OptionButton category {get;set;}=new();
    public AudioLibraryDragList list {get;set;}=new();
    public Godot.Collections.Array<Settings> entries {get;set;}=new();
    public Settings favorites {get;set;}=new();
    public Godot.Collections.Array<string> recent {get;set;}=new();
    public Godot.Collections.Array<Settings> imported {get;set;}=new();
    public Settings current {get;set;}=new();
    public Variant generator_drag_payload {get;set;}
    public KiwiAudioAssetIndex _index {get;set;}=new();
    public Godot.Collections.Array<string> _project_roots {get;set;}=new();
    public Godot.Collections.Array<Settings> _project_entries {get;set;}=new();
    public long _index_generation {get;set;}
    public string _project_key {get;set;}="";
    public OptionButton _source_menu {get;set;}=new();
    public Label _scan_status {get;set;}=new();
    public Button _refresh_button {get;set;}=new();
    public Button _cancel_button {get;set;}=new();
    public Button _remove_button {get;set;}=new();
    public Button _preview_button {get;set;}=new();
    public Button _add_button {get;set;}=new();
    public FileDialog _folder_dialog {get;set;}=new();
    public OptionButton _preset_kind_filter {get;set;}=new();
    public OptionButton _tag_filter {get;set;}=new();
    public VBoxContainer _filters {get;set;}=new();
    public VBoxContainer _folders {get;set;}=new();
    public Button _folders_toggle {get;set;}=new();
    private readonly AudioLibraryOperations _operations=new();
    public override void _Ready()=>_operations.ready(this);
    public void _build_preset_filters()=>_operations.build_preset_filters(this);
    public void clear_filters()=>_operations.clear_filters(this);
    public void _update_tag_filter()=>_operations.update_tag_filter(this);
    public static string[] preset_tags(KiwiAudioPreset preset)
    {using var operations=new AudioLibraryOperations();return operations.preset_tags(preset);}
    public static string[] _clean_tags(Variant value)
    {using var operations=new AudioLibraryOperations();return operations.clean_tags(value);}
    public void _build_project_controls()=>_operations.build_project_controls(this);
    public void _add_source(string value)=>_operations.add_source(this,value);
    public void _remove_source()=>_operations.remove_source(this);
    public void _update_sources()=>_operations.update_sources(this);
    public void _start_scan()=>_operations.start_scan(this);
    public void _cancel_scan()=>_operations.cancel_scan(this);
    public void _scan_finished(long generation,Settings result)=>_operations.scan_finished(this,(int)generation,result);
    public void reload()=>_operations.reload(this);
    public void refresh()=>_operations.refresh(this);
    public void _selected(long position)=>_operations.selected(this,(int)position);
    public void _update_actions()=>_operations.update_actions(this);
    public bool _can_use_current()=>_operations.can_use_current(this);
    public void _request_preview(){if(_can_use_current())EmitSignal(SignalName.preview_requested,current);}
    public void _request_add(){if(_can_use_current())EmitSignal(SignalName.add_requested,current);}
    public void remember(string id)=>_operations.remember(this,id);
    public void add_asset(Variant source,string label,double duration)=>_operations.add_asset(this,source,label,duration);
    public void toggle_favorite()=>_operations.toggle_favorite(this);
    public void _save(string field)=>_save(field,"");
    public void _save(string field,string changed_id)=>_operations.save(this,field,changed_id);
    public void remember_effect(string id)=>remember("effect_"+id);
    public Godot.Collections.Array<Settings> ranked_effects()=>_operations.ranked_effects(this);
    public static bool valid_entry(Variant value)
    {using var operations=new AudioLibraryOperations();return operations.valid_entry(value);}
    public static RefCounted _native()=>Engine.GetSingleton("KiwiNativeServices").Call("service","audio_library").As<RefCounted>();
    public Variant _generator_drag_data(Settings entry)
    {
        if(!EngineVariantDispatch.CallableValid(generator_drag_payload))return new Settings{["generator"]=entry.Duplicate(true)};
        using var arguments=new Godot.Collections.Array{entry};
        return EngineVariantDispatch.InvokeCallable(generator_drag_payload,arguments);
    }
    public override void _Notification(int what)
    {
        if(what!=NotificationPredelete)return;
        generator_drag_payload=default;
        foreach(var node in new Node[]{search,category,list,_index,_source_menu,_scan_status,_refresh_button,_cancel_button,_remove_button,_preview_button,_add_button,_folder_dialog,_preset_kind_filter,_tag_filter,_filters,_folders,_folders_toggle})
            if(GodotObject.IsInstanceValid(node)&&node.GetParent()==null)node.Free();
    }
}
