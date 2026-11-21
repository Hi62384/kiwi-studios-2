using Godot;
using System;
using System.Linq;
using System.Collections.Generic;

public partial class ModelSessionEdits
{
    public string edit_mesh(RefCounted owner,string kind,double amount,bool preview)
    {
        var item=Primary(owner);if(item==null||item.Get("mesh").As<Resource>() is not Resource mesh||item.Get("locked").AsBool())return "Select an unlocked mesh first.";
        if(item.Get("skin_mesh").As<Mesh>()!=null||item.Get("binding").As<Resource>()!=null)return "Bound mesh geometry is preserved. Detach it in Rigging before editing topology.";
        string mode=owner.Get("mode").AsString();int[] elements=owner.Get("elements").AsInt32Array(),chosen=(int[])elements.Clone();var selectedSet=new HashSet<int>(elements);Resource? result=null;
        switch(kind)
        {
            case "Extrude":case "Extrude individual":case "Inset":
                if(mode!="Face"||elements.Length==0)return "Select faces first (4).";var output=kind=="Inset"?_geometry.inset(mesh,elements,amount):_geometry.extrude(mesh,elements,amount,kind=="Extrude individual");result=output["mesh"].As<Resource>();chosen=output["selection"].AsInt32Array();break;
            case "Subdivide":result=mode=="Edge"&&elements.Length>0?_geometry.subdivide_edges(mesh,elements):_geometry.subdivide(mesh,mode=="Face"?elements:Array.Empty<int>());break;
            case "Bevel":
            {
                var edges=mode=="Edge"?elements.ToList():new List<int>();if(mode=="Face"&&elements.Length>0){var topology=_meshes.edges(mesh);for(int i=0;i<topology.Count;i++)if(topology[i]["faces"].AsInt32Array().Any(selectedSet.Contains))edges.Add(i);}
                result=_geometry.bevel(mesh,edges.ToArray(),amount);if(result==null)return "Bevel currently supports convex meshes with up to 64 clipping planes.";break;
            }
            case "Weld":result=_geometry.weld(mesh,amount);break;
            case "Smooth":result=_geometry.smooth_mesh(mesh,amount,1);break;
            case "Flip normals":
            {
                result=_meshes.copy_mesh(mesh);var faces=result.Get("faces").AsGodotArray();var uv=result.Get("uv").AsGodotArray();
                for(int f=0;f<faces.Count;f++)if(elements.Length==0||mode!="Face"||selectedSet.Contains(f)){int[] indices=faces[f].AsInt32Array();Vector2[] coordinates=uv[f].AsVector2Array();Array.Reverse(indices);Array.Reverse(coordinates);faces[f]=indices;uv[f]=coordinates;}break;
            }
            case "Delete":
            {
                var removed=new List<int>();var vertices=new HashSet<int>(selected_vertices(owner));var faces=mesh.Get("faces").AsGodotArray();for(int f=0;f<faces.Count;f++){if(mode=="Face"&&selectedSet.Contains(f))removed.Add(f);else if(mode!="Face"&&faces[f].AsInt32Array().Any(vertices.Contains))removed.Add(f);}
                result=_geometry.remove_faces(mesh,removed.ToArray());chosen=Array.Empty<int>();break;
            }
        }
        if(result==null)return "Unsupported operation.";
        if(result.Get("faces").AsGodotArray().Count==0&&mesh.Get("faces").AsGodotArray().Count>0&&kind!="Delete")return "Operation would remove the mesh. Use a smaller amount.";
        string[] errors=_meshes.validate(result,true);if(errors.Length>0)return "Operation cancelled: "+errors[0];
        void Apply(){item.Set("mesh",result);item.Set("generator","");owner.Set("elements",kind is "Extrude" or "Extrude individual" or "Inset"?chosen:Array.Empty<int>());}
        if(preview){Apply();Changed(owner);}else Action(owner,kind,Apply);return "";
    }
}
