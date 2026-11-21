using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class CuteCondition : Resource
{
    public enum ConditionType { EQUAL, GREATER_THAN, LESS_THAN, EQUAL_GREATER_THAN, EQUAL_LESS_THAN, NOT_EQUAL }
    [Export] public ConditionType condition { get; set; } = ConditionType.EQUAL;
    [Export] public Godot.Collections.Array compare_value { get; set; } = new();
    private readonly SharedControlOperations _operations = new();
    public bool compare(Variant val) => _operations.compare(this, val);
    public static Settings condition_types() => new() { ["EQUAL"] = 0, ["GREATER_THAN"] = 1, ["LESS_THAN"] = 2, ["EQUAL_GREATER_THAN"] = 3, ["EQUAL_LESS_THAN"] = 4, ["NOT_EQUAL"] = 5 };
}
