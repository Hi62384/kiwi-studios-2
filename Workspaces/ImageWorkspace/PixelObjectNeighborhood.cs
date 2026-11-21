using Godot;
using System.Collections.Generic;
public partial class PixelObjectSegmenterKernel
{
    private Neighborhood Adjacent(Vector2I point)=>new(point,_field.Size);
    private readonly struct Neighborhood
    {
        private readonly Vector2I _point,_size;
        public Neighborhood(Vector2I point,Vector2I size){_point=point;_size=size;}
        public NeighborEnumerator GetEnumerator()=>new(_point,_size);
    }
    private struct NeighborEnumerator
    {
        private readonly Vector2I _point,_size;private int _slot;
        public int Current{get;private set;}
        public NeighborEnumerator(Vector2I point,Vector2I size){_point=point;_size=size;_slot=0;Current=0;}
        public bool MoveNext()
        {
            int index=_point.Y*_size.X+_point.X;
            while(_slot<4){switch(_slot++){case 0:if(_point.X>0){Current=index-1;return true;}break;case 1:if(_point.X+1<_size.X){Current=index+1;return true;}break;case 2:if(_point.Y>0){Current=index-_size.X;return true;}break;case 3:if(_point.Y+1<_size.Y){Current=index+_size.X;return true;}break;}}return false;
        }
    }
}
