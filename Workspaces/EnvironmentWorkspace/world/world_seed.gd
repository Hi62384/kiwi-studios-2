extends RefCounted
## Reseed linked defaults, retaining authored points and explicit local seeds.
static func apply(source: Resource,seed: int) -> Resource:
	var next: Resource=source.copy(); var previous:=int(source.seed); next.seed=seed
	for index in next.settlements.size():
		var settlement: Dictionary=next.settlements[index]; var recipe:=str(settlement.id).begins_with("recipe:"); var old_default:=hash([previous,index]) if recipe else hash([previous,settlement.id]); var replacement:=hash([seed,index]) if recipe else hash([seed,settlement.id])
		if int(settlement.get("seed",old_default))==old_default: settlement.seed=replacement
		for district: Dictionary in settlement.get("districts",[]):
			if int(district.get("seed",previous))==previous: district.seed=seed
	for index in next.forests.size():
		var forest: Dictionary=next.forests[index]; var old_default: int=previous+index*101
		if int(forest.seed)!=old_default: continue
		var replacement: int=seed+index*101; forest.seed=replacement
		for variant: Dictionary in forest.get("variants",[]):
			if int(variant.settings.get("seed",0))==hash([old_default,variant.layer,variant.kind]): variant.settings.seed=hash([replacement,variant.layer,variant.kind])
	for rule: Dictionary in next.prop_rules:
		if int(rule.get("seed",previous))==previous: rule.seed=seed
	for region: Dictionary in next.regions:
		if int(region.get("seed",0))==hash([previous,region.id]): region.seed=hash([seed,region.id])
	return next
