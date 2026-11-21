using Godot;
using System;
public partial class ImageOperationPreviewOperations:RefCounted
{
    public void ready(Control owner){owner.ClipContents=true;owner.Material=new CanvasItemMaterial{BlendMode=CanvasItemMaterial.BlendModeEnum.PremultAlpha};owner.MouseDefaultCursorShape=Control.CursorShape.Drag;owner.Resized+=owner.QueueRedraw;}
    public void draw(Control owner)
    {
        owner.DrawRect(new Rect2(Vector2.Zero,owner.Size),new Color("0d151e"));var texture=owner.Get("texture").As<Texture2D>();if(texture==null)return;var dimensions=(Vector2)texture.GetSize();float fit=Math.Min((owner.Size.X-24)/dimensions.X,(owner.Size.Y-24)/dimensions.Y);var extent=dimensions*fit*(float)owner.Get("zoom").AsDouble();var rect=new Rect2((owner.Size-extent)*.5f+owner.Get("pan").AsVector2(),extent);for(int y=0;y<(int)owner.Size.Y;y+=20)for(int x=0;x<(int)owner.Size.X;x+=20)if((x/20+y/20)%2==0)owner.DrawRect(new Rect2(x,y,20,20),new Color("16232f"));owner.DrawTextureRect(texture,rect,false);
    }
    public void gui_input(Control owner,InputEvent input)
    {
        if(input is InputEventMouseButton button){if(button.ButtonIndex is MouseButton.Left or MouseButton.Middle){owner.Set("dragging",button.Pressed);owner.AcceptEvent();}if(button.Pressed&&button.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown){double previous=owner.Get("zoom").AsDouble(),zoom=Math.Clamp(previous*(button.ButtonIndex==MouseButton.WheelUp?1.2:1/1.2),.1,32);var pan=button.Position-owner.Size*.5f-(button.Position-owner.Size*.5f-owner.Get("pan").AsVector2())*(float)(zoom/previous);owner.Set("zoom",zoom);owner.Set("pan",pan);owner.QueueRedraw();owner.AcceptEvent();}if(button.DoubleClick){owner.Set("zoom",1.0);owner.Set("pan",Vector2.Zero);owner.QueueRedraw();}}else if(input is InputEventMouseMotion motion&&owner.Get("dragging").AsBool()){owner.Set("pan",owner.Get("pan").AsVector2()+motion.Relative);owner.QueueRedraw();owner.AcceptEvent();}
    }
}
