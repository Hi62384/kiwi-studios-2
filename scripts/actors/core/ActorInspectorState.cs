using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorInspectorState : Resource
{
    [Export] public Settings actor_states { get; set; } = new();
    private readonly ActorInspectorStateOperations _operations = new();
    public void restore_from(ActorInspectorState? other) => _operations.restore_from(this, other);
    public double scroll_for(string actor_id) => _operations.scroll_for(this, actor_id);
    public void set_scroll(string actor_id, double value) => _operations.set_scroll(this, actor_id, value);
    public string main_tab_for(string actor_id) => _operations.main_tab_for(this, actor_id);
    public void set_main_tab(string actor_id, string value) => _operations.set_main_tab(this, actor_id, value);
    public string section_for(string actor_id, string main_tab) => _operations.section_for(this, actor_id, main_tab);
    public void set_section(string actor_id, string main_tab, string section) => _operations.set_section(this, actor_id, main_tab, section);
    public double page_scroll_for(string actor_id, string main_tab, string section) => _operations.page_scroll_for(this, actor_id, main_tab, section);
    public void set_page_scroll(string actor_id, string main_tab, string section, double value) => _operations.set_page_scroll(this, actor_id, main_tab, section, value);
    public bool category_expanded(string actor_id, string category) => _operations.category_expanded(this, actor_id, category);
    public void set_category_expanded(string actor_id, string category, bool expanded) => _operations.set_category_expanded(this, actor_id, category, expanded);
    public bool vector_linked(string actor_id, StringName property_id) => _operations.vector_linked(this, actor_id, property_id);
    public void set_vector_linked(string actor_id, StringName property_id, bool linked) => _operations.set_vector_linked(this, actor_id, property_id, linked);
    public Settings _actor_state(string actor_id) => _operations.actor_state(this, actor_id);
    public void _set_actor_value(string actor_id, string key, Variant value) => _operations.set_actor_value(this, actor_id, key, value);
}
