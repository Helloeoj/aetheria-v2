extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
 if not ok:
  failures += 1
  printerr("FAIL: ", label)
func _ready() -> void:
 call_deferred("run")
func run() -> void:
 var rules = load("res://scripts/player_recovery.gd")
 if rules == null:
  printerr("FAIL: recovery service missing")
  get_tree().quit(1)
  return
 var p := PlayerState.new("Recovery test")
 var w := WorldState.new(p)
 var a := CombatActor.new().configure({"entity_id":p.entity_id,"max_hp":p.get_max_hp(),"hp":0})
 w.register_player_actor(a)
 check(not rules.advance(w,p,0.1),"starts downed without immediate respawn")
 check(not a.can_move() and not a.can_attack(),"downed cannot move or fight")
 check(not rules.advance(w,p,29.8),"still revivable before 30 seconds")
 check(rules.revive(w,p,25),"trusted revival before deadline")
 check(a.is_alive and a.hp == 25 and p.current_hp == 25,"revival restores actor and player in place")
 check(p.downed_elapsed == 0.0,"revival cancels timer")
 a.hp=0
 a.is_alive=false
 check(not rules.advance(w,p,29.99),"second death gets its own window")
 var saved := CharacterCodec.encode(p,"golem")
 var decoded := CharacterCodec.decode(saved,p.name,p.entity_id)
 check(decoded.ok and is_equal_approx(decoded.player.downed_elapsed,29.99),"save retains downed timer")
 check(rules.advance(w,p,0.01),"respawn required exactly at 30 seconds")
 check(not rules.revive(w,p,25),"revival rejected at expired deadline")
 var legacy := saved.duplicate(true)
 legacy.erase("downed_elapsed")
 check(CharacterCodec.decode(legacy,p.name,p.entity_id).ok,"older dead save remains loadable")
 var corrupt := saved.duplicate(true)
 corrupt.downed_elapsed=31.0
 check(not CharacterCodec.decode(corrupt,p.name,p.entity_id).ok,"invalid timer rejected")
 rules.restore(p)
 check(p.current_hp==p.get_max_hp() and p.downed_elapsed==0.0,"respawn restores full health and clears timer")
 var region_script = load("res://network/authoritative_region.gd")
 if region_script == null:
  get_tree().quit(1)
  return
 var r = region_script.new()
 r.configure("golem",null)
 r.add_player(p.entity_id,p)
 var ra: CombatActor=r.world.combat.actors[p.entity_id]
 ra.hp=0
 ra.is_alive=false
 for i in 30: r.advance(1.0)
 check(p.current_hp==0 and p.downed_elapsed + 0.0000001 >= 30.0,"authority advances downed clock")
 check(not r.submit(p.entity_id,{"type":"move","direction":[1,0]}).ok,"dead command rejected")
 print("Recovery smoke: ",failures," failures")
 get_tree().quit(0 if failures==0 else 1)
