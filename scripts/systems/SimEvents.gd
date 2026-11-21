class_name SimEvents
extends RefCounted
## 시뮬레이션이 내보내는 연출 이벤트 통로 (#21). 서버(시뮬레이션)는 "어디에 무엇이 나왔다"만 알리고,
## 클라이언트가 이 이벤트를 받아 폭발/글자를 그린다. 이벤트는 순수 데이터라서 그대로 네트워크로 보낼 수 있다.
## 이벤트 모양: {"type": "fx_ring"|"fx_text", "lane": 레인 번호(보스 레인은 GameField.BOSS_LANE_ID), "pos": [x, y](셀 단위),
##              "radius"(링) / "text"(글자), "color": "RRGGBB"}
##          {"type": "fx_shot", "lane", "from": [x, y], "target": 몬스터 번호(없으면 -1), "dest": [x, y], "style", "speed", "color", "pierce": bool}  투사체를 쐈다
##          {"type": "fx_cloud", "lane", "pos": [x, y], "radius", "life", "color"}  표식 구름이 깔렸다
##          {"type": "skill_announced", "info": {name, text, lane, delay, boss}}  보스 스킬 배너. delay>0이면 그 시간 뒤 발동
## 레인이 지금 화면에 보이는지는 클라이언트가 정한다 (서버는 보이는지 모른다).

signal emitted(ev: Dictionary)


## 보스 스킬을 HUD 배너로 알린다
func announce(info: Dictionary) -> void:
	emitted.emit({"type": "skill_announced", "info": info})


## 투사체를 쐈다 (피해는 서버가 처리하고, 클라이언트는 날아가는 모습만 그린다)
func shot(lane_id: int, from: Vector2, target_id: int, dest: Vector2, style: String, speed: float, color: Color, pierce: bool) -> void:
	emitted.emit({"type": "fx_shot", "lane": lane_id, "from": [from.x, from.y], "target": target_id, "dest": [dest.x, dest.y],
		"style": style, "speed": speed, "color": color.to_html(false), "pierce": pierce})


## 표식 구름이 깔렸다
func cloud(lane_id: int, pos: Vector2, radius: float, life: float, color: Color) -> void:
	emitted.emit({"type": "fx_cloud", "lane": lane_id, "pos": [pos.x, pos.y], "radius": radius, "life": life, "color": color.to_html(false)})


## 링 이펙트 (원이 퍼진다)
func ring(lane_id: int, pos: Vector2, radius: float, color: Color) -> void:
	emitted.emit({"type": "fx_ring", "lane": lane_id, "pos": [pos.x, pos.y], "radius": radius, "color": color.to_html(false)})


## 떠오르는 글자 (처치 골드, "파괴!", 데미지 숫자 등)
func text(lane_id: int, pos: Vector2, text: String, color: Color) -> void:
	emitted.emit({"type": "fx_text", "lane": lane_id, "pos": [pos.x, pos.y], "text": text, "color": color.to_html(false)})
