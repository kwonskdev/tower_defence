class_name SimRandom
## 시뮬레이션 결과를 바꾸는 랜덤 도우미. 전역 randf()/pick_random() 대신 세션이 들고 있는 RandomNumberGenerator를 넘겨 받아 쓴다.
## 서버만 뽑고 클라이언트는 결과만 받는다 (#21). 시드를 고정하면 같은 판이 그대로 재현된다.
## 화면에서만 쓰는 랜덤(몬스터 흔들림, 데미지 숫자 위치 등)은 여기 쓰지 않고 전역 randf()를 그대로 쓴다.


## 배열에서 하나 고른다 (비어 있으면 null)
static func pick(rng: RandomNumberGenerator, items: Array):
	if items.is_empty():
		return null
	return items[rng.randi_range(0, items.size() - 1)]


## 배열을 제자리에서 섞는다 (Fisher-Yates)
static func shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp
