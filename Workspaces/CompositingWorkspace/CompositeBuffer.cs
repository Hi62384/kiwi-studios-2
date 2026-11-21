using Godot;

public partial class CompositeBuffer : RefCounted
{
    [Export] public Image? image { get; set; }
    [Export] public float pixel_aspect_ratio { get; set; } = 1;
    [Export] public StringName channel_layout { get; set; } = "RGBA";
    [Export] public StringName precision { get; set; } = "float32";
    [Export] public StringName color_space { get; set; } = "linear_srgb";
    [Export] public StringName alpha_association { get; set; } = "straight";
    [Export] public StringName coordinate_domain { get; set; } = "canvas";
    [Export] public double frame_time { get; set; }
    [Export] public string source_identity { get; set; } = "";
    [Export] public StringName depth_convention { get; set; } = "";
    [Export] public StringName depth_units { get; set; } = "";
    [Export] public string camera_reference { get; set; } = "";
    [Export] public Image? validity { get; set; }

    public bool is_valid() => image != null && !image.IsEmpty() && image.GetWidth() > 0 && image.GetHeight() > 0
        && float.IsFinite(pixel_aspect_ratio) && pixel_aspect_ratio > 0;

    public CompositeBuffer duplicate_buffer() => new()
    {
        image = image == null ? null : (Image)image.Duplicate(),
        pixel_aspect_ratio = pixel_aspect_ratio, channel_layout = channel_layout,
        precision = precision, color_space = color_space, alpha_association = alpha_association,
        coordinate_domain = coordinate_domain, frame_time = frame_time, source_identity = source_identity,
        depth_convention = depth_convention, depth_units = depth_units, camera_reference = camera_reference,
        validity = validity == null ? null : (Image)validity.Duplicate()
    };
}
