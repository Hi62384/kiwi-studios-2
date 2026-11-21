using Godot;
using Settings=Godot.Collections.Dictionary;

public partial class ShaderWorkspaceOperations
{
    private static Range Number(double value,double step=.01) {var result=new DragNumber();result.AllowGreater=true;result.AllowLesser=true;result.Step=step;result.Value=value;result.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;return result;}
    public void rebuild_parameters(Control owner)
    {
        var list=Item<VBoxContainer>(owner,"parameters_list");if(!GodotObject.IsInstanceValid(list))return;foreach(Node child in list.GetChildren()){list.RemoveChild(child);child.QueueFree();}
        foreach(var raw in Item<Shader>(owner,"preview_shader").GetShaderUniformList()){var info=raw.AsGodotDictionary();string name=info.TryGetValue("name",out var key)?key.AsString():"";int type=info.TryGetValue("type",out var kind)?kind.AsInt32():0;if(name.Length>0&&type!=0)add_parameter_row(owner,new StringName(name),type,info.TryGetValue("hint_string",out var hint)?hint.AsString():"");}
        // Incomplete shader edits must never discard stored preview or linked values.
        if(list.GetChildCount()==0)Caption(list,"No editable uniforms in this shader.","718b9e");
    }
    public void add_parameter_row(Control owner,StringName name,int valueType,string hint)
    {
        var field=Column(Item<VBoxContainer>(owner,"parameters_list"),3);field.Name="Uniform_"+name;var heading=Row(field);var label=Attach(heading,new Label {Text=name.ToString().Replace('_',' ').Capitalize(),TooltipText=name.ToString(),SizeFlagsHorizontal=Control.SizeFlags.ExpandFill,ClipText=true});var defaults=shader_uniform_default(owner,name,valueType);var values=owner.Get("parameter_values").AsGodotDictionary();var value=values.TryGetValue(name,out var stored)?stored:defaults;var reset=Attach(heading,new Button {Name=name+"_reset",Text="↺",TooltipText="Reset to shader default: "+defaults,Visible=values.ContainsKey(name)&&!Equal(value,defaults)});reset.Pressed+=()=>reset_preview_parameter(owner,name);
        switch((Variant.Type)valueType)
        {
            case Variant.Type.Bool: var check=Attach(field,new CheckButton {ButtonPressed=value.AsBool()});check.Toggled+=enabled=>set_preview_parameter(owner,name,enabled,"edit",default);break;
            case Variant.Type.Int: case Variant.Type.Float: add_parameter_number(owner,field,name,value.AsDouble(),valueType,hint);break;
            case Variant.Type.Color:
                var color=new LiveColorPickerButton();color.CustomMinimumSize=new Vector2(0,32);color.SizeFlagsHorizontal=Control.SizeFlags.ExpandFill;color.Color=value.AsColor();field.AddChild(color);style_parameter_color(color,value.AsColor());Settings origin=new();color.Connect("interaction_started",Callable.From(()=>origin=current_parameter_values(owner)));color.Connect("preview_changed",Callable.From<Color>(next=>{style_parameter_color(color,next);set_preview_parameter(owner,name,next,"preview",default);}));color.Connect("drag_committed",Callable.From<Color,Color>((before,next)=>{style_parameter_color(color,next);set_preview_parameter(owner,name,next,"commit",origin);}));break;
            case Variant.Type.Vector2: case Variant.Type.Vector3: case Variant.Type.Vector4:
                int count=valueType==(int)Variant.Type.Vector2?2:valueType==(int)Variant.Type.Vector3?3:4;for(int index=0;index<count;index++){int component=index;var row=Row(field);Attach(row,new Label {Text=new[]{"X","Y","Z","W"}[index],CustomMinimumSize=new Vector2(18,0),Modulate=new Color(new[]{"ee9e9e","9ed8a8","91b9ed","d7a5ed"}[index])});double scalar=count==2?value.AsVector2()[index]:count==3?value.AsVector3()[index]:value.AsVector4()[index];var number=Attach(row,Number(scalar));Settings vectorOrigin=new();number.Connect("interaction_started",Callable.From(()=>vectorOrigin=current_parameter_values(owner)));number.Connect("preview_changed",Callable.From<double>(next=>vector_parameter_changed(owner,next,name,component,valueType,"preview",default)));number.Connect("drag_committed",Callable.From<double>(next=>vector_parameter_changed(owner,next,name,component,valueType,"commit",vectorOrigin)));number.ValueChanged+=next=>vector_parameter_changed(owner,next,name,component,valueType,"edit",default);}break;
            case Variant.Type.Object: owner.Call("_add_texture_parameter",field,name,value);break;
            default: Caption(field,"Unsupported preview type","718b9e");break;
        }
    }
    public void add_parameter_number(Control owner,Control parent,StringName name,double value,int valueType,string hint)
    {
        var row=Row(parent);var number=Number(value,valueType==(int)Variant.Type.Int?1:.01);number.Name=name+"_value";Settings origin=new();number.Connect("interaction_started",Callable.From(()=>origin=current_parameter_values(owner)));Variant Normalize(double next)=>valueType==(int)Variant.Type.Int?Variant.From((long)next):Variant.From(next);
        var bounds=hint_range(hint);if(bounds.Length>0){var slider=Attach(row,new HSlider {MinValue=bounds[0],MaxValue=bounds[1],Step=number.Step,Value=value,SizeFlagsHorizontal=Control.SizeFlags.ExpandFill});number.CustomMinimumSize=new Vector2(82,0);number.SizeFlagsHorizontal=Control.SizeFlags.ShrinkEnd;bool active=false;Settings sliderOrigin=new();slider.DragStarted+=()=>{active=true;sliderOrigin=current_parameter_values(owner);};slider.ValueChanged+=next=>{number.SetValueNoSignal(next);set_preview_parameter(owner,name,Normalize(next),active?"preview":"edit",default);};slider.DragEnded+=changed=>{active=false;if(changed)set_preview_parameter(owner,name,Normalize(slider.Value),"commit",sliderOrigin);};number.Connect("preview_changed",Callable.From<double>(next=>slider.SetValueNoSignal(next)));number.ValueChanged+=next=>slider.SetValueNoSignal(next);}
        number.Connect("preview_changed",Callable.From<double>(next=>set_preview_parameter(owner,name,Normalize(next),"preview",default)));number.Connect("drag_committed",Callable.From<double>(next=>set_preview_parameter(owner,name,Normalize(next),"commit",origin)));number.ValueChanged+=next=>set_preview_parameter(owner,name,Normalize(next),"edit",default);row.AddChild(number);
    }
}
