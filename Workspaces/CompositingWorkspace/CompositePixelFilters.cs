using Godot;
using System;
using Vector4 = System.Numerics.Vector4;

public partial class CompositePixelFilters : RefCounted
{
    public Image normalize(Image source, bool sourceIsSrgb, bool premultiplied)
    {
        float[] pixels = ReadPixels(source, out var image, out var bytes);
        for (int i = 0; i < pixels.Length; i += 4)
        {
            var color = new Color(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]);
            if (sourceIsSrgb) color = color.SrgbToLinear();
            if (premultiplied)
            {
                float inverseAlpha = color.A > .000001f ? 1f / color.A : 0;
                color.R *= inverseAlpha; color.G *= inverseAlpha; color.B *= inverseAlpha;
            }
            pixels[i] = color.R; pixels[i + 1] = color.G; pixels[i + 2] = color.B;
        }
        return WritePixels(image, bytes, pixels);
    }

    public Image transform(Image source, Vector2I canvas, Vector2 position, float rotation, Vector2 scale, Vector2 anchor, bool sourceIsSrgb)
    {
        float[] pixels = ReadPixels(source, out var image, out _);
        int width = image.GetWidth(), height = image.GetHeight();
        var transform = new Transform2D(rotation, position);
        transform.X *= scale.X; transform.Y *= scale.Y;
        var inverse = transform.AffineInverse(); var pivot = new Vector2(width, height) * anchor;
        float[] output = new float[checked(canvas.X * canvas.Y * 4)];
        for (int y = 0; y < canvas.Y; y++) for (int x = 0; x < canvas.X; x++)
        {
            Vector2 point = inverse * new Vector2(x + .5f, y + .5f) + pivot;
            if (point.X < 0 || point.Y < 0 || point.X >= width || point.Y >= height) continue;
            int inputIndex = ((int)point.Y * width + (int)point.X) * 4;
            int outputIndex = (y * canvas.X + x) * 4;
            var color = new Color(pixels[inputIndex], pixels[inputIndex + 1], pixels[inputIndex + 2], pixels[inputIndex + 3]);
            if (sourceIsSrgb) color = color.SrgbToLinear();
            output[outputIndex] = color.R; output[outputIndex + 1] = color.G; output[outputIndex + 2] = color.B; output[outputIndex + 3] = color.A;
        }
        byte[] bytes = new byte[output.Length * sizeof(float)]; Buffer.BlockCopy(output, 0, bytes, 0, bytes.Length);
        return Image.CreateFromData(canvas.X, canvas.Y, false, Image.Format.Rgbaf, bytes);
    }

    public Image opacity(Image source, float amount)
    {
        float[] pixels = ReadPixels(source, out var image, out var bytes);
        for (int i = 3; i < pixels.Length; i += 4) pixels[i] *= amount;
        return WritePixels(image, bytes, pixels);
    }

    public Image shape(Vector2I size, string kind, Color color, Vector2[] points)
    {
        int width = Math.Clamp(size.X, 1, 4096), height = Math.Clamp(size.Y, 1, 4096);
        byte[] pixels = new byte[checked(width * height * 4)];
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
        {
            bool inside = true;
            if (kind == "ellipse")
            {
                float dx = (x + .5f) / width * 2 - 1, dy = (y + .5f) / height * 2 - 1;
                inside = dx * dx + dy * dy <= 1;
            }
            else if (kind == "triangle") inside = y >= MathF.Abs(x - width * .5f) * height / Math.Max(1, width * .5f);
            else if (kind == "polygon") inside = points.Length >= 3 && Geometry2D.IsPointInPolygon(new Vector2(x + .5f, y + .5f), points);
            if (!inside) continue;
            int index = (y * width + x) * 4;
            pixels[index] = (byte)color.R8; pixels[index + 1] = (byte)color.G8; pixels[index + 2] = (byte)color.B8; pixels[index + 3] = (byte)color.A8;
        }
        return Image.CreateFromData(width, height, false, Image.Format.Rgba8, pixels);
    }

    public Color composite_pixel(Color background, Color foreground, int mode)
    {
        if (mode == 1) return composite_pixel(foreground, background, 0);
        float ab = Math.Clamp(background.A, 0, 1), af = Math.Clamp(foreground.A, 0, 1);
        var cb = new Godot.Vector3(background.R, background.G, background.B);
        var cf = new Godot.Vector3(foreground.R, foreground.G, foreground.B);
        if (mode == 2) { float a = af * ab; return new Color(cf.X, cf.Y, cf.Z, a); }
        if (mode == 3) return new Color(cf.X, cf.Y, cf.Z, af * (1 - ab));
        if (mode == 4)
        {
            var color = ab > .000001f ? (cf * af * ab + cb * ab * (1 - af)) / ab : Godot.Vector3.Zero;
            return new Color(color.X, color.Y, color.Z, ab);
        }
        var blend = mode switch
        {
            5 => cf + cb, 6 => cb - cf, 7 => cf * cb,
            8 => Godot.Vector3.One - (Godot.Vector3.One - cf) * (Godot.Vector3.One - cb),
            9 => (cf - cb).Abs(),
            10 => new Godot.Vector3(Math.Min(cf.X, cb.X), Math.Min(cf.Y, cb.Y), Math.Min(cf.Z, cb.Z)),
            11 => new Godot.Vector3(Math.Max(cf.X, cb.X), Math.Max(cf.Y, cb.Y), Math.Max(cf.Z, cb.Z)),
            _ => cf
        };
        float alpha = af + ab * (1 - af);
        var premultiplied = mode == 0 || mode == 12 ? cf * af + cb * ab * (1 - af)
            : cf * af * (1 - ab) + cb * ab * (1 - af) + blend * af * ab;
        var rgb = alpha > .000001f ? premultiplied / alpha : Godot.Vector3.Zero;
        return new Color(rgb.X, rgb.Y, rgb.Z, alpha);
    }

    public Image blend(Image backdrop, Image source, int mode, float opacity, Image? matte, bool sourceIsSrgb)
    {
        float[] pixels = ReadPixels(backdrop, out var output, out var bytes);
        float[] foreground = ReadPixels(source, out var input, out _);
        float[]? mask = null; Image? maskImage = null;
        if (matte != null && !matte.IsEmpty()) mask = ReadPixels(matte, out maskImage, out _);
        int width = output.GetWidth(), inputWidth = input.GetWidth(); opacity = Math.Clamp(opacity, 0, 1);
        for (int y = 0; y < output.GetHeight(); y++) for (int x = 0; x < width; x++)
        {
            int index = (y * width + x) * 4;
            Color front = Colors.Transparent;
            if (x < inputWidth && y < input.GetHeight())
            {
                int fi = (y * inputWidth + x) * 4;
                front = new Color(foreground[fi], foreground[fi + 1], foreground[fi + 2], foreground[fi + 3]);
                if (sourceIsSrgb) front = front.SrgbToLinear();
            }
            float weight = opacity;
            if (mask != null && maskImage != null && x < maskImage.GetWidth() && y < maskImage.GetHeight())
            {
                int mi = (y * maskImage.GetWidth() + x) * 4;
                weight *= Math.Clamp(mask[mi + 3] * (mask[mi] * .2126f + mask[mi + 1] * .7152f + mask[mi + 2] * .0722f), 0, 1);
            }
            front.A *= weight;
            Color result = composite_pixel(new Color(pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3]), front, mode);
            pixels[index] = result.R; pixels[index + 1] = result.G; pixels[index + 2] = result.B; pixels[index + 3] = result.A;
        }
        return WritePixels(output, bytes, pixels);
    }

    public Image alpha_extract(Image source, int width, int height)
    {
        float[] input = ReadPixels(source, out var image, out _);
        float[] output = new float[checked(width * height * 4)];
        for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
        {
            int index = (y * width + x) * 4;
            float alpha = x < image.GetWidth() && y < image.GetHeight() ? input[(y * image.GetWidth() + x) * 4 + 3] : 0;
            output[index] = output[index + 1] = output[index + 2] = alpha; output[index + 3] = 1;
        }
        byte[] bytes = new byte[output.Length * sizeof(float)]; Buffer.BlockCopy(output, 0, bytes, 0, bytes.Length);
        return Image.CreateFromData(width, height, false, Image.Format.Rgbaf, bytes);
    }

    public Image apply_matte(Image source, Image matte)
    {
        float[] pixels = ReadPixels(source, out var image, out var bytes);
        float[] mask = ReadPixels(matte, out var maskImage, out _);
        int width = image.GetWidth(), maskWidth = maskImage.GetWidth();
        for (int y = 0; y < image.GetHeight(); y++) for (int x = 0; x < width; x++)
        {
            int index = (y * width + x) * 4;
            int mi = (y * maskWidth + x) * 4;
            pixels[index + 3] *= x < maskWidth && y < maskImage.GetHeight() ? mask[mi] * mask[mi + 3] : 0;
        }
        return WritePixels(image, bytes, pixels);
    }

    public Image mix_adjustment(Image source, Image adjusted, float opacity, Image? matte)
    {
        float[] pixels = ReadPixels(source, out var image, out var bytes);
        float[] changed = ReadPixels(adjusted, out _, out _);
        float[]? mask = null; Image? maskImage = null;
        if (matte != null && !matte.IsEmpty()) mask = ReadPixels(matte, out maskImage, out _);
        int width = image.GetWidth(); opacity = Math.Clamp(opacity, 0, 1);
        for (int y = 0; y < image.GetHeight(); y++) for (int x = 0; x < width; x++)
        {
            int index = (y * width + x) * 4; float weight = opacity;
            if (mask != null && maskImage != null)
            {
                if (x >= maskImage.GetWidth() || y >= maskImage.GetHeight()) weight = 0;
                else
                {
                    int mi = (y * maskImage.GetWidth() + x) * 4;
                    weight *= Math.Clamp(mask[mi + 3] * (mask[mi] * .2126f + mask[mi + 1] * .7152f + mask[mi + 2] * .0722f), 0, 1);
                }
            }
            for (int component = 0; component < 4; component++) pixels[index + component] = Mathf.Lerp(pixels[index + component], changed[index + component], weight);
        }
        return WritePixels(image, bytes, pixels);
    }

    private static float Number(Godot.Collections.Dictionary settings, string key, float fallback) =>
        settings.TryGetValue(key, out Variant value) ? (float)value.AsDouble() : fallback;

    private static float[] ReadPixels(Image source, out Image image, out byte[] bytes)
    {
        image = (Image)source.Duplicate(); image.Convert(Image.Format.Rgbaf); bytes = image.GetData();
        var pixels = new float[bytes.Length / sizeof(float)]; Buffer.BlockCopy(bytes, 0, pixels, 0, bytes.Length); return pixels;
    }

    private static Image WritePixels(Image image, byte[] bytes, float[] pixels)
    {
        Buffer.BlockCopy(pixels, 0, bytes, 0, bytes.Length);
        return Image.CreateFromData(image.GetWidth(), image.GetHeight(), false, Image.Format.Rgbaf, bytes);
    }

    public float curve_sample(Godot.Collections.Array points, float value)
    {
        if (points.Count < 2) return value;
        var sorted = new Godot.Vector2[points.Count];
        for (int i = 0; i < points.Count; i++) sorted[i] = points[i].AsVector2();
        Array.Sort(sorted, (a, b) => a.X.CompareTo(b.X));
        return SampleSorted(sorted, value);
    }

    private static float SampleSorted(Godot.Vector2[] points, float value)
    {
        if (points.Length < 2) return value;
        if (value <= points[0].X) return points[0].Y;
        for (int i = 1; i < points.Length; i++)
        {
            if (value > points[i].X) continue;
            float width = points[i].X - points[i - 1].X;
            if (width <= 0.000001f) return points[i].Y;
            return Mathf.Lerp(points[i - 1].Y, points[i].Y, (value - points[i - 1].X) / width);
        }
        return points[^1].Y;
    }

    public Image grade(Image source, Godot.Collections.Dictionary settings)
    {
        float[] pixels = ReadPixels(source, out var image, out var bytes);
        float gain = MathF.Pow(2f, Number(settings, "exposure", 0));
        float brightness = Number(settings, "brightness", 0), contrast = Number(settings, "contrast", 1);
        float saturation = Number(settings, "saturation", 1), temperature = Number(settings, "temperature", 0), tint = Number(settings, "tint", 0);
        var curves = settings.TryGetValue("curves", out var curveValue) ? curveValue.AsGodotDictionary() : new Godot.Collections.Dictionary();
        var channels = new Godot.Vector2[4][]; string[] names = { "master", "red", "green", "blue" };
        for (int channel = 0; channel < 4; channel++)
        {
            var points = curves.TryGetValue(names[channel], out var value) ? value.AsGodotArray() : new Godot.Collections.Array();
            channels[channel] = new Godot.Vector2[points.Count];
            for (int i = 0; i < points.Count; i++) channels[channel][i] = points[i].AsVector2();
            Array.Sort(channels[channel], (a, b) => a.X.CompareTo(b.X));
        }
        for (int i = 0; i < pixels.Length; i += 4)
        {
            float r = pixels[i] * gain + brightness + temperature * .1f - tint * .03f;
            float g = pixels[i + 1] * gain + brightness + tint * .05f;
            float b = pixels[i + 2] * gain + brightness - temperature * .1f - tint * .03f;
            r = (r - .18f) * contrast + .18f; g = (g - .18f) * contrast + .18f; b = (b - .18f) * contrast + .18f;
            float luminance = r * .2126f + g * .7152f + b * .0722f;
            r = luminance + (r - luminance) * saturation; g = luminance + (g - luminance) * saturation; b = luminance + (b - luminance) * saturation;
            pixels[i] = SampleSorted(channels[1], SampleSorted(channels[0], r));
            pixels[i + 1] = SampleSorted(channels[2], SampleSorted(channels[0], g));
            pixels[i + 2] = SampleSorted(channels[3], SampleSorted(channels[0], b));
        }
        return WritePixels(image, bytes, pixels);
    }

    public Image chroma_key(Image source, Godot.Collections.Dictionary settings)
    {
        float[] pixels = ReadPixels(source, out var image, out var bytes);
        Color key = settings.TryGetValue("key_color", out var value) ? value.AsColor() : new Color(0, 1, 0, 1);
        float tolerance = Math.Clamp(Number(settings, "tolerance", .2f), 0, 2), softness = Math.Max(.0001f, Number(settings, "softness", .1f));
        float spill = Math.Clamp(Number(settings, "spill", .5f), 0, 1);
        for (int i = 0; i < pixels.Length; i += 4)
        {
            float r = pixels[i] - key.R, g = pixels[i + 1] - key.G, b = pixels[i + 2] - key.B;
            float amount = Math.Clamp((MathF.Sqrt(r * r + g * g + b * b) - tolerance) / softness, 0, 1);
            pixels[i + 3] *= amount * amount * (3 - 2 * amount);
            pixels[i + 1] = Mathf.Lerp(pixels[i + 1], Math.Min(pixels[i + 1], Math.Max(pixels[i], pixels[i + 2])), spill);
        }
        return WritePixels(image, bytes, pixels);
    }

    public Image luma_key(Image source, Godot.Collections.Dictionary settings)
    {
        float[] pixels = ReadPixels(source, out var image, out var bytes);
        float low = Math.Clamp(Number(settings, "low", .1f), 0, 1), high = Math.Clamp(Number(settings, "high", .9f), 0, 1);
        if (high < low) (low, high) = (high, low);
        float softness = Math.Max(.0001f, Number(settings, "softness", .05f));
        bool invert = settings.TryGetValue("invert", out var value) && value.AsBool();
        for (int i = 0; i < pixels.Length; i += 4)
        {
            float luma = Math.Clamp(pixels[i] * .2126f + pixels[i + 1] * .7152f + pixels[i + 2] * .0722f, 0, 1);
            float matte = Mathf.SmoothStep(low - softness, low + softness, luma) * (1 - Mathf.SmoothStep(high - softness, high + softness, luma));
            pixels[i + 3] *= invert ? 1 - matte : matte;
        }
        return WritePixels(image, bytes, pixels);
    }

    public Image blur(Image source, int radius)
    {
        var image = (Image)source.Duplicate(); image.Convert(Image.Format.Rgbaf);
        radius = Math.Clamp(radius, 0, 32);
        if (radius == 0) return image;
        int width = image.GetWidth(), height = image.GetHeight();
        byte[] bytes = image.GetData();
        float[] pixels = new float[checked(width * height * 4)];
        Buffer.BlockCopy(bytes, 0, pixels, 0, bytes.Length);
        var horizontal = new Vector4[checked(width * height)];
        Vector4 Read(int x, int y)
        {
            int index = (y * width + x) * 4; float alpha = pixels[index + 3];
            return new Vector4(pixels[index] * alpha, pixels[index + 1] * alpha, pixels[index + 2] * alpha, alpha);
        }
        for (int y = 0; y < height; y++)
        {
            Vector4 sum = Vector4.Zero;
            for (int x = 0; x < Math.Min(width, radius + 1); x++) sum += Read(x, y);
            for (int x = 0; x < width; x++)
            {
                int count = Math.Min(width - 1, x + radius) - Math.Max(0, x - radius) + 1;
                horizontal[y * width + x] = sum / count;
                if (x - radius >= 0) sum -= Read(x - radius, y);
                if (x + radius + 1 < width) sum += Read(x + radius + 1, y);
            }
        }
        for (int x = 0; x < width; x++)
        {
            Vector4 sum = Vector4.Zero;
            for (int y = 0; y < Math.Min(height, radius + 1); y++) sum += horizontal[y * width + x];
            for (int y = 0; y < height; y++)
            {
                int count = Math.Min(height - 1, y + radius) - Math.Max(0, y - radius) + 1;
                Vector4 value = sum / count; int index = (y * width + x) * 4;
                float inverseAlpha = value.W > 0.000001f ? 1f / value.W : 0f;
                pixels[index] = value.X * inverseAlpha; pixels[index + 1] = value.Y * inverseAlpha;
                pixels[index + 2] = value.Z * inverseAlpha; pixels[index + 3] = Math.Max(0f, value.W);
                if (y - radius >= 0) sum -= horizontal[(y - radius) * width + x];
                if (y + radius + 1 < height) sum += horizontal[(y + radius + 1) * width + x];
            }
        }
        Buffer.BlockCopy(pixels, 0, bytes, 0, bytes.Length);
        return Image.CreateFromData(width, height, false, Image.Format.Rgbaf, bytes);
    }
}
