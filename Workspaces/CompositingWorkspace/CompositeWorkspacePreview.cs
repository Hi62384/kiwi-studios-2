using Godot;
using System;

public partial class CompositeWorkspacePreview : RefCounted
{
    public Resource prepare(Resource document, int maximum_axis)
    {
        var preview = (Resource)document.Duplicate(true); Vector2I size = document.Get("canvas_size").AsVector2I();
        float factor = Math.Min(1f, maximum_axis / (float)Math.Max(size.X, size.Y));
        if (factor >= 1) return preview;
        preview.Set("canvas_size", new Vector2I(Math.Max(1, Mathf.RoundToInt(size.X * factor)), Math.Max(1, Mathf.RoundToInt(size.Y * factor))));
        foreach (Variant value in preview.Get("layers").AsGodotArray())
        {
            var layer = value.As<Resource>(); if (layer == null) continue;
            layer.Set("position", layer.Get("position").AsVector2() * factor); layer.Set("scale", layer.Get("scale").AsVector2() * factor);
        }
        foreach (Variant value in preview.Get("animation").AsGodotArray())
        {
            var track = value.AsGodotDictionary();
            if (!track.TryGetValue("property", out var property) || property.AsString() is not ("position" or "scale") || !track.TryGetValue("keys", out var keys)) continue;
            foreach (Variant keyValue in keys.AsGodotArray())
            {
                var key = keyValue.AsGodotDictionary();
                if (key.TryGetValue("value", out var position) && position.VariantType == Variant.Type.Vector2) key["value"] = position.AsVector2() * factor;
            }
        }
        return preview;
    }

    public Image display_preview(Image source)
    {
        using var image = (Image)source.Duplicate(); image.Convert(Image.Format.Rgbaf);
        byte[] input = image.GetData(); float[] values = new float[input.Length / sizeof(float)]; Buffer.BlockCopy(input, 0, values, 0, input.Length);
        byte[] output = new byte[values.Length];
        for (int i = 0; i < values.Length; i += 4)
        {
            var color = new Color(values[i], values[i + 1], values[i + 2], values[i + 3]).LinearToSrgb();
            color.R = Math.Clamp(color.R, 0, 1); color.G = Math.Clamp(color.G, 0, 1); color.B = Math.Clamp(color.B, 0, 1); color.A = Math.Clamp(color.A, 0, 1);
            output[i] = (byte)color.R8; output[i + 1] = (byte)color.G8; output[i + 2] = (byte)color.B8; output[i + 3] = (byte)color.A8;
        }
        return Image.CreateFromData(image.GetWidth(), image.GetHeight(), false, Image.Format.Rgba8, output);
    }
}
