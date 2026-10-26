extends SceneTree
func _initialize()->void:
 var errors:=0
 for name in DirAccess.get_files_at("res://Workspaces/AudioWorkspace"):
  if name.ends_with(".gd"):
   var script=load("res://Workspaces/AudioWorkspace/"+name)
   if script==null or not script.can_instantiate():errors+=1;print("FAIL ",name)
 print("ALL_MODULES failures=",errors);quit(errors)
