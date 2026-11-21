using System.Collections.Generic;
public partial class TimelineEditorOperations
{
    private static readonly Dictionary<string,string> IconPaths=new()
    {
        ["undo"]="<path d=\"M8 4 3 9l5 5M3 9h9a6 6 0 0 1 0 12\"/>",
        ["redo"]="<path d=\"m16 4 5 5-5 5m5-5h-9a6 6 0 0 0 0 12\"/>",
        ["magnet"]="<path d=\"M5 3v10a7 7 0 0 0 14 0V3h-5v10a2 2 0 0 1-4 0V3Z\"/><path d=\"M5 7h5m4 0h5\"/>",
        ["split"]="<circle cx=\"6\" cy=\"6\" r=\"3\"/><circle cx=\"6\" cy=\"18\" r=\"3\"/><path d=\"m8 8 12 12M8 16 20 4\"/>",
        ["mic"]="<rect x=\"9\" y=\"2\" width=\"6\" height=\"12\" rx=\"3\"/><path d=\"M5 10v2a7 7 0 0 0 14 0v-2M12 19v3m-4 0h8\"/>",
        ["screen"]="<rect x=\"2\" y=\"3\" width=\"20\" height=\"14\" rx=\"2\"/><path d=\"M8 22h8m-4-5v5\"/><circle cx=\"17\" cy=\"7\" r=\"2\"/>",
        ["stop"]="<rect x=\"5\" y=\"5\" width=\"14\" height=\"14\" rx=\"2\"/>",
        ["keys"]="<path d=\"m12 3 8 9-8 9-8-9Z\"/>",
        ["grid"]="<path d=\"M3 7h18M3 17h18M7 3v18M17 3v18\"/>",
        ["add"]="<path d=\"M12 4v16M4 12h16\"/>",
    };
}
