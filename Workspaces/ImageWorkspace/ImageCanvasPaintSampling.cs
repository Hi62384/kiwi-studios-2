using Godot;
using System;
public partial class ImageCanvasSelectionOperations
{
    internal sealed class SelectionSampler
    {
        private readonly Image? _mask;private readonly byte[]? _bytes;private readonly Transform2D _inverse;private readonly ImageSelectionMapping? _mapping;private readonly Func<Vector2,Vector2>? _custom;private readonly Rect2I _bounds;
        public SelectionSampler(Control canvas)
        {
            _mask=canvas.Get("selection").As<Image>();_inverse=canvas.Get("selection_inverse").AsTransform2D();bool warped=_mask!=null&&HasWarp(canvas,true);_mapping=warped?canvas.Get("_selection_mapping").AsGodotObject() as ImageSelectionMapping:null;if(_mask!=null){_bounds=new Rect2I(Vector2I.Zero,_mask.GetSize());if(_mask.GetFormat()==Image.Format.Rgba8)_bytes=_mask.GetData();if(_mapping==null&&warped)_custom=point=>canvas.Call("_map_selection_point",point,true).AsVector2();}
        }
        public double Coverage(Vector2 point){if(_mask==null)return 1;var at=(Vector2I)(_mapping!=null?_mapping.inverse(point):_custom!=null?_custom(point):_inverse*point).Floor();return _bounds.HasPoint(at)?_bytes!=null?_bytes[(at.Y*_bounds.Size.X+at.X)*4+3]/255f:_mask.GetPixelv(at).A:0;}
        public bool Exists=>_mask!=null;
        public bool Identity=>_mapping==null&&_custom==null&&_inverse.IsEqualApprox(Transform2D.Identity);
    }
    private sealed class ValueColorSampler
    {
        private readonly Color _color,_inverseColor;private readonly bool _material,_selectedOnly,_local;private readonly Image? _mask;private readonly Rect2I _bounds;private readonly Transform2D _mapping,_worldInverse;private readonly ImageLayerProjection _projection;private readonly Vector2 _content;
        public ValueColorSampler(ImageCanvasSelectionOperations operations,Control canvas,Resource item)
        {
            _color=canvas.Get("color").AsColor();_inverseColor=canvas.Get("_value_inverse_color").AsColor();_material=canvas.Get("_material_region").AsGodotObject()!=null;var properties=item.Get("properties").AsGodotDictionary();_selectedOnly=Get(properties,"values_selection_only",false).AsBool();_local=Get(properties,"values_selection_local",false).AsBool();_mask=canvas.Get("_value_mask").As<Image>();_mapping=canvas.Get("_value_mask_mapping").AsTransform2D();if(_mask!=null)_bounds=new Rect2I(Vector2I.Zero,_mask.GetSize());if(_selectedOnly&&_local){_projection=new ImageLayerProjection(item);_content=operations._layers.content_dimensions(item);_worldInverse=operations._documents.world_transform(canvas.Get("document").As<Resource>(),item).AffineInverse();}
        }
        public Color Source(Vector2 point)
        {
            if(_material)return Colors.White;if(_selectedOnly){if(_mask==null)return _color;var at=(Vector2I)(_mapping*point);if(_local)at=(Vector2I)(_projection.Unproject(_worldInverse*point)/_content*(Vector2)_mask.GetSize());if(!_bounds.HasPoint(at)||_mask.GetPixelv(at).A<=0)return _color;}return _inverseColor;
        }
    }
}
