using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ImageRepairEngineOperations
{
    private static float Luminance(Color color)=>color.R*.2126f+color.G*.7152f+color.B*.0722f;
    private static Settings Composite(Node owner,Settings job,Settings settings,Image original,Image destination,Image reconstructed,Image mask,Image? selection,Image? localSelection,Image? layerMask,Rect2I area,string mode,double amount,bool editable,bool clip,bool newLayer)
    {
        var output=(Image)destination.Duplicate();var coverageImage=Image.CreateEmpty(area.Size.X,area.Size.Y,false,Image.Format.Rgba8);
        var frame=Get(job,"frame",Transform2D.Identity).AsTransform2D();var reference=Get(job,"reference").As<Resource>();var selectionReference=Get(job,"selection_reference").As<Resource>();
        ImageLayerProjection? projection=reference!=null?new ImageLayerProjection(reference):null,selectionProjection=selectionReference!=null?new ImageLayerProjection(selectionReference):null;
        var selectionInverse=Get(job,"selection_inverse",Transform2D.Identity).AsTransform2D();var selectionWorld=Get(job,"selection_world",Transform2D.Identity).AsTransform2D();var inverseFrame=frame.AffineInverse();
        var prior=editable?job["prior_coverage"].As<Image>():null;bool selectionOnly=Get(settings,"selection_only",true).AsBool();string blending=Get(settings,"material_blending","").AsString();
        for(int y=0;y<area.Size.Y;y++)
        {
            if(job["generation"].AsInt64()!=owner.Get("_generation").AsInt64()){output.Dispose();coverageImage.Dispose();return new Settings{["kind"]=mode};}
            for(int x=0;x<area.Size.X;x++)
            {
                double coverage=mask.GetPixel(x,y).A*amount;var p=(Vector2)(area.Position+new Vector2I(x,y))+Vector2.One*.5f;
                if(localSelection!=null)coverage*=localSelection.GetPixelv((Vector2I)p).A;
                else if(selection!=null&&selectionOnly)
                {
                    var world=projection.HasValue?frame*projection.Value.Project(p/(Vector2)original.GetSize()*projection.Value.Dimensions,new Vector2(-1,-1)):frame*p;
                    var at=selectionInverse*world;
                    if(selectionProjection.HasValue&&projection.HasValue)at=selectionWorld*selectionProjection.Value.Project(projection.Value.Unproject(inverseFrame*world)/projection.Value.Dimensions*selectionProjection.Value.Dimensions,new Vector2(-1,-1));
                    var pixel=(Vector2I)at.Floor();coverage*=new Rect2I(Vector2I.Zero,selection.GetSize()).HasPoint(pixel)?selection.GetPixelv(pixel).A:0;
                }
                if(clip)coverage*=original.GetPixelv((Vector2I)p).A;
                if(layerMask!=null)coverage*=layerMask.GetPixelv(((Vector2I)(p/(Vector2)original.GetSize()*(Vector2)layerMask.GetSize())).Clamp(Vector2I.Zero,layerMask.GetSize()-Vector2I.One)).R;
                float weight=(float)Math.Clamp(coverage,0,1);var desired=reconstructed.GetPixel(x,y);var old=destination.GetPixel(x,y);
                if(editable){float oldCoverage=prior!.GetPixelv(area.Position+new Vector2I(x,y)).A;coverageImage.SetPixel(x,y,new Color(1,1,1,oldCoverage+(1-oldCoverage)*weight));continue;}
                switch(blending)
                {
                    case "overlay":for(int channel=0;channel<3;channel++)desired[channel]=old[channel]<.5f?2*old[channel]*desired[channel]:1-2*(1-old[channel])*(1-desired[channel]);break;
                    case "colorize":float ratio=Luminance(old)/Math.Max(.01f,Luminance(desired));desired.R*=ratio;desired.G*=ratio;desired.B*=ratio;break;
                    case "detail":float gain=.65f+Luminance(desired)*.7f;desired.R=old.R*gain;desired.G=old.G*gain;desired.B=old.B*gain;break;
                }
                if((mode is "pattern_fill" or "procedural")&&desired.A<1&&!newLayer)
                {
                    float alpha=desired.A+old.A*(1-desired.A),denominator=Math.Max(.00001f,alpha);desired=new Color((desired.R*desired.A+old.R*old.A*(1-desired.A))/denominator,(desired.G*desired.A+old.G*old.A*(1-desired.A))/denominator,(desired.B*desired.A+old.B*old.A*(1-desired.A))/denominator,alpha);
                }
                output.SetPixel(x,y,newLayer?new Color(desired.R,desired.G,desired.B,desired.A*weight):old.Lerp(desired,weight));
            }
        }
        return new Settings{["image"]=output,["area"]=area,["kind"]=mode,["coverage"]=coverageImage};
    }
}
