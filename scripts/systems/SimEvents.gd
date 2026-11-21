class_name SimEvents
extends RefCounted
## 시뮬레이션이 내보내는 연출 이벤트 통로 (#21). 서버(시뮬레이션)는 "어디에 무엇이 나왔다"만 알리고,
## 클라이언트가 이 이벤트를 받아 폭발/글자를 그린다. 이벤트는 순수 데이터라서 그대로 네트워크로 보낼 수 있다.
## 이벤트 모양: {"type": "fx_ring"|"fx_text", "lane": 레인 번호(보스 레인은 GameField.BOSS_LANE_ID), "pos": [x, y](셀 단위),
##              "radius"(링) / "text"(글자), "color": "RRGGBB"}
## 레인이 지금 화면에 보이는지는 클라이언트가 정한다 (서버는 보이는지 모른다).

signal emitted(ev: Dictionary)


## 링 이펙트 (원이 퍼진다)
func ring(lane_id: int, pos: Vector2, radius: float, color: Color) -> void:
	emitted.emit({"type": "fx_ring", "lane": lane_id, "pos": [pos.x, pos.y], "radius": radius, "color": color.to_html(false)})


## 떠오르는 글자 (처치 골드, "파괴!", 데미지 숫자 등)
func text(lane_id: int, pos: Vector2, text: String, color: Color) -> void:
	emitted.emit({"type": "fx_text", "lane": lane_id, "pos": [pos.x, pos.y], "text": text, "color": color.to_html(false)})
