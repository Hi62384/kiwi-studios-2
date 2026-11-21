using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ImageWorkspaceOperations
{
    private static Resource NewActorObject(string type,Settings values){var result=new ActorObjectData();result.Set("type_id",type);result.Set("values",values);return result;}
    public Resource default_text_settings()=>NewActorObject("text_settings",new Settings{["font"]="Arial",["font_size"]=72.0,["bold"]=false,["italic"]=false,["color"]=Colors.White,["letter_spacing"]=0,["line_spacing"]=0,["outline_size"]=0,["outline_color"]=Colors.Black,["shadow"]=false,["shadow_color"]=new Color(0,0,0,.65f),["shadow_offset"]=new Vector2(2,2)});
    public Resource default_noise_image()=>NewActorObject("noise_image",new Settings{["noise_type"]=(int)FastNoiseLite.NoiseTypeEnum.SimplexSmooth,["fractal_type"]=(int)FastNoiseLite.FractalTypeEnum.Fbm,["seed"]=0,["frequency"]=.015,["octaves"]=5,["lacunarity"]=2.0,["gain"]=.5,["contrast"]=1.0,["low_color"]=Colors.Black,["high_color"]=Colors.White,["seamless"]=true,["invert"]=false,["as_normal_map"]=false,["resolution"]=2});
    public Resource ensure_text_settings(Resource layer)
    {
        var properties=layer.Get("properties").AsGodotDictionary();var value=Get(properties,"text_settings");if(value.VariantType==Variant.Type.Object&&value.AsGodotObject() is Resource existing)return existing;var settings=default_text_settings();var values=settings.Get("values").AsGodotDictionary();foreach(var pair in new[]{("font","font"),("font_size","font_size"),("bold","bold"),("color","color"),("outline","outline_size"),("outline_color","outline_color")})values[pair.Item2]=Get(properties,pair.Item1,values[pair.Item2]);properties["text_settings"]=settings;return settings;
    }
    public void set_text_setting(Resource layer,StringName key,Variant value)=>ensure_text_settings(layer).Call("set_value",key,value);
    public void set_text_setting_component(Resource layer,StringName key,int component,double value){var settings=ensure_text_settings(layer);var vector=settings.Call("get_value",key,Vector2.Zero).AsVector2();vector[component]=(float)value;settings.Call("set_value",key,vector);}
    public void set_noise_object_value(Resource layer,StringName key,Variant value){var data=Get(layer.Get("properties").AsGodotDictionary(),"noise_object");if(data.VariantType!=Variant.Type.Object||data.AsGodotObject() is not Resource resource)return;resource.Call("set_value",key,value);refresh_noise_layer(layer);}
    public void refresh_noise_layer(Resource layer){var value=Get(layer.Get("properties").AsGodotDictionary(),"noise_object");layer.Set("texture",value.VariantType==Variant.Type.Object&&value.AsGodotObject()!=null?GD.Load<CSharpScript>("res://scripts/actors/core/ActorImageGenerator.cs").Call("texture_for_object",value):default(Variant));}
    public void save_polygon(Control owner,Vector2[] points)
    {
        var document=Document(owner);var layer=_documents.layer_for_id(document,Canvas(owner).Get("path_layer_id").AsString());if(layer==null)return;Action(owner,()=>{var local=new Vector2[points.Length];if(points.Length>0){var bounds=new Rect2(points[0],Vector2.Zero);foreach(var point in points)bounds=bounds.Expand(point);var parent=_documents.layer_for_id(document,layer.Get("parent_id").AsString());var inverse=parent!=null?_documents.world_transform(document,parent).AffineInverse():Transform2D.Identity;var dimensions=bounds.Size.Max(Vector2.One);layer.Set("dimensions",dimensions);layer.Set("rotation",0.0);layer.Set("position",inverse*(bounds.Position+dimensions*.5f)-dimensions*.5f);_layers.set_linear_basis(layer,inverse);for(int i=0;i<points.Length;i++)local[i]=points[i]-bounds.Position;}var properties=layer.Get("properties").AsGodotDictionary();properties["shape"]="custom";properties["points"]=local;properties["path_size"]=layer.Get("dimensions");});
    }
    public void draw_custom_shape(Control owner,Resource layer)
    {
        owner.Call("_set_tool","path");var canvas=Canvas(owner);canvas.Set("path_layer_id",layer.Get("id"));canvas.GrabFocus();canvas.Set("_polygon_index",-1);var properties=layer.Get("properties").AsGodotDictionary();var vertices=Get(properties,"points",Array.Empty<Vector2>()).AsVector2Array();var size=Get(properties,"path_size",layer.Get("dimensions")).AsVector2().Max(Vector2.One);var dimensions=layer.Get("dimensions").AsVector2();var transform=_documents.world_transform(Document(owner),layer);for(int i=0;i<vertices.Length;i++)vertices[i]=transform*(vertices[i]*dimensions/size);canvas.Set("_points",vertices);owner.Get("status").As<Label>().Text="Drag to place or move vertices · Right-click cancels / deletes · Enter applies · Esc cancels";
    }
    public void create_noise_image(Control owner,Resource layer){Action(owner,()=>{layer.Get("properties").AsGodotDictionary()["noise_image"]=default_noise_image().Get("values");update_image_noise(layer);});}
    public void set_noise_value(Resource layer,string key,Variant value){var properties=layer.Get("properties").AsGodotDictionary();var config=Get(properties,"noise_image",new Settings()).AsGodotDictionary();config[key]=value;properties["noise_image"]=config;update_image_noise(layer);}
    public void update_image_noise(Resource layer){var config=Get(layer.Get("properties").AsGodotDictionary(),"noise_image",new Settings()).AsGodotDictionary();var resource=NewActorObject("noise_image",config);var bitmap=GD.Load<CSharpScript>("res://scripts/actors/core/ActorImageGenerator.cs").Call("generate_noise",resource).As<Image>();if(bitmap!=null&&!bitmap.IsEmpty()){var texture=ImageTexture.CreateFromImage(bitmap);layer.Set("texture",texture);layer.Set("paint_base",texture);}}

}
