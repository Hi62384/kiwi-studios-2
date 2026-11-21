using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageWarpPickerOperations:RefCounted
{
    public Texture2D icon(string kind,Settings paths,Settings icons)
    {
        if(icons.TryGetValue(kind,out var existing))return existing.As<Texture2D>();using var bitmap=new Image();string path=paths.TryGetValue(kind,out var found)?found.AsString():paths["brush"].AsString();bitmap.LoadSvgFromString("<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'><g fill='none' stroke='#95e4d0' stroke-width='1.8' stroke-linecap='round' stroke-linejoin='round'>"+path+"</g></svg>");var texture=ImageTexture.CreateFromImage(bitmap);icons[kind]=texture;return texture;
    }
    private static StyleBox Box(Control workspace,string fill,string border,int radius,int padding)=>workspace.Call("_box",new Color(fill),new Color(border),radius,padding).As<StyleBox>();
    public MenuButton build(Control workspace,Node parent,string nodeName,string title,GArray ids,GArray captions,string current,Variant changed,Settings paths,Settings icons)
    {
        int selected=0;for(int index=0;index<ids.Count;index++)if(ids[index].AsString()==current){selected=index;break;}var button=new MenuButton{Name=nodeName,Text=captions[selected].AsString()+"  ▾",Icon=icon(current,paths,icons),CustomMinimumSize=new Vector2(0,28)};button.AddThemeConstantOverride("icon_max_width",19);parent.AddChild(button);button.AddThemeFontSizeOverride("font_size",12);button.AddThemeStyleboxOverride("normal",Box(workspace,"20343d","446570",6,5));button.AddThemeStyleboxOverride("hover",Box(workspace,"28554f","80e3c7",6,5));button.AddThemeStyleboxOverride("pressed",Box(workspace,"23594f","80e3c7",6,5));var menu=button.GetPopup();menu.AddSeparator(title);menu.AddThemeStyleboxOverride("panel",Box(workspace,"152631","4a756f",10,10));menu.AddThemeStyleboxOverride("hover",workspace.Call("_box",new Color("28594f"),Colors.Transparent,5,5).As<StyleBox>());menu.AddThemeColorOverride("font_color",new Color("dfefed"));menu.AddThemeColorOverride("font_hover_color",Colors.White);menu.AddThemeColorOverride("font_separator_color",new Color("8ba9af"));menu.AddThemeFontSizeOverride("font_size",14);menu.AddThemeConstantOverride("v_separation",12);menu.AddThemeConstantOverride("h_separation",12);menu.AddThemeConstantOverride("icon_max_width",22);for(int index=0;index<ids.Count;index++){string id=ids[index].AsString();menu.AddIconItem(icon(id,paths,icons),captions[index].AsString()+(id==current?"    ✓":""),index);}var bridge=GD.Load<GDScript>("res://Workspaces/ImageWorkspace/image_warp_picker.gd");menu.IdPressed+=index=>bridge.Call("_choose",changed,(int)index);return button;
    }
}
