using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class BuildingSessionOperations
{
    public void set_material(RefCounted session,string id,int slot,Material? material)
    {
        var document=Document(session);var root=_documents.component(document,id);var current=source(root);if(current==null||root==null||slot<0||slot>6)return;var next=_sources.copy(current);var nextMaterials=next.Get("materials").AsGodotArray();while(nextMaterials.Count<=slot)nextMaterials.Add(nextMaterials.Count==6&&nextMaterials.Count>1?nextMaterials[1]:nextMaterials.Count>0?nextMaterials[0]:default);nextMaterials[slot]=material!=null?Variant.From(material):default;
        if(Environment(document)&&document.Call("component_kind",id).AsString()=="building"){GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd").Call("request",session,id,next,"Assign building material");return;}
        if(current.Get("materials").AsGodotArray().Count<7&&slot>=5){update(session,id,next,"Assign building material",false,false,new Settings());return;}
        Action(session,"Assign building material",()=>
        {
            root.Get("parameters").AsGodotDictionary()["architecture_source"]=next;foreach(var value in Document(session).Get("components").AsGodotArray())
            {
                var component=value.As<Resource>();var values=component.Get("parameters").AsGodotDictionary();int[] slots=Get(values,"architecture_material_slots",new[]{Get(values,"architecture_material_slot",-1).AsInt32()}).AsInt32Array();if(component.Get("mesh").As<Resource>()==null||owner(session,component)!=root||!slots.Contains(slot))continue;var surfaces=component.Get("surface_materials").AsGodotArray();if(Get(values,"_architecture_manual_material",false).AsBool()||!surfaces.RecursiveEqual(Get(values,"_architecture_materials",surfaces).AsGodotArray())){values["_architecture_manual_material"]=true;continue;}for(int index=0;index<slots.Length;index++)if(slots[index]==slot&&index<surfaces.Count)surfaces[index]=material!=null?Variant.From(material):default;values["_architecture_materials"]=surfaces.Duplicate();
            }
        });
    }
}
