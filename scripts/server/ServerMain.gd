extends Node
class_name ServerMain
## UI 없이 시뮬레이션만 돌리는 서버 진입점. `--headless --server`로 시작하면 MainGame 화면을 만들지 않고 세션만 연다 (#21).
## 지금은 한 프로세스 안에서 돈다. 네트워크는 #20 이후에 이 위에 얹는다 (스냅샷/이벤트는 CommandBus 결과와 같은 모양으로).
##
## 인자 (모두 선택):
##   --server            서버 모드 (Boot가 이것을 보고 이 노드를 띄운다)
##   --players=N         참여 인원 1~8 (기본 1)
##   --seed=N            시뮬레이션 랜덤 시드. 주지 않으면 매번 다른 판
##   --time-scale=N      게임 속도 배율 (기본 1). 테스트로 빨리 끝낼 때
##   --bot               자동 플레이어를 붙인다 (참여자 모두). 사람 없이 한 판을 끝까지 돌릴 때
## 한 판이 끝나면 결과를 로그에 한 줄 남기고 종료한다 (승리 0, 패배 1).

signal finished(victory: bool, info: Dictionary)

var session := Session.new()
var field: GameField
var result := {}   # 끝난 뒤의 요약. {victory, boss_level, reason}


## 이 프로세스를 서버로 시작해야 하는가
static func requested() -> bool:
	return "--server" in OS.get_cmdline_args() or "--server" in OS.get_cmdline_user_args()


## "--name=값" 인자의 값 (없으면 fallback)
static func arg_value(name: String, fallback: String = "") -> String:
	var prefix := "--%s=" % name
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback


func _ready() -> void:
	var players := clampi(int(arg_value("players", "1")), 1, Balance.MAX_PLAYERS)
	session.participants.clear()
	for i in range(players):
		session.participants.append(i)
	var seed_text := arg_value("seed")
	if seed_text != "":
		session.rng.seed = int(seed_text)
	Engine.time_scale = maxf(0.1, float(arg_value("time-scale", "1")))
	Log.info(Log.Category.GAME, "서버 시작: 참여 %d명, 시드 %s, 배속 x%s" % [players, seed_text if seed_text != "" else "(무작위)", Engine.time_scale])

	field = (load("res://scenes/ui/GameField.tscn") as PackedScene).instantiate() as GameField
	field.session = session
	add_child(field)
	field.boss_ready.connect(_on_boss_ready, CONNECT_ONE_SHOT)


func _on_boss_ready(boss: BossController) -> void:
	boss.boss_defeated.connect(func(): _finish(true, boss, ""))
	boss.boss_failed.connect(func(reason: String): _finish(false, boss, reason))
	if "--bot" in OS.get_cmdline_args() or "--bot" in OS.get_cmdline_user_args():
		for pid in session.participants:
			var bot := AutoPlayer.new()
			add_child(bot)
			bot.setup(field.bus, pid)
	var started := field.bus.execute(Command.make(Command.START_GAME, session.local_player_id, {}))
	if not started["ok"]:
		Log.warn(Log.Category.GAME, "서버 시작 실패: %s" % started["reason"])
		_finish(false, boss, started["reason"])


func _finish(victory: bool, boss: BossController, reason: String) -> void:
	if not result.is_empty():
		return
	result = {"victory": victory, "boss_level": boss.level, "reason": reason}
	Log.info(Log.Category.GAME, "서버 한 판 끝: %s (보스 Lv.%d)%s" % ["승리" if victory else "패배", boss.level, "" if reason == "" else " - " + reason])
	finished.emit(victory, result)
	if requested():  # 테스트가 이 노드를 직접 만든 경우에는 프로세스를 끝내지 않는다
		get_tree().quit(0 if victory else 1)
