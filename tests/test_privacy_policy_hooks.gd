extends "res://tests/case_base.gd"
## 이슈 #27: 메인 메뉴의 방침/삭제 요청/신고 링크와 1인 플레이, 닉네임 금칙어 연결, 안드로이드 권한.
##  [1] 메인 메뉴에 링크 3개가 있고, 링크가 비어 있거나 열 수 없어도 [혼자 하기]는 그대로 눌린다 (오프라인에서도 막히지 않는다)
##  [2] 삭제 요청/신고 경로(메일)가 채워져 있다
##  [3] 닉네임 금칙어는 #25의 Nicknames.is_clean/BannedWords가 맡는다 (여기서 중복 구현하지 않는다): 금칙어는 걸리고 자동 생성 이름은 안 걸린다
##  [4] export_presets.cfg(추적됨)에 INTERNET 권한이 켜져 있다
## (실제 메일 앱/브라우저가 열리는지는 폰에서 눈으로 봐야 한다)


func run() -> void:
	await get_tree().process_frame  # run()에 await가 하나도 없으면 finished가 실행기보다 먼저 나가 버린다
	var m := MainMenu.new()
	m.profile_path = "user://test_privacy_hooks.cfg"
	add_child(m)
	var links := _link_texts(m)
	check(links.has("개인정보처리방침") and links.has("데이터 삭제 요청") and links.has("닉네임 신고"), "메뉴에 방침/삭제 요청/신고 링크 3개 (찾은 것: %s)" % str(links))
	check(m.open_link("") == false, "빈 링크는 안내만 보이고 아무 일도 없다")
	check(m.status_label.text.find(MainMenu.SUPPORT_EMAIL) != -1, "안내에 메일 주소가 보인다")
	check(MainMenu.DELETION_REQUEST_URL != "" and MainMenu.REPORT_URL != "", "삭제 요청/신고 경로가 있다")
	var solo_ok := [false]
	m.solo_chosen.connect(func(): solo_ok[0] = true)
	m.solo_button.pressed.emit()
	check(solo_ok[0], "링크와 상관없이 [혼자 하기]가 된다")
	m.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_privacy_hooks.cfg"))

	check(not Nicknames.is_clean("씨발") and not Nicknames.is_clean("FuCk유"), "금칙어 닉네임은 걸린다 (#25 BannedWords)")
	var gen_ok := true
	for adj in Nicknames.ADJECTIVES:
		for noun in Nicknames.NOUNS:
			if not Nicknames.is_clean(str(adj) + str(noun)):
				gen_ok = false
	check(gen_ok, "자동 생성 이름 조합은 금칙어에 걸리지 않는다")

	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	check(presets.find("permissions/internet=true") != -1 and presets.find("permissions/internet=false") == -1, "INTERNET 권한이 켜져 있다")


func _link_texts(node: Node) -> Array:
	var out := []
	if node is LinkButton:
		out.append((node as LinkButton).text)
	for c in node.get_children():
		out.append_array(_link_texts(c))
	return out
