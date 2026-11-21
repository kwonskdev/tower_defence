extends RefCounted
class_name GhostArt
## 유령 그림. 플레이어 레인의 작은 유령(Monster)과 보스 레인의 큰 유령(BossController.BossView)이 똑같이 생기도록 한 곳에서 그린다.
## 모양: 흰 시트를 쓴 유령. 머리는 둥글고 아래는 물결치는 치맛자락, 눈이 빼꼼 보이고 두 손으로 입을 가리고 있다.
## 크기는 r(몸통 반지름, 픽셀)로만 정한다: 플레이어 레인은 일반 몬스터와 같은 크기, 보스 레인은 보스 몸통(BOSS_RADIUS)과 같은 크기.
## canvas의 _draw 안에서만 부른다 (CanvasItem의 draw_* 함수를 빌려 쓴다).

const OUTLINE := Color(0.24, 0.26, 0.42)
const BODY := Color(0.97, 0.98, 1.0)
const SHADE := Color(0.78, 0.83, 0.96)
const EYE := Color(0.08, 0.08, 0.18)


## c: 몸통 중심 / r: 몸통 반지름 / t: 흐르는 시간(치맛자락이 일렁인다) / look: 바라보는 방향 / body: 몸 색 (맞았을 때, 길을 뚫을 때 살짝 물든다)
static func draw_ghost(canvas: CanvasItem, c: Vector2, r: float, t: float, look: Vector2 = Vector2.DOWN, body: Color = BODY) -> void:
	var w := clampf(r * 0.07, 1.5, 6.0)  # 윤곽선 굵기
	var sil := _silhouette(c, r, t)

	# 몸통 + 오른쪽 아래 그늘 + 윤곽선
	canvas.draw_colored_polygon(sil, body)
	canvas.draw_arc(c + Vector2(r * 0.1, r * 0.1), r * 0.8, -0.3, 1.3, 16, SHADE, w * 1.6)
	var outline := sil.duplicate()
	outline.append(sil[0])
	canvas.draw_polyline(outline, OUTLINE, w)

	# 눈: 바라보는 쪽으로 살짝 쏠린다
	var dir := look.normalized() if look.length() > 0.01 else Vector2.DOWN
	for side in [-1.0, 1.0]:
		var e: Vector2 = c + Vector2(side * r * 0.32, -r * 0.2) + dir * r * 0.05
		canvas.draw_circle(e, r * 0.13, EYE)
		canvas.draw_circle(e + Vector2(-r * 0.04, -r * 0.05), r * 0.04, Color.WHITE)  # 반짝임

	# 두 손으로 입을 가린다 (살짝 까딱인다)
	var bob := sin(t * 3.0) * r * 0.03
	for side in [-1.0, 1.0]:
		var h: Vector2 = c + Vector2(side * r * 0.2, r * 0.42 + bob)
		canvas.draw_circle(h, r * 0.25, body)
		canvas.draw_arc(h, r * 0.25, 0.0, TAU, 16, OUTLINE, w)
		for k in [-1.0, 1.0]:  # 손가락 두 개
			var f: Vector2 = h + Vector2(k * r * 0.08, -r * 0.2)
			canvas.draw_line(f, f + Vector2(0.0, r * 0.12), OUTLINE, maxf(1.0, w * 0.7))


## 몸 윤곽: 윗머리 반원(왼쪽 -> 위 -> 오른쪽) + 오른쪽에서 왼쪽으로 물결치는 치맛자락. x가 한 방향으로만 가서 겹치지 않는 단순한 다각형이다.
static func _silhouette(c: Vector2, r: float, t: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(13):
		var a := PI + PI * i / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	for i in range(1, 25):
		var u := i / 24.0
		pts.append(c + Vector2(lerpf(r, -r, u), r * (1.05 + 0.14 * cos(u * TAU * 3.0 + t * 4.0))))
	return pts
