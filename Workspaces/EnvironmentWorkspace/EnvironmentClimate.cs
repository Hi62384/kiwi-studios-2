using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class EnvironmentClimate : Resource
{
    [Export(PropertyHint.Enum, "Manual,Scene timeline,Automatic")] public int time_mode { get; set; } = 1;
    [Export(PropertyHint.Range, "0.,24.,.01")] public double time_of_day { get; set; } = 9.0;
    [Export(PropertyHint.Range, ".1,86400.,.1")] public double day_length_seconds { get; set; } = 600.0;
    [Export] public double time_speed { get; set; } = 1.0;
    [Export] public double start_time { get; set; } = 8.0;
    [Export] public bool time_paused { get; set; } = false;
    [Export] public double latitude { get; set; } = 45.0;
    [Export] public int date_day { get; set; } = 172;
    [Export(PropertyHint.Enum, "Spring,Summer,Autumn,Winter")] public int season { get; set; } = 1;
    [Export] public double temperature { get; set; } = 18.0;
    [Export(PropertyHint.Range, "0.,1.,.001")] public double humidity { get; set; } = .45;
    [Export(PropertyHint.Range, "0.,1.,.001")] public double cloud_coverage { get; set; } = .15;
    [Export(PropertyHint.Enum, "Clear,Cloudy,Rain,Storm,Snow,Fog,Dust")] public int weather { get; set; } = 0;
    [Export(PropertyHint.Range, "0.,1.,.001")] public double weather_intensity { get; set; } = 0.0;
    [Export] public Vector3 wind_direction { get; set; } = new Vector3(1.0f,0.0f,0.0f);
    [Export(PropertyHint.Range, "0.,250.,.01")] public double wind_speed { get; set; } = 2.0;
    [Export(PropertyHint.Range, "0.,1.,.001")] public double gust_strength { get; set; } = .15;
    [Export(PropertyHint.Range, ".05,3600.,.05")] public double gust_period { get; set; } = 7.0;
    [Export] public double visibility { get; set; } = 10000.0;
    [Export] public double altitude_temperature_lapse { get; set; } = .0065;
    [Export] public bool procedural_weather { get; set; } = false;
    [Export] public int weather_seed { get; set; } = 1;
    [Export(PropertyHint.Range, "1.,86400.,1.")] public double weather_interval { get; set; } = 900.0;
    [Export(PropertyHint.Range, "0.,3600.,.1")] public double weather_transition { get; set; } = 120.0;
    [Export(PropertyHint.Range, "0.,1.,.001")] public double storm_probability { get; set; } = .08;
    [Export(PropertyHint.Range, "0.,1.,.001")] public double rain_probability { get; set; } = .3;
    [Export(PropertyHint.Range, "0.,1.,.001")] public double snow_probability { get; set; } = .12;
    [Export] public Godot.Collections.Array<Settings> schedule { get; set; } = new();
    [Export] public Godot.Collections.Array<Settings> regions { get; set; } = new();
    [Export] public int version { get; set; } = 1;
    private readonly EnvironmentClimateOperations _operations = new();
    public static string[] weather_options() => new[] { "Clear", "Cloudy", "Rain", "Storm", "Snow", "Fog", "Dust" };
    public static string[] season_options() => new[] { "Spring", "Summer", "Autumn", "Winter" };
    public EnvironmentClimate copy_climate() => (EnvironmentClimate)_operations.copy_climate(this);
    public long signature() => _operations.signature(this);
    public string[] validate() => _operations.validate(this);
    public Settings evaluate(Vector3 position, double scene_time) => _operations.evaluate(this, position, scene_time, double.NaN, new Settings());
    public Settings evaluate(Vector3 position, double scene_time, double altitude) => _operations.evaluate(this, position, scene_time, altitude, new Settings());
    public Settings evaluate(Vector3 position, double scene_time, double altitude, Settings overrides) => _operations.evaluate(this, position, scene_time, altitude, overrides);
    public Settings apply_environment(Godot.Environment environment, double scene_time) => _operations.apply_environment(this, environment, scene_time, Vector3.Zero, new Settings());
    public Settings apply_environment(Godot.Environment environment, double scene_time, Vector3 position) => _operations.apply_environment(this, environment, scene_time, position, new Settings());
    public Settings apply_environment(Godot.Environment environment, double scene_time, Vector3 position, Settings overrides) => _operations.apply_environment(this, environment, scene_time, position, overrides);
    public Godot.Environment make_environment(double scene_time) => _operations.make_environment(this, scene_time);
    public Settings _procedural_state(double scene_time) => _operations.procedural_state(this, scene_time);
    public Settings _procedural_pick(long slot) => _operations.procedural_pick(this, slot);
    public Settings _scheduled_state(double scene_time) => _operations.scheduled_state(this, scene_time);
    public Settings _weather_value(int index) => _operations.weather_value(this, index);
    public Settings _scaled_weather(int index, double intensity) => _operations.scaled_weather(this, index, intensity);
    public Settings _blend_weather(Settings from, Settings to) => _operations.blend_weather(from, to, 1);
    public Settings _blend_weather(Settings from, Settings to, double weight) => _operations.blend_weather(from, to, weight);
    public double _region_weight(Settings region, Vector3 point) => _operations.region_weight(region, point);
    public static double point_to_segment(Vector2 point, Vector2 a, Vector2 b) => new EnvironmentClimateOperations().point_to_segment(point, a, b);
}
