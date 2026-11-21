using Godot;

public partial class TransformationWorkspaceOperations
{
    public void unhandled_key_input(Control owner,InputEvent input)
    {
        if(!owner.IsVisibleInTree()||input is not InputEventKey key||!key.Pressed||key.Echo)return;var focus=owner.GetViewport().GuiGetFocusOwner();if(focus is LineEdit or TextEdit or SpinBox)return;var session=Session(owner);var canvas=Item<Control>(owner,"canvas");if(key.CtrlPressed){switch(key.Keycode){case Key.S:owner.Call(key.ShiftPressed?"save_as":"save");break;case Key.Z:finish_pending(owner);session.Call(key.ShiftPressed?"redo":"undo");break;case Key.Y:finish_pending(owner);session.Call("redo");break;case Key.C:session.Call("copy_components");break;case Key.V:finish_pending(owner);edit_mode(owner);session.Call("paste_components");break;case Key.D:finish_pending(owner);edit_mode(owner);session.Call("duplicate_components");break;default:return;}}else{switch(key.Keycode){case Key.Space:toggle_play(owner);break;case Key.I:finish_pending(owner);session.Call("insert_key");break;case Key.V:owner.Call("set_tool","move");break;case Key.W:case Key.B:owner.Call("set_tool","brush");break;case Key.E:owner.Call("set_tool","eraser");break;case Key.G:owner.Call("set_tool","fill");break;case Key.P:owner.Call("set_tool","pivot");break;case Key.F:canvas.Call("fit");break;case Key.Delete:case Key.Backspace:finish_pending(owner);session.Call("delete_components");break;default:return;}}owner.GetViewport().SetInputAsHandled();
    }
}
