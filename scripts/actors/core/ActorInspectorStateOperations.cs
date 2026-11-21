using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;
public partial class ActorInspectorStateOperations:RefCounted
{
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private readonly Expression _comparison=CreateComparison();private static Expression CreateComparison(){var expression=new Expression();expression.Parse("a == b",new[]{"a","b"});return expression;}
    public void restore_from(Resource owner,Resource? other){owner.Set("actor_states",other!=null?other.Get("actor_states").AsGodotDictionary().Duplicate(true):new Settings());owner.EmitChanged();}
    public Settings actor_state(Resource owner,string id)=>Get(owner.Get("actor_states").AsGodotDictionary(),id,new Settings()).AsGodotDictionary().Duplicate();
    public void set_actor_value(Resource owner,string id,string key,Variant value){var state=actor_state(owner,id);if(_comparison.Execute(new GArray{Get(state,key),value}).AsBool())return;state[key]=value;Store(owner,id,state);}
    private static void Store(Resource owner,string id,Settings state){owner.Get("actor_states").AsGodotDictionary()[id]=state;owner.EmitChanged();}
    public double scroll_for(Resource owner,string id)=>Get(actor_state(owner,id),"scroll",0.0).AsDouble();
    public void set_scroll(Resource owner,string id,double value)=>set_actor_value(owner,id,"scroll",Math.Max(value,0));
    public string main_tab_for(Resource owner,string id){string value=Get(actor_state(owner,id),"main_tab","Properties").AsString();return value is "Actor" or "Properties"?value:"Properties";}
    public void set_main_tab(Resource owner,string id,string value){if(value is "Actor" or "Properties")set_actor_value(owner,id,"main_tab",value);}
    public string section_for(Resource owner,string id,string main)=>Get(Get(actor_state(owner,id),"sections",new Settings()).AsGodotDictionary(),main,"").AsString();
    public void set_section(Resource owner,string id,string main,string section){var sections=Get(actor_state(owner,id),"sections",new Settings()).AsGodotDictionary().Duplicate();sections[main]=section;set_actor_value(owner,id,"sections",sections);}
    public double page_scroll_for(Resource owner,string id,string main,string section){var state=actor_state(owner,id);var pages=Get(state,"page_scrolls",new Settings()).AsGodotDictionary();return Get(pages,main+"/"+section,pages.Count==0?Get(state,"scroll",0.0):Variant.From(0.0)).AsDouble();}
    public void set_page_scroll(Resource owner,string id,string main,string section,double value){var state=actor_state(owner,id);var pages=Get(state,"page_scrolls",new Settings()).AsGodotDictionary().Duplicate();string key=main+"/"+section;value=Math.Max(value,0);if(_comparison.Execute(new GArray{Get(pages,key,-1.0),value}).AsBool())return;pages[key]=value;state["page_scrolls"]=pages;state["scroll"]=value;Store(owner,id,state);}
    public bool category_expanded(Resource owner,string id,string category)=>Get(Get(actor_state(owner,id),"categories",new Settings()).AsGodotDictionary(),category,true).AsBool();
    public void set_category_expanded(Resource owner,string id,string category,bool expanded){var state=actor_state(owner,id);var categories=Get(state,"categories",new Settings()).AsGodotDictionary().Duplicate();categories[category]=expanded;state["categories"]=categories;Store(owner,id,state);}
    public bool vector_linked(Resource owner,string id,StringName property)=>Get(Get(actor_state(owner,id),"links",new Settings()).AsGodotDictionary(),property.ToString(),false).AsBool();
    public void set_vector_linked(Resource owner,string id,StringName property,bool linked){var state=actor_state(owner,id);var links=Get(state,"links",new Settings()).AsGodotDictionary().Duplicate();links[property.ToString()]=linked;state["links"]=links;Store(owner,id,state);}
}
