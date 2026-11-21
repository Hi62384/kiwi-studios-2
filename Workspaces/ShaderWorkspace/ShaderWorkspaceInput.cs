using Godot;
using System;

public partial class ShaderWorkspaceOperations
{
    public void viewport_input(Control owner,InputEvent input)
    {
        var display=Item<TextureRect>(owner,"viewport_display");if(input is InputEventMouseButton pressed&&pressed.Pressed){display.GrabFocus();Code(owner).ReleaseFocus();}if(owner.Get("shader_kind").AsString()=="canvas_item"){display.AcceptEvent();return;}
        if(input is InputEventMouseButton right&&right.ButtonIndex==MouseButton.Right){owner.Set("_looking",right.Pressed);owner.Set("_last_mouse",right.Position);display.AcceptEvent();}
        else if(input is InputEventMouseMotion motion&&owner.Get("_looking").AsBool()){var delta=motion.Position-owner.Get("_last_mouse").AsVector2();owner.Set("_last_mouse",motion.Position);var rig=Item<Node3D>(owner,"camera_rig");var rotation=rig.Rotation;rotation.Y-=(float)(delta.X*.006);rig.Rotation=rotation;var camera=Item<Camera3D>(owner,"camera");rotation=camera.Rotation;rotation.X=(float)Math.Clamp(rotation.X-delta.Y*.006,-1.5,1.5);camera.Rotation=rotation;display.AcceptEvent();}
        else if(input is InputEventMouseButton wheel&&wheel.Pressed&&wheel.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown){owner.Set("camera_speed",Math.Clamp(owner.Get("camera_speed").AsDouble()*(wheel.ButtonIndex==MouseButton.WheelUp?1.2:1/1.2),.1,100));Item<Label>(owner,"status").Text=viewport_help(owner);display.AcceptEvent();}
        else if(input is InputEventKey key&&display.HasFocus()&&key.Keycode is Key.W or Key.A or Key.S or Key.D or Key.Q or Key.E)display.AcceptEvent();
    }
    public void unhandled_key_input(Control owner,InputEvent input)
    {if(!owner.Visible||input is not InputEventKey key||!key.Pressed||key.Echo)return;if(key.CtrlPressed&&key.Keycode==Key.S){owner.Call(key.ShiftPressed?"save_as":"save");owner.GetViewport().SetInputAsHandled();}}
    public void process(Control owner,double delta)
    {
        if(!owner.Visible||!owner.Get("_looking").AsBool()||owner.Get("shader_kind").AsString()=="canvas_item")return;var rig=Item<Node3D>(owner,"camera_rig");var basis=rig.Transform.Basis;var velocity=Vector3.Zero;if(Input.IsKeyPressed(Key.W))velocity-=basis.Z;if(Input.IsKeyPressed(Key.S))velocity+=basis.Z;if(Input.IsKeyPressed(Key.A))velocity-=basis.X;if(Input.IsKeyPressed(Key.D))velocity+=basis.X;if(Input.IsKeyPressed(Key.Q))velocity-=Vector3.Up;if(Input.IsKeyPressed(Key.E))velocity+=Vector3.Up;if(!velocity.IsZeroApprox())rig.Position+=velocity.Normalized()*(float)delta*(float)owner.Get("camera_speed").AsDouble();
    }
}
