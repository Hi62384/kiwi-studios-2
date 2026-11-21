using Godot;
using System;
using GArray=Godot.Collections.Array;
using Settings=Godot.Collections.Dictionary;
public partial class AudioPatternCanvasOperations
{
    private static readonly string[] DrumNames={"Kick","Snare","Closed hat","Open hat","Tom","Crash","Ride","Clap"};
    public void draw(Control o)
    {
        o.DrawRect(new Rect2(Vector2.Zero,o.Size),new Color("101a24"));bool steps=Text(o,"mode")=="steps";float height=(float)N(o,"row_height"),zoom=(float)N(o,"pixels_per_beat"),scroll=(float)N(o,"scroll_beat"),snap=(float)N(o,"snap_beat");var font=o.Get("_font").As<Font>();var session=Session(o);var document=session?.Get("document").AsGodotObject();int start=(int)N(o,"start_pitch"),rows=steps?Drums.Length:(int)Math.Ceiling((o.Size.Y-Top)/height);using var composer=new AudioComposerOperations();var scales=composer.scales();string scale=document?.Get("scale").AsString()??"minor";var scaleNotes=scales.TryGetValue(scale,out var scaleValue)?scaleValue.AsGodotArray():new GArray{0,2,3,5,7,8,10};int key=document?.Get("key").AsInt32()??0;
        for(int row=0;row<rows;row++)
        {
            int pitch=steps?Drums[row]:start-row;float y=Top+row*height;bool black=((pitch%12)+12)%12 is 1 or 3 or 6 or 8 or 10;bool inScale=scaleNotes.Contains(((pitch-key)%12+12)%12);o.DrawRect(new Rect2(Keys,y,o.Size.X-Keys,height),new Color(inScale?"1a2b30":"17212b"));o.DrawLine(new Vector2(Keys,y+height),new Vector2(o.Size.X,y+height),new Color("263441"));o.DrawRect(new Rect2(0,y,Keys-2,height-1),new Color(black?"263542":"a4b4bb"));if(steps||pitch%12==0)o.DrawString(font,new Vector2(5,y+height-4),steps?DrumNames[row]:"C"+(pitch/12-1),HorizontalAlignment.Left,64,10,new Color(black?"e5f0f2":"142632"));
        }
        int first=(int)Math.Floor(scroll/snap),last=(int)Math.Ceiling((scroll+Math.Max(0,o.Size.X-Keys)/zoom)/snap);for(int step=first;step<=last;step++){float beat=step*snap,x=Keys+(beat-scroll)*zoom;bool whole=Mathf.IsZeroApprox(Mathf.PosMod(beat,1));o.DrawLine(new Vector2(x,Top),new Vector2(x,o.Size.Y),new Color(whole?"466371":"293b47"));if(whole)o.DrawString(font,new Vector2(x+4,17),((int)beat+1).ToString(),HorizontalAlignment.Left,50,11,new Color("b0c5d1"));}
        var clip=Clip(o);double clipBeat=clip!=null&&document!=null?N(clip,"start_time")*document.Call("arrangement_tempo").AsDouble()/60:0;var chords=document?.Get("chords").AsGodotArray()??new GArray();
        foreach(var raw in notes(o))
        {
            var note=raw.AsGodotDictionary();var rect=note_rect(o,note);var color=new Color("62d6b5").Lerp(new Color("e3c279"),(float)N(note,"velocity",.8));if(Selected(o).Contains(note["id"].AsString()))color=color.Lightened(.25f);o.DrawRect(rect,color);double globalBeat=N(note,"start")+clipBeat;
            foreach(var chordRaw in chords){var chord=chordRaw.AsGodotDictionary();if(globalBeat<N(chord,"start")||globalBeat>=N(chord,"start")+N(chord,"duration",1))continue;var tones=chord.TryGetValue("pitches",out var pitches)?pitches.AsGodotArray():new GArray();foreach(var tone in tones)if(((int)N(note,"pitch")%12+12)%12==((tone.AsInt32()%12)+12)%12){o.DrawRect(rect,new Color("ffefb4"),false,1.5f);break;}break;}
            if(rect.Size.X>28)o.DrawString(font,rect.Position+new Vector2(3,rect.Size.Y-3),((int)N(note,"pitch")).ToString(),HorizontalAlignment.Left,rect.Size.X-4,10,new Color("143129"));float velocity=(float)Math.Clamp(N(note,"velocity",.8),0,1);o.DrawLine(new Vector2(rect.Position.X,o.Size.Y-2),new Vector2(rect.Position.X,o.Size.Y-2-velocity*22),color,3);
        }
        if(clip!=null&&document!=null)
        {
            var actor=Actor(o);var values=actor.Get("values").AsGodotDictionary();var tempos=values.TryGetValue("midi_tempos",out var events)?events.AsGodotArray():new GArray();double timeScale=N(values,"midi_tempo_scale",1);using var timing=new AudioTempoMapOperations();if(timing.validate_tempos(tempos,true).Length>0||!timing.number_in(timeScale,.000001,1000000))return;using var edits=new AudioEditSessionOperations();var canonical=timing.canonical(tempos,edits.note_source_tempo(actor,document));var beats=new double[canonical.Count];var seconds=new double[canonical.Count];var rates=new double[canonical.Count];for(int i=0;i<canonical.Count;i++){beats[i]=N(canonical[i],"beat");rates[i]=N(canonical[i],"microseconds")/1000000*timeScale;if(i>0)seconds[i]=seconds[i-1]+(beats[i]-beats[i-1])*rates[i-1];}
            double ToSeconds(double beat){int i=Array.BinarySearch(beats,Math.Max(0,beat));if(i<0)i=Math.Max(0,~i-1);return seconds[i]+(Math.Max(0,beat)-beats[i])*rates[i];}
            double ToBeat(double value){int i=Array.BinarySearch(seconds,Math.Max(0,value));if(i<0)i=Math.Max(0,~i-1);return beats[i]+(Math.Max(0,value)-seconds[i])/rates[i];}
            double source=N(clip,"source_offset")*N(values,"notes_source_scale",1),window=N(clip,"duration")*N(clip,"playback_speed"),end=source+window;bool wraps=false;if(values.TryGetValue("loop",out var loop)&&loop.AsBool()){double period=ToSeconds(N(o,"pattern_beats"));if(period>0){source=Mathf.PosMod(source,period);end=source+window;if(window>=period){source=0;end=period;}else if(end>period){end-=period;wraps=true;}}}
            double sourceStart=ToBeat(source),sourceEnd=ToBeat(end);float left=Keys+((float)sourceStart-scroll)*zoom,right=Keys+((float)sourceEnd-scroll)*zoom;var shade=new Color(0,0,0,.45f);if(wraps)o.DrawRect(new Rect2(Math.Max(Keys,right),Top,Math.Max(0,Math.Min(o.Size.X,left)-Math.Max(Keys,right)),o.Size.Y-Top),shade);else{if(sourceStart>.00001)o.DrawRect(new Rect2(Keys,Top,Math.Max(0,Math.Min(o.Size.X,left)-Keys),o.Size.Y-Top),shade);if(right<o.Size.X)o.DrawRect(new Rect2(Math.Max(Keys,right),Top,o.Size.X-Math.Max(Keys,right),o.Size.Y-Top),shade);}foreach(float boundary in new[]{left,right})if(boundary>=Keys&&boundary<=o.Size.X)o.DrawLine(new Vector2(boundary,Top),new Vector2(boundary,o.Size.Y),new Color("82afff"),2);
        }
        float loopX=Keys+((float)N(o,"pattern_beats")-scroll)*zoom;o.DrawLine(new Vector2(loopX,0),new Vector2(loopX,o.Size.Y),new Color("eac56f"),2);
    }
}
