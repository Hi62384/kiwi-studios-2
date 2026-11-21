using Godot;
using System;
using GArray=Godot.Collections.Array;
public partial class ImageWorkspaceOperations
{
    private readonly ImageMaterialBrowserOperations _browser=new();private readonly ImageMaterialResourceOperations _materials=new();private readonly ImageProceduralTextureOperations _recipes=new();
    public void refresh_inspector(Control owner)
    {
        bool effects=owner.Get("_effects_open").AsBool();Field(owner,"_effects_dock").Visible=effects;var scroll=owner.Get("_inspector_scroll").As<ScrollContainer>();scroll.Visible=!effects;if(effects){owner.Call("_refresh_effects_dock");return;}int oldScroll=scroll.ScrollVertical;var inspector=Field(owner,"inspector");clear(inspector);owner.Set("_text_input",default(Variant));var layer=main_layer(owner);if(layer==null)return;var properties=layer.Get("properties").AsGodotDictionary();var canvas=Canvas(owner);var repair=canvas.Get("repair_tool").As<RefCounted>();var material=ResourceValue(Get(properties,"texture_material"));
        if(ScriptIs(material,"res://Workspaces/ImageWorkspace/texture_material.gd"))
        {
            if(canvas.Get("painting_mode").AsString()=="material"&&owner.GetNodeOrNull("MaterialBrowser")==null){var copy=_materials.copy_material(material!);copy.Set("coverage",default(Variant));copy.Set("source",default(Variant));repair.Set("material",copy);}button(owner,inspector,"Edit painted material",Callable.From(()=>{repair.Set("material",_materials.copy_material(properties["texture_material"].As<Resource>()));canvas.Set("painting_mode","material");owner.Call("_set_tool","brush");_browser.open(owner);}),"Change the material without repainting its coverage","noise");button(owner,inspector,"Bake material",new Callable(owner,"rasterize_selected"),"Convert this material layer into ordinary editable pixels","check");
        }
        var recipe=ResourceValue(Get(properties,"texture_recipe"));if(ScriptIs(recipe,"res://Workspaces/ImageWorkspace/image_texture_recipe.gd"))button(owner,inspector,"Edit procedural texture",Callable.From(()=>{repair.Set("recipe",_recipes.copy_recipe(properties["texture_recipe"].As<Resource>()));repair.Set("mode","procedural");owner.Call("_set_tool","repair");_repair.generate(repair,"");}),"Reopen the saved texture recipe","noise");string kind=layer.Get("kind").AsString();
        if(kind=="image")owner.Call("_image_source_property",layer);
        else if(kind=="text")
        {
            var label=new Label{Text="TEXT"};label.AddThemeColorOverride("font_color",new Color("70cdb8"));inspector.AddChild(label);var input=new TextEdit{Text=properties["text"].AsString(),CustomMinimumSize=new Vector2(0,110),WrapMode=TextEdit.LineWrappingMode.Boundary};owner.Set("_text_input",input);inspector.AddChild(input);input.FocusEntered+=()=>begin(owner);input.TextChanged+=()=>{begin(owner);properties["text"]=input.Text;preview(owner);};input.FocusExited+=()=>commit(owner);owner.Call("_text_settings_property",layer);var align=new OptionButton();foreach(string caption in new[]{"Left","Center","Right"})align.AddItem(caption);align.Select(properties["alignment"].AsInt32());inspector.AddChild(align);align.ItemSelected+=value=>Action(owner,()=>properties["alignment"]=value);
        }
        else if(kind=="shape")
        {
            var shape=new OptionButton();foreach(string caption in new[]{"Rounded rectangle","Ellipse","Triangle","Custom polygon"})shape.AddItem(caption);var names=new[]{"rectangle","ellipse","triangle","custom"};shape.Select(Math.Max(0,Array.IndexOf(names,properties["shape"].AsString())));inspector.AddChild(shape);shape.ItemSelected+=value=>{Action(owner,()=>properties["shape"]=names[value]);if(value==3)owner.Call("_draw_custom_shape",layer);};if(properties["shape"].AsString()=="custom")button(owner,inspector,"Draw custom shape…",Callable.From(()=>owner.Call("_draw_custom_shape",layer)),"Click vertices; Enter closes the shape","");check(owner,inspector,"Filled",Get(properties,"filled",true).AsBool(),Callable.From<bool>(value=>properties["filled"]=value));number(owner,inspector,"Corners",properties["radius"].AsDouble(),Callable.From<double>(value=>properties["radius"]=value),0,500,.1);color(owner,inspector,"Fill",properties["color"].AsColor(),Callable.From<Color>(value=>properties["color"]=value));number(owner,inspector,"Stroke",properties["stroke"].AsDouble(),Callable.From<double>(value=>properties["stroke"]=value),0,100,.1);color(owner,inspector,"Stroke color",properties["stroke_color"].AsColor(),Callable.From<Color>(value=>properties["stroke_color"]=value));
        }
        else if(kind=="path"){color(owner,inspector,"Fill",properties["color"].AsColor(),Callable.From<Color>(value=>properties["color"]=value));number(owner,inspector,"Stroke",properties["stroke"].AsDouble(),Callable.From<double>(value=>properties["stroke"]=value),0,100,.1);color(owner,inspector,"Stroke color",properties["stroke_color"].AsColor(),Callable.From<Color>(value=>properties["stroke_color"]=value));}
        else if(kind=="noise")owner.Call("_noise_layer_property",layer);
        else if(kind=="gradient")
        {
            color(owner,inspector,"Start color",properties["color"].AsColor(),Callable.From<Color>(value=>properties["color"]=value));color(owner,inspector,"End color",properties["color_end"].AsColor(),Callable.From<Color>(value=>properties["color_end"]=value));number(owner,inspector,"Angle",properties["gradient_angle"].AsDouble(),Callable.From<double>(value=>properties["gradient_angle"]=value),-360,360,.1);check(owner,inspector,"Radial",properties["gradient_radial"].AsBool(),Callable.From<bool>(value=>properties["gradient_radial"]=value));var choices=new GArray();foreach(var entry in new[]{("Mint / ocean","69dfbe","3261de"),("Sunset","f9ab62","cc477c"),("Night","192346","824ed0")})choices.Add(new GArray{entry.Item1,Callable.From(()=>Action(owner,()=>{properties["color"]=new Color(entry.Item2);properties["color_end"]=new Color(entry.Item3);}))});menu(owner,inspector,"Gradient presets",choices);
        }
        scroll.SetDeferred("scroll_vertical",oldScroll);
    }
}
