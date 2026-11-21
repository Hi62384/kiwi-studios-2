using Godot;
using System;
using System.Text;
using Settings=Godot.Collections.Dictionary;
public partial class ActorShaderTimeOperations:RefCounted
{
    private static bool Start(char value)=>value=='_'||value>='A'&&value<='Z'||value>='a'&&value<='z';
    private static bool Part(char value)=>Start(value)||value>='0'&&value<='9';
    public bool identifier_start(string character)=>character.Length==1&&Start(character[0]);
    public bool identifier_part(string character)=>character.Length==1&&Part(character[0]);
    public Settings prepare(string source)
    {
        string uniform="kiwi_timeline_time";int suffix=2;while(source.Contains(uniform,StringComparison.Ordinal))uniform="kiwi_timeline_time_"+suffix++;var output=new StringBuilder(source.Length+64);int cursor=0;bool hasTime=false,inserted=false,afterShader=false;
        while(cursor<source.Length)
        {
            char current=source[cursor],next=cursor+1<source.Length?source[cursor+1]:'\0';
            if(current=='/'&&next=='/'){int stop=source.IndexOf('\n',cursor);if(stop<0)stop=source.Length;output.Append(source,cursor,stop-cursor);cursor=stop;continue;}
            if(current=='/'&&next=='*'){int stop=source.IndexOf("*/",cursor+2,StringComparison.Ordinal);stop=stop<0?source.Length:stop+2;output.Append(source,cursor,stop-cursor);cursor=stop;continue;}
            if(current=='"'||current=='\''){char quote=current;int stop=cursor+1;while(stop<source.Length){if(source[stop]=='\\'){stop=Math.Min(stop+2,source.Length);continue;}if(source[stop++]==quote)break;}output.Append(source,cursor,stop-cursor);cursor=stop;continue;}
            if(Start(current)){int stop=cursor+1;while(stop<source.Length&&Part(source[stop]))stop++;string word=source.Substring(cursor,stop-cursor);if(word=="shader_type"&&!inserted)afterShader=true;if(word=="TIME"){output.Append(uniform);hasTime=true;}else output.Append(word);cursor=stop;continue;}
            output.Append(current);if(current==';'&&afterShader&&!inserted){output.Append("\nuniform float ").Append(uniform).Append(";\n");inserted=true;afterShader=false;}cursor++;
        }
        bool replace=hasTime&&inserted;return new Settings{["code"]=replace?output.ToString():source,["uniform"]=replace?uniform:""};
    }
}
