using Godot;
using Settings = Godot.Collections.Dictionary;
public partial class AudioProviderContractOperations : RefCounted
{
    public Settings descriptor() => new() { ["id"] = "", ["label"] = "Unconfigured provider", ["tasks"] = new Godot.Collections.Array(), ["models"] = new Godot.Collections.Array(), ["supports_cancel"] = false, ["credential_required"] = true };
    public Settings estimate() => new() { ["known"] = false, ["amount"] = 0.0, ["currency"] = "", ["unit"] = "request" };
    public Settings generate() => new() { ["success"] = false, ["error"] = "This provider has no generation adapter." };
}
