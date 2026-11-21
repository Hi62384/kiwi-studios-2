using Godot;
using System;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class ImageRepairEngineOperations:RefCounted
{
    private static Variant Get(Settings d,string key,Variant fallback=default)=>d.TryGetValue(key,out var value)?value:fallback;
    public void cancel(Node owner){owner.Set("_generation",owner.Get("_generation").AsInt64()+1);owner.Get("_pending").AsGodotDictionary().Clear();}
    public long submit(Node owner,Settings job){long sequence=owner.Get("_sequence").AsInt64()+1;owner.Set("_sequence",sequence);var next=job.Duplicate();next["generation"]=owner.Get("_generation");next["sequence"]=sequence;owner.Set("_pending",next);return sequence;}
    public bool busy(Node owner)=>owner.Get("_thread").AsGodotObject()!=null||owner.Get("_pending").AsGodotDictionary().Count>0;
    public void process(Node owner)
    {
        var thread=owner.Get("_thread").As<GodotThread>();
        if(thread!=null&&!thread.IsAlive())
        {
            using var completed=thread.WaitToFinish();var result=completed.AsGodotDictionary();owner.Set("_thread",default(Variant));thread.Dispose();thread=null;
            var job=owner.Get("_job").AsGodotDictionary();if(job["generation"].AsInt64()==owner.Get("_generation").AsInt64()){result["sequence"]=job["sequence"];owner.EmitSignal("preview",result);}
        }
        var pending=owner.Get("_pending").AsGodotDictionary();
        if(thread==null&&pending.Count>0){owner.Set("_job",pending);owner.Set("_pending",new Settings());thread=new GodotThread();owner.Set("_thread",thread);thread.Start(Callable.From<Variant>(()=>work(owner,pending)));}
        else if(thread==null)owner.EmitSignal("idle");
    }
    public void exit_tree(Node owner){cancel(owner);var thread=owner.Get("_thread").As<GodotThread>();if(thread==null)return;using var result=thread.WaitToFinish();owner.Set("_thread",default(Variant));thread.Dispose();}
    public Settings work(Node owner,Settings job)
    {
        bool Cancelled()=>job["generation"].AsInt64()!=owner.Get("_generation").AsInt64();
        var cancellation=owner.Call("_cancellation",job);
        string mode=job["kind"].AsString();
        if(mode=="generate"){using var generator=new ImageProceduralTextureOperations();return new Settings{["image"]=generator.generate(job["recipe"].As<Resource>(),job["size"].AsVector2I(),cancellation,true),["kind"]="generate",["target"]=Get(job,"target","")};}
        var original=job["original"].As<Image>();var sample=job["sample"].As<Image>();var settings=job["settings"].AsGodotDictionary().Duplicate();settings["cancelled"]=cancellation;
        var area=job["area"].AsRect2I();var size=area.Size;using var mask=Image.CreateEmpty(size.X,size.Y,false,Image.Format.Rgba8);
        string application=Get(settings,"application","continuous").AsString();bool scattered=application=="scatter",stamped=scattered||application=="stamp";
        var points=job["points"].AsVector2Array();var angles=new float[points.Length];var scales=new float[points.Length];var buckets=new Dictionary<Vector2I,List<int>>();double brushSize=settings["size"].AsDouble();
        if(stamped)for(int i=0;i<points.Length;i++)
        {
            using var rng=new RandomNumberGenerator{Seed=unchecked((uint)GD.Hash(new GArray{points[i],Get(settings,"seed",0)}))};
            if(scattered)points[i]+=new Vector2(rng.RandfRange(-1,1),rng.RandfRange(-1,1))*(float)(brushSize*Get(settings,"jitter",.25).AsDouble());
            angles[i]=Mathf.DegToRad((float)(Get(settings,"rotation",0).AsDouble()+rng.RandfRange(-1,1)*Get(settings,"random_rotation",0).AsDouble()));
            if(Get(settings,"follow_direction",false).AsBool()&&i>0)angles[i]+=(points[i]-points[i-1]).Angle();scales[i]=(float)Math.Max(.1,1+rng.RandfRange(-1,1)*Get(settings,"random_scale",0).AsDouble());
            var bucket=(Vector2I)(points[i]/(float)brushSize).Floor();for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){var key=bucket+new Vector2I(x,y);if(!buckets.TryGetValue(key,out var indices)){indices=new();buckets[key]=indices;}indices.Add(i);}
        }
        using var alpha=new PixelSelectionAlphaOperations();using var stamp=alpha.stamp(brushSize,1-settings["hardness"].AsDouble());if(stamped)stamp.Fill(Colors.White);
        var pressures=Get(settings,"pressures",Array.Empty<float>()).AsFloat32Array();
        for(int i=0;i<points.Length;i++)
        {
            Image dab=stamp;if(Get(settings,"pressure",false).AsBool()){dab=(Image)stamp.Duplicate();int diameter=Math.Max(1,Mathf.RoundToInt(brushSize*(i<pressures.Length?pressures[i]:1)));dab.Resize(diameter,diameter,Image.Interpolation.Bilinear);}
            mask.BlendRect(dab,new Rect2I(Vector2I.Zero,dab.GetSize()),(Vector2I)points[i]-area.Position-dab.GetSize()/2);if(dab!=stamp)dab.Dispose();
        }
        bool fill=Get(job,"fill",false).AsBool(),editable=Get(job,"editable_texture",false).AsBool(),clip=Get(settings,"clip_alpha",false).AsBool(),newLayer=Get(settings,"new_layer",false).AsBool();
        if(fill)mask.Fill(Colors.White);var selection=Get(job,"selection").As<Image>();Image? feathered=null;
        if(fill&&selection!=null&&Get(settings,"boundary_feather",0).AsDouble()>0){feathered=alpha.feather(selection,settings["boundary_feather"].AsDouble());selection=feathered;}
        try
        {
            double amount=Get(settings,"strength",1).AsDouble()*Get(settings,"opacity",1).AsDouble();var layerMask=Get(job,"layer_mask").As<Image>();
            if(editable&&selection==null&&layerMask==null&&!clip)
            {
                using var scaled=ScaleMask(mask,amount);var coverage=job["prior_coverage"].As<Image>().GetRegion(area);coverage.BlendRect(scaled,new Rect2I(Vector2I.Zero,size),Vector2I.Zero);return new Settings{["area"]=area,["kind"]=mode,["coverage"]=coverage};
            }
            using var destination=original.GetRegion(area);Image reconstructed=(Image)destination.Duplicate();var sourceArea=job["source_area"].AsRect2I();using var healing=new ImageHealingOperations();using var patterns=new ImagePatternFillOperations();
            var localSelection=Get(job,"local_selection").As<Image>();
            try
            {
                if(!editable&&(mode is "pattern_heal" or "patch"||(mode is "pattern_fill" or "procedural")&&Get(settings,"behavior","").AsString()=="synthesis"))
                {
                    bool automatic=Get(job,"automatic",false).AsBool();var excluded=automatic?area:new Rect2I();using var local=localSelection?.GetRegion(area);var matching=local??mask;
                    if(automatic){settings["exclusion_mask"]=matching;settings["exclusion_origin"]=area.Position;}
                    using var synthesis=new ImageTextureSynthesisOperations();reconstructed.Dispose();reconstructed=synthesis.synthesize(destination,sample,sourceArea,matching,settings,area.Position,excluded,true);
                }
                else if(!editable&&mode=="spot")
                {
                    int tile=Math.Max(8,Math.Min(32,Mathf.RoundToInt(brushSize)));
                    for(int y=area.Position.Y;y<area.End.Y;y+=tile)for(int x=area.Position.X;x<area.End.X;x+=tile){if(Cancelled())return new Settings{["kind"]=mode};var piece=new Rect2I(x,y,Math.Min(tile,area.End.X-x),Math.Min(tile,area.End.Y-y));using var patch=healing.spot_patch(original,piece,settings,area,true);reconstructed.BlitRect(patch,new Rect2I(Vector2I.Zero,patch.GetSize()),piece.Position-area.Position);}
                }
                else if(!editable)
                {
                    var sourceMean=healing.mean(sample,sourceArea,new Rect2I());var targetMean=healing.mean(original,area.Grow(Math.Max(4,Math.Max(size.X,size.Y)/2)),area);
                    var sampledLayer=Get(job,"reference").As<Resource>();ImageLayerProjection? projection=sampledLayer!=null?new ImageLayerProjection(sampledLayer):null;
                    var sampledFrame=Get(job,"frame",Transform2D.Identity).AsTransform2D();var basis=Get(job,"sample_basis",Transform2D.Identity).AsTransform2D();var anchor=Get(job,"destination_anchor",Vector2.Zero).AsVector2();
                    for(int y=0;y<size.Y;y++){if(Cancelled())return new Settings{["kind"]=mode};for(int x=0;x<size.X;x++)
                    {
                        var p=(Vector2)(area.Position+new Vector2I(x,y));var color=Colors.Transparent;
                        if(mode is "pattern_fill" or "procedural")
                        {
                            if(stamped&&!fill)
                            {
                                int best=-1;float distance=float.PositiveInfinity;if(buckets.TryGetValue((Vector2I)(p/(float)brushSize).Floor(),out var indices))foreach(int index in indices){float next=p.DistanceSquaredTo(points[index]);if(next<distance){distance=next;best=index;}}
                                if(best>=0){var at=(p-points[best]).Rotated(-angles[best])/(float)Math.Max(1,Get(settings,"stamp_extent",brushSize).AsDouble()*scales[best])+Vector2.One*.5f;if(new Rect2(0,0,1,1).HasPoint(at))color=sample.GetPixelv(((Vector2I)(at*(Vector2)sample.GetSize())).Clamp(Vector2I.Zero,sample.GetSize()-Vector2I.One));}
                            }
                            else color=patterns.sample(sample,sourceArea,p,settings);
                        }
                        else
                        {
                            var delta=(p-anchor).Rotated(-Mathf.DegToRad((float)Get(settings,"rotation",0).AsDouble()))/(float)Math.Max(.01,Get(settings,"scale",1).AsDouble());var sampleDelta=basis.BasisXform(delta);
                            if(Get(settings,"sample_mode","current").AsString()!="current"&&projection.HasValue){var proj=projection.Value;sampleDelta=sampledFrame.BasisXform(proj.Project((anchor+delta)/(Vector2)original.GetSize()*proj.Dimensions,new Vector2(-1,-1))-proj.Project(anchor/(Vector2)original.GetSize()*proj.Dimensions,new Vector2(-1,-1)));}
                            var sourcePoint=job["source_anchor"].AsVector2()+Get(settings,"offset",Vector2.Zero).AsVector2()+sampleDelta;
                            if(!new Rect2(Vector2.Zero,(Vector2)sample.GetSize()).HasPoint(sourcePoint)){mask.SetPixel(x,y,Colors.Transparent);continue;}
                            color=sample.GetPixelv((Vector2I)sourcePoint);if(mode=="heal"&&Get(settings,"healing_blend","texture").AsString()=="texture")color=healing.adapt(color,sourceMean,targetMean,Get(settings,"texture_preservation",1).AsDouble());
                        }
                        reconstructed.SetPixel(x,y,color);
                    }}
                }
                return Composite(owner,job,settings,original,destination,reconstructed,mask,selection,localSelection,layerMask,area,mode,amount,editable,clip,newLayer);
            }
            finally{reconstructed.Dispose();}
        }
        finally{feathered?.Dispose();}
    }
    private static Image ScaleMask(Image mask,double amount)
    {
        var bytes=mask.GetData();if(!Mathf.IsEqualApprox(amount,1))for(int i=3;i<bytes.Length;i+=4)bytes[i]=(byte)Math.Clamp(Mathf.RoundToInt(bytes[i]*amount),0,255);
        return Image.CreateFromData(mask.GetWidth(),mask.GetHeight(),false,Image.Format.Rgba8,bytes);
    }
}
