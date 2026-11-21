class_name KiwiPowderSolver
extends RefCounted
## CPU XPBD unilateral sphere contacts, Coulomb positional friction and breakable bonds.
## The adapter supplies time, boundary queries and reactions; no live physics nodes.
const MAX_PAIRS:=1000000
const MAX_BONDS_PER_ACTOR:=65536
var positions:=PackedVector3Array()
var previous:=PackedVector3Array()
var velocities:=PackedVector3Array()
var radii:=PackedFloat32Array()
var masses:=PackedFloat32Array()
var inverse_masses:=PackedFloat32Array()
var owners:=PackedInt32Array()
var slots:=PackedInt32Array()
var contacts:=PackedInt32Array()
var batches: Array[Dictionary]=[]
var pairs:=PackedInt32Array()
var lambdas:=PackedFloat32Array()
var checks:=0
var elapsed_usec:=0
var error:=""

func solve(input: Array[Dictionary],collide: Callable,reaction: Callable,prepare: Callable=Callable()) -> void:
	_native_solver().solve(self,input,collide,reaction,prepare)

func _prune_bonds() -> void:
	_native_solver().prune_bonds(self)

func _neighbors(max_radius: float) -> bool:
	return _native_solver().neighbors(self,max_radius)

func _contact(pair: int,iterations: int,substeps: int,count_contact: bool) -> void:
	_native_solver().contact(self,pair,iterations,substeps,count_contact)

func _boundary(i: int,hit: Dictionary,h: float,reaction: Callable,count_contact: bool) -> void:
	_native_solver().boundary(self,i,hit,h,reaction,count_contact)

func _reaction(callback: Callable,i: int,hit: Dictionary,correction: Vector3,h: float) -> void:
	_native_solver().reaction(self,callback,i,hit,correction,h)

func _velocity_contact(pair: int,incoming: PackedVector3Array) -> void:
	_native_solver().velocity_contact(self,pair,incoming)


static func _native_solver() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","powder_solver")
static func _invoke_prepare(callback: Callable,fraction: float) -> void:
	if callback.is_valid(): callback.call(fraction)
static func _invoke_reaction(callback: Callable,hit: Dictionary,impulse: Vector3,displacement: Vector3) -> void:
	if callback.is_valid(): callback.call(hit,impulse,displacement)
static func _invoke_collision(callback: Callable,id: String,from: Vector3,to: Vector3,radius: float,h: float) -> Dictionary:
	return callback.call(id,from,to,radius,h)
