extends SceneTree

var failures := 0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for amount in [.8,1.0]:
		for profile in ["oval","noisy oval","organic"]:
			check_profile(amount,profile)
	print("High-scale correction checks: %d failures" % failures)
	quit(failures)

func check_profile(amount: float,profile: String) -> void:
	for scale in [4.0,8.0,16.0]:
		var corrector := KiwiStrokeCorrector.new()
		corrector.begin(Vector2(150,0),amount,4,0,scale)
		var worst_turn := 0.0
		var worst_jump := 0.0
		var debug_kink:=""
		for step in range(1,601):
			var angle := step/600.0*PI*1.75
			var point:=Vector2(cos(angle)*150,sin(angle)*90)
			if profile=="noisy oval": point*=1.0+sin(step*1.7)*.004
			elif profile=="organic": point*=1.0+.12*sin(angle*3.0)
			corrector.add(point,step/120.0)
			corrector.update()
			var previous_turn := 0.0
			for i in range(5,corrector.knots.size()-5):
				var a := corrector.knots[i]-corrector.knots[i-1]
				var b := corrector.knots[i+1]-corrector.knots[i]
				var turn := a.angle_to(b)
				if absf(turn)>worst_turn:
					worst_turn=absf(turn)
					debug_kink="step %s knot %s/%s corner %s raw %s fitted %s neighbors %s %s" % [step,i,corrector.knots.size(),corrector.corners[i],corrector._raw(i),corrector.knots[i],a,b]
				if i>5: worst_jump=maxf(worst_jump,absf(turn-previous_turn))
				previous_turn=turn
		print("%s strength %s scale %s: largest turn %.3f; curvature jump %.3f" % [profile,amount,scale,worst_turn,worst_jump])
		if worst_turn>.65 or worst_jump>.4:
			print(debug_kink)
			failures+=1; push_error("High-scale correction introduces kinks on %s at strength %s scale %s" % [profile,amount,scale])
