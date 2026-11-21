using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ImageLayerDrawingOperations:RefCounted
{
    private readonly ImageLayerOperations _layers=new();private readonly ActorTextSettingsOperations _text=new();
    private static Variant Get(Settings properties,string key,Variant fallback=default)=>properties.TryGetValue(key,out var value)?value:fallback;
    public void draw(Node2D owner)
    {
        var layer=owner.Get("layer").As<Resource>();if(layer==null)return;var p=layer.Get("properties").AsGodotDictionary();var dimensions=layer.Get("dimensions").AsVector2();var rect=new Rect2(Vector2.Zero,dimensions);var color=Get(p,"color",Colors.White).AsColor();string kind=layer.Get("kind").AsString();
        if(kind is "image" or "paint" or "basic"){var texture=layer.Get("texture").As<Texture2D>();if(texture!=null)owner.DrawTextureRect(texture,rect,false);return;}
        if(kind=="shape")
        {
            float stroke=Get(p,"stroke",0.0).AsSingle();var strokeColor=Get(p,"stroke_color",Colors.White).AsColor();bool filled=Get(p,"filled",true).AsBool();string shape=Get(p,"shape","rectangle").AsString();
            if(shape is "triangle" or "custom")
            {
                var points=shape=="triangle"?new[]{new Vector2(dimensions.X*.5f,0),dimensions,new Vector2(0,dimensions.Y)}:Get(p,"points",Array.Empty<Vector2>()).AsVector2Array();if(shape=="custom"){var ratio=dimensions/Get(p,"path_size",dimensions).AsVector2().Max(Vector2.One);for(int i=0;i<points.Length;i++)points[i]*=ratio;points=_layers.rounded_polygon(points,Get(p,"radius",0).AsDouble());}if(filled&&points.Length>=3){var triangles=Geometry2D.TriangulatePolygon(points);for(int i=0;i<triangles.Length;i+=3)owner.DrawColoredPolygon(new[]{points[triangles[i]],points[triangles[i+1]],points[triangles[i+2]]},color);}if(stroke>0&&points.Length>1)Outline(owner,points,strokeColor,stroke);return;
            }
            if(shape=="ellipse"){var points=new Vector2[96];for(int i=0;i<96;i++){float angle=Mathf.Tau*i/96;points[i]=dimensions*.5f+new Vector2(Mathf.Cos(angle),Mathf.Sin(angle))*dimensions*.5f;}if(filled)owner.DrawColoredPolygon(points,color);if(stroke>0)Outline(owner,points,strokeColor,stroke);}
            else{using var box=new StyleBoxFlat{BgColor=color,DrawCenter=filled,BorderColor=strokeColor};box.SetCornerRadiusAll(Get(p,"radius",24).AsInt32());box.SetBorderWidthAll((int)stroke);owner.DrawStyleBox(box,rect);}return;
        }
        if(kind=="text")
        {
            var settings=_text.values(Get(p,"text_settings"));if(settings.Count==0)settings=p;string key=Get(settings,"font","").AsString()+BoolText(Get(settings,"bold",false).AsBool())+BoolText(Get(settings,"italic",false).AsBool())+Get(settings,"letter_spacing",0).AsInt32()+Get(settings,"line_spacing",0).AsInt32();var font=owner.Get("font").As<Font>();
            if(font==null||owner.Get("font_key").AsString()!=key){var baseFont=_text.font(settings);int letters=Get(settings,"letter_spacing",0).AsInt32(),lines=Get(settings,"line_spacing",0).AsInt32();font=letters!=0||lines!=0?new FontVariation{BaseFont=baseFont,SpacingGlyph=letters,SpacingSpace=letters,SpacingTop=lines/2,SpacingBottom=lines/2}:baseFont;owner.Set("font",font);owner.Set("font_key",key);}
            float detail=owner.Get("text_detail").AsSingle(),scale=Get(p,"text_scale",1.0).AsSingle();int size=Math.Max(1,Mathf.RoundToInt(Get(settings,"font_size",72).AsDouble()*scale*detail));owner.DrawSetTransform(Vector2.Zero,0,Vector2.One/detail);var alignment=(HorizontalAlignment)Get(p,"alignment",0).AsInt32();var position=new Vector2(0,font.GetAscent(size));string text=Get(p,"text","Text").AsString();
            if(Get(settings,"outline_size",0).AsInt32()>0)owner.DrawMultilineStringOutline(font,position,text,alignment,dimensions.X*detail,size,-1,Mathf.RoundToInt(Get(settings,"outline_size",0).AsDouble()*detail),Get(settings,"outline_color",Colors.Black).AsColor());
            if(Get(settings,"shadow",false).AsBool())owner.DrawMultilineString(font,position+Get(settings,"shadow_offset",new Vector2(2,2)).AsVector2()*scale*detail,text,alignment,dimensions.X*detail,size,-1,Get(settings,"shadow_color",new Color(0,0,0,.65f)).AsColor());owner.DrawMultilineString(font,position,text,alignment,dimensions.X*detail,size,-1,Get(settings,"color",color).AsColor());owner.DrawSetTransform(Vector2.Zero);return;
        }
        if(kind=="gradient")
        {
            var gradient=owner.Get("gradient").As<GradientTexture2D>();if(gradient==null){gradient=new GradientTexture2D();owner.Set("gradient",gradient);}gradient.Gradient=new Gradient{Colors=new[]{color,Get(p,"color_end",Colors.White).AsColor()}};gradient.Fill=Get(p,"gradient_radial",false).AsBool()?GradientTexture2D.FillEnum.Radial:GradientTexture2D.FillEnum.Linear;var direction=Vector2.FromAngle(Mathf.DegToRad(Get(p,"gradient_angle",0).AsSingle()))*.5f;gradient.FillFrom=Vector2.One*.5f-direction;gradient.FillTo=Vector2.One*.5f+direction;owner.DrawTextureRect(gradient,rect,false);return;
        }
        if(kind=="noise")
        {
            var texture=layer.Get("texture").As<Texture2D>();if(texture!=null){owner.DrawTextureRect(texture,rect,false);return;}var noise=owner.Get("noise").As<NoiseTexture2D>();if(noise==null){noise=new NoiseTexture2D{Width=512,Height=512};owner.Set("noise",noise);noise.Changed+=owner.QueueRedraw;noise.Changed+=()=>owner.EmitSignal("source_changed");}long key=GD.Hash(p);if(owner.Get("noise_key").AsInt64()!=key){owner.Set("noise_key",key);noise.Noise=new FastNoiseLite{Seed=Get(p,"noise_seed",0).AsInt32(),Frequency=Get(p,"noise_frequency",.02).AsSingle(),FractalOctaves=Get(p,"noise_octaves",5).AsInt32()};noise.ColorRamp=new Gradient{Colors=new[]{color,Get(p,"color_end",Colors.White).AsColor()}};noise.AsNormalMap=Get(p,"noise_normal",false).AsBool();}owner.DrawTextureRect(noise,rect,false);return;
        }
        if(kind=="path"){var points=Get(p,"points",Array.Empty<Vector2>()).AsVector2Array();var source=Get(p,"path_size",dimensions).AsVector2();for(int i=0;i<points.Length;i++)points[i]*=dimensions/source.Max(Vector2.One);if(points.Length>=3)owner.DrawColoredPolygon(points,color);float width=Get(p,"stroke",0).AsSingle();if(points.Length>=2&&width>0)Outline(owner,points,Get(p,"stroke_color",Colors.White).AsColor(),width);}
    }
    private static string BoolText(bool value)=>value?"true":"false";
    private static void Outline(Node2D owner,Vector2[] points,Color color,float width){var closed=new Vector2[points.Length+1];Array.Copy(points,closed,points.Length);closed[^1]=points[0];owner.DrawPolyline(closed,color,width,true);}
}
