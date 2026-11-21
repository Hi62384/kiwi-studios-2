using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using GArray=Godot.Collections.Array;

public partial class ModelSessionEdits
{
    private static Godot.Collections.Array<string> Roots(Dictionary<string,Resource> lookup,IEnumerable<string> ids)
    {var chosen=ids.ToArray();return new Godot.Collections.Array<string>(chosen.Where(id=>!chosen.Any(other=>ModelDocumentOperations.Descendant(lookup,id,other))));}
    private static void FilterComponents(Resource document,Func<Resource,bool> keep)
    {var source=document.Get("components").AsGodotArray();var filtered=source.Duplicate(false);filtered.Clear();foreach(Variant value in source)if(keep(value.As<Resource>()))filtered.Add(value);document.Set("components",filtered);}
    public void duplicate_selected(RefCounted owner,bool preview)
    {
        void Duplicate()
        {
            var document=Doc(owner);var lookup=ModelDocumentOperations.Lookup(document);var selected=Selected(owner);string[] roots=selected.ToArray();var mapping=new Godot.Collections.Dictionary();var copies=new List<Resource>();
            foreach(Variant value in document.Get("components").AsGodotArray())
            {var item=value.As<Resource>();string id=Text(item,"id");if(!selected.Contains(id)&&!roots.Any(root=>ModelDocumentOperations.Descendant(lookup,id,root)))continue;var copy=_components.copy_component(item,true);copy.Set("title",Text(copy,"title")+" copy");mapping[id]=copy.Get("id");copies.Add(copy);}
            var components=document.Get("components").AsGodotArray();foreach(var copy in copies){_remap.component(copy,mapping);if(mapping.TryGetValue(Text(copy,"parent_id"),out var parent))copy.Set("parent_id",parent);components.Add(copy);}
            selected.Clear();foreach(string id in roots)if(mapping.TryGetValue(id,out var mapped))selected.Add(mapped.AsString());
        }
        if(preview){owner.Call("begin");Duplicate();Changed(owner);}else Action(owner,"Duplicate components",Duplicate);
    }
    public void group_selected(RefCounted owner)
    {
        if(Selected(owner).Count==0)return;Action(owner,"Group components",()=>
        {
            var document=Doc(owner);var lookup=ModelDocumentOperations.Lookup(document);var group=EmptyComponent();string groupId=Guid.NewGuid().ToString("N");group.Set("id",groupId);group.Set("title","Group");var roots=new List<Resource>();var worlds=new Dictionary<string,Transform3D>();Vector3 center=Vector3.Zero;
            foreach(string id in Roots(lookup,Selected(owner))){if(!lookup.TryGetValue(id,out var item))continue;roots.Add(item);var pose=ModelDocumentOperations.WorldTransform(lookup,item);worlds[id]=pose;center+=pose.Origin;}
            var transform=new Transform3D(Basis.Identity,center/Math.Max(1,roots.Count));group.Set("transform",transform);document.Get("components").AsGodotArray().Add(group);
            foreach(var item in roots){item.Set("parent_id",groupId);item.Set("transform",transform.AffineInverse()*worlds[Text(item,"id")]);}
            var selected=Selected(owner);selected.Clear();selected.Add(groupId);ResetElements(owner);
        });
    }
    public void parent_selected(RefCounted owner,bool unparent)
    {
        var target=Primary(owner);if(target==null)return;var ids=new Godot.Collections.Array<string>(Selected(owner));if(!unparent)ids.Remove(Text(target,"id"));owner.Call("reparent_components",ids,unparent?"":Text(target,"id"));
    }
    public bool can_reparent(RefCounted owner,Godot.Collections.Array<string> ids,string parentId)
    {
        var lookup=ModelDocumentOperations.Lookup(Doc(owner));lookup.TryGetValue(parentId,out var target);if(parentId.Length>0&&(target==null||!ModelDocumentOperations.Accessible(lookup,target,true)))return false;bool changes=false;var roots=Roots(lookup,ids);
        foreach(string id in ids)
        {if(!lookup.TryGetValue(id,out var item)||!ModelDocumentOperations.Accessible(lookup,item,true)||id==parentId||ModelDocumentOperations.Descendant(lookup,parentId,id))return false;if(roots.Contains(id))changes|=Text(item,"parent_id")!=parentId;}
        return changes;
    }
    public Godot.Collections.Array<string> _reparent_roots(RefCounted owner,Godot.Collections.Array<string> ids)=>Roots(ModelDocumentOperations.Lookup(Doc(owner)),ids);
    public void reparent_components(RefCounted owner,Godot.Collections.Array<string> ids,string parentId)
    {
        if(!owner.Call("can_reparent",ids,parentId).AsBool())return;var lookup=ModelDocumentOperations.Lookup(Doc(owner));var roots=Roots(lookup,ids);var worlds=new Dictionary<string,Transform3D>();foreach(string id in roots)worlds[id]=ModelDocumentOperations.WorldTransform(lookup,lookup[id]);
        Transform3D inverse=lookup.TryGetValue(parentId,out var target)?ModelDocumentOperations.WorldTransform(lookup,target).AffineInverse():Transform3D.Identity;
        Action(owner,parentId.Length==0?"Unparent components":"Parent components",()=>
        {var current=ModelDocumentOperations.Lookup(Doc(owner));foreach(string id in roots)if(current.TryGetValue(id,out var item)){item.Set("parent_id",parentId);item.Set("transform",inverse*worlds[id]);}owner.Set("mode","Object");ResetElements(owner);});
    }
    public string delete_selected(RefCounted owner)
    {
        if(owner.Get("mode").AsString()!="Object")return owner.Get("elements").AsInt32Array().Length>0?owner.Call("edit_mesh","Delete").AsString():"";var selected=Selected(owner);
        foreach(Variant value in Doc(owner).Get("components").AsGodotArray())
        {
            var item=value.As<Resource>();var growth=item.Get("growth").As<Resource>();if(growth!=null&&selected.Contains(Text(growth,"source_id"))&&!selected.Contains(Text(item,"id")))return "Delete or convert dependent surface growth first, or select it with its source.";
            if(selected.Contains(Text(item,"skeleton_id"))&&!selected.Contains(Text(item,"id")))return "Detach this armature's meshes first, or select them together with the armature for deletion.";
        }
        Action(owner,"Delete components",()=>
        {
            selected=Selected(owner);var document=Doc(owner);var lookup=ModelDocumentOperations.Lookup(document);foreach(var item in lookup.Values)if(selected.Contains(Text(item,"parent_id"))&&!selected.Contains(Text(item,"id"))){item.Set("transform",ModelDocumentOperations.WorldTransform(lookup,item));item.Set("parent_id","");}
            FilterComponents(document,item=>!selected.Contains(Text(item,"id"))||item.Get("locked").AsBool());selected.Clear();ResetElements(owner);
        });return "";
    }
    public void join_selected(RefCounted owner)
    {
        var target=Primary(owner);var selected=Selected(owner);if(target==null||selected.Count<2)return;var initial=ModelDocumentOperations.Lookup(Doc(owner));
        foreach(string id in selected)if(!initial.TryGetValue(id,out var item)||item.Get("is_skeleton").AsBool()||item.Get("skin_mesh").As<Mesh>()!=null||item.Get("binding").As<Resource>()!=null||item.Get("growth").As<Resource>()!=null)return;
        Action(owner,"Join meshes",()=>
        {
            selected=Selected(owner);var document=Doc(owner);var lookup=ModelDocumentOperations.Lookup(document);Transform3D world=ModelDocumentOperations.WorldTransform(lookup,target);var mesh=new KiwiModelMesh();var materials=new Godot.Collections.Array<Material>();var worlds=lookup.ToDictionary(pair=>pair.Key,pair=>ModelDocumentOperations.WorldTransform(lookup,pair.Value));
            foreach(string id in selected)
            {
                var item=lookup[id];var source=item.Get("mesh").As<Resource>();if(source==null)continue;int offset=materials.Count;var slots=item.Get("surface_materials").AsGodotArray().Duplicate(false);int highest=0;foreach(int index in source.Get("materials").AsInt32Array())highest=Math.Max(highest,index);while(slots.Count<=highest)slots.Add(default(Variant));
                using var evaluated=_modifiers.evaluate(item);_meshes.append_mesh(mesh,evaluated,world.AffineInverse()*worlds[id],offset);foreach(Variant material in slots)materials.Add(material.As<Material>()!);
            }
            target.Set("mesh",mesh);target.Set("surface_materials",materials);target.Get("modifiers").AsGodotArray().Clear();target.Set("generator","");var visited=new HashSet<string>();
            while(selected.Contains(Text(target,"parent_id"))){string parent=Text(target,"parent_id");if(!visited.Add(parent)){target.Set("parent_id","");break;}target.Set("parent_id",lookup.TryGetValue(parent,out var ancestor)?Text(ancestor,"parent_id"):"");}
            target.Set("transform",worlds.TryGetValue(Text(target,"parent_id"),out var parentWorld)?parentWorld.AffineInverse()*world:world);string targetId=Text(target,"id");
            foreach(var item in lookup.Values)if(item!=target&&selected.Contains(Text(item,"parent_id"))&&Text(item,"parent_id")!=targetId){item.Set("parent_id",targetId);item.Set("transform",world.AffineInverse()*worlds[Text(item,"id")]);}
            FilterComponents(document,item=>!selected.Contains(Text(item,"id"))||item==target);selected.Clear();selected.Add(targetId);ResetElements(owner);
        });
    }
}
