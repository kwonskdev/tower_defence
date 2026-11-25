extends "res://tests/case_base.gd"
## 이슈 #24 회귀 테스트: 서버 빌드/호스팅.
##  [1] export 프리셋 "Linux Server"(전용 서버)와 한 줄 빌드/실행 스크립트, 배포 파일(Dockerfile/compose/Caddy/systemd)이 있다
##  [2] 지표: 방 수(대기/진행)/접속자 수/몬스터 수가 RoomHub.stats()와 로그 한 줄(METRICS)에 나온다. /proc 파서
##  [3] 방 코드 서버에서 프로토콜/스냅샷 버전이 다른 클라이언트는 거부되고(서버 버전 포함) 업데이트 안내가 나온다. 서버가 더 낮으면 기다리라고 안내한다
##  [5] 동시 방 수 한도(max_rooms): 넘으면 새 방 만들기는 server_busy로 거부, 기존 방은 그대로, 방이 닫히면 다시 만들 수 있다
##  [6] 유휴 keepalive: 서버가 오래 아무것도 안 보낸 대기방 연결에 작은 메시지를 보낸다 (Cloudflare 유휴 끊김 대비)
##  [7] 테스트용/정식 빌드 구분: 평문(ws://)과 서버 주소 입력은 debug 빌드에서만, 정식(release)은 wss만 / 안드로이드 debug·release 네트워크 보안 설정 파일과 프리셋
##  [4] 암호화: 서버가 직접 wss로 열면 TLS 클라이언트는 방 만들기까지 되고, 평문(ws) 클라이언트는 못 들어온다. 인증서/키 파일로 서버 TLS 설정이 만들어진다
## (실제 Linux 서버/도커/리버스 프록시/폰은 여기서 보지 않는다. docs/server-hosting.md의 확인 목록)

const PORT_BASE := 47430


func run() -> void:
	_files()
	_parsers()
	await _metrics()
	await _version_reject()
	await _wss()
	await _room_limit()
	await _keepalive()
	await _build_gate()
	Engine.time_scale = 1.0


# ---- [1] 빌드/배포 파일 -------------------------------------------------------

func _files() -> void:
	print("[1] export 프리셋과 배포 파일")
	var cfg := ConfigFile.new()
	check(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg를 읽었다")
	var found := ""
	for sec in cfg.get_sections():
		if cfg.get_value(sec, "name", "") == "Linux Server":
			found = sec
	check(found != "", "Linux Server 프리셋이 있다")
	if found != "":
		check(cfg.get_value(found, "platform") == "Linux" and bool(cfg.get_value(found, "dedicated_server")), "플랫폼 Linux, 전용 서버(화면 리소스 제외) 모드")
		check(str(cfg.get_value(found, "export_path", "")).begins_with("build/server/"), "내보내기 경로가 build/server/ 아래 (gitignore 대상)")
		check(cfg.get_value(found + ".options", "binary_format/architecture", "") == "x86_64" and bool(cfg.get_value(found + ".options", "binary_format/embed_pck")), "x86_64, pck 내장(파일 하나)")
	var must := ["tools/server/build.sh", "tools/server/run.sh", "deploy/Dockerfile", "deploy/docker-compose.yml", "deploy/Caddyfile", "deploy/lanewars.service", "deploy/nginx.conf.example", "docs/server-hosting.md"]
	for f in must:
		check(FileAccess.file_exists("res://" + f), "%s 가 있다" % f)
	var compose := FileAccess.get_file_as_string("res://deploy/docker-compose.yml")
	var service := FileAccess.get_file_as_string("res://deploy/lanewars.service")
	check(compose.contains("restart: unless-stopped") and service.contains("Restart=always"), "죽으면 다시 뜬다 (compose 재시작 정책 / systemd Restart=always)")
	check(FileAccess.get_file_as_string("res://deploy/Caddyfile").contains("reverse_proxy"), "TLS 리버스 프록시 예시(Caddy)가 서버로 넘긴다")


# ---- [2] 지표 -----------------------------------------------------------------

func _parsers() -> void:
	print("[2a] /proc 파서")
	# 프로세스 이름에 공백/괄호가 있어도 14/15번째 칸(utime/stime)을 맞게 읽는다
	var stat := "1234 (lane wars (x)) S 1 1234 1234 0 -1 4194560 100 0 0 0 150 50 0 0 20 0 8 0 100 1000 100 18446744073709551615"
	check(ServerMetrics.parse_cpu_ticks(stat) == 200.0, "utime 150 + stime 50 = 200틱 (이름에 공백/괄호가 있어도) (실제 %s)" % ServerMetrics.parse_cpu_ticks(stat))
	check(ServerMetrics.parse_cpu_ticks("깨진 글자") == -1.0, "못 읽으면 -1")
	near(ServerMetrics.parse_rss_mb("Name:\tgodot\nVmRSS:\t  204800 kB\nThreads:\t4\n"), 200.0, "VmRSS 204800kB = 200MB")
	near(ServerMetrics.parse_rss_mb("Name:\tgodot\n"), 0.0, "VmRSS가 없으면 0")


func _server(port: int) -> ServerMain:
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = port
	server.session.participants.clear()
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	return server


func _client(player_name: String, port: int, mode: String, code := "", tls: TLSOptions = null) -> NetClient:
	var cl := NetClient.new()
	cl.player_name = player_name
	cl.join_mode = mode
	cl.join_code = code
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", port, tls)
	return cl


func _settle(cl: NetClient) -> String:
	await wait_until(func(): return cl.is_joined() or cl.state == NetClient.State.REJECTED, 8000)
	return cl.reject_reason


func _metrics() -> void:
	print("[2b] 방 수/접속자 수/몬스터 수 지표")
	var port := PORT_BASE
	var server := await _server(port)
	var hub: RoomHub = server.hub
	var m := ServerMetrics.new()
	m.setup(hub, 0.0)  # 자동 로그는 끄고 직접 report()를 부른다
	server.add_child(m)
	var s0 := hub.stats()
	check(s0.rooms == 0 and s0.conns == 0 and s0.players == 0 and s0.monsters == 0, "처음에는 방 0개, 접속 0명")
	var a := _client("방장", port, NetProtocol.MODE_CREATE)
	await _settle(a)
	var b := _client("친구", port, NetProtocol.MODE_JOIN, a.room_code)
	await _settle(b)
	var c := _client("딴사람", port, NetProtocol.MODE_CREATE)
	await _settle(c)
	var s1 := hub.stats()
	check(s1.rooms == 2 and s1.waiting == 2 and s1.playing == 0 and s1.players == 3 and s1.conns == 3, "방 2개(둘 다 대기), 사람 3명, 연결 3개 (%s)" % [s1])
	b.set_ready(true)
	await wait_until(func(): return a.lobby.get("can_start", false), 5000)
	a.request_start()
	await wait_until(func(): return a.in_game and b.in_game, 8000)
	await frames(10)
	var s2 := hub.stats()
	check(s2.rooms == 2 and s2.playing == 1 and s2.waiting == 1, "한 방이 시작하면 진행 1, 대기 1 (%s)" % [s2])
	var field: GameField = hub.room_for(a.room_code).field
	field.boss.max_hp = 1e15
	field.boss.hp = 1e15
	var lane: LaneController = field.lanes[0]
	for i in range(5):
		lane.gold = 1e9
		field.bus.execute(Command.make(Command.SEND_MONSTER, 0, {"kind_id": "rusher"}))
	check(hub.stats().monsters >= 5, "보스 레인에 보낸 몬스터가 몬스터 수에 잡힌다 (%d)" % hub.stats().monsters)
	await frames(30)
	var logged := []
	var on_log := func(_level, _category, message: String): logged.append(message)
	Log.log_emitted.connect(on_log)
	var rep := m.report()
	Log.log_emitted.disconnect(on_log)
	check(rep.rooms == 2 and rep.players == 3 and rep.conns == 3 and rep.peak_rooms == 2 and rep.peak_conns == 3, "지표 모음에 방/접속자/최대치가 있다")
	check(rep.frame_avg_ms > 0.0 and rep.frame_max_ms >= rep.frame_avg_ms and rep.work_max_ms >= rep.work_avg_ms and rep.mem_mb > 0.0, "프레임/작업 시간과 메모리가 있다 (프레임 %.1f/%.1fms, 작업 %.2f/%.2fms, %.0fMB)" % [rep.frame_avg_ms, rep.frame_max_ms, rep.work_avg_ms, rep.work_max_ms, rep.mem_mb])
	check(logged.any(func(l): return l.begins_with("METRICS rooms=2") and l.contains("players=3") and l.contains("frame_avg=") and l.contains("work_max=")), "로그에 METRICS 한 줄이 남는다 (%s)" % [logged])
	# 방이 닫히면 지표도 줄어든다 (끝난 방을 닫는 규칙은 test_post_game_connection)
	c.close()
	await wait_until(func(): return hub.room_count() == 1, 8000)
	check(hub.stats().rooms == 1, "사람이 다 나간 방이 닫히면 방 수가 줄어든다")
	for cl in [a, b, c]:
		cl.queue_free()
	server.queue_free()
	await frames(4)


# ---- [3] 버전 불일치 ----------------------------------------------------------

func _version_reject() -> void:
	print("[3] 방 코드 서버: 버전이 다른 클라이언트는 업데이트 안내와 함께 거부")
	var port := PORT_BASE + 1
	var server := await _server(port)
	var hub: RoomHub = server.hub
	var old := _client("옛앱", port, NetProtocol.MODE_CREATE)
	old.proto_override = NetProtocol.PROTOCOL_VERSION - 1
	var got := {}
	old.rejected.connect(func(reason, info): got["reason"] = reason; got["info"] = info)
	await wait_until(func(): return not got.is_empty(), 8000)
	check(got.get("reason") == NetProtocol.REJECT_PROTOCOL, "프로토콜이 낮은 클라이언트는 protocol_mismatch로 거부된다 (%s)" % [got.get("reason")])
	check(got.has("info") and got.info.proto == NetProtocol.PROTOCOL_VERSION and got.info.snapshot == Snapshot.VERSION, "거부 메시지에 서버 버전이 있다")
	check(hub.room_count() == 0 and hub.stats().players == 0, "거부된 클라이언트는 방을 만들지 못했다")
	var text := MainMenu.reject_text(got.reason, got.info)
	check(text.contains("업데이트"), "화면 문구가 앱 업데이트를 안내한다 (%s)" % text)
	# 서버가 더 낮은 경우(서버를 아직 못 올렸다): 앱 업데이트가 아니라 기다리라고 안내한다
	var older := MainMenu.reject_text(NetProtocol.REJECT_PROTOCOL, {"proto": NetProtocol.PROTOCOL_VERSION - 1, "snapshot": Snapshot.VERSION})
	check(older.contains("서버") and older.contains("잠시") and not older.contains("업데이트"), "서버가 더 낮으면 기다리라고 안내한다 (%s)" % older)
	check(MainMenu.reject_text(NetProtocol.REJECT_PROTOCOL) == text, "서버 버전을 모르면(info 없음) 앱 업데이트 안내")
	# 스냅샷 버전만 달라도 거부
	var hello_bad := NetProtocol.make_hello("x", NetProtocol.MODE_CREATE)
	hello_bad["snapshot"] = Snapshot.VERSION + 1
	check(NetProtocol.check_hello(hello_bad) == NetProtocol.REJECT_PROTOCOL, "스냅샷 버전만 달라도 거부 판정")
	# 맞는 클라이언트는 같은 서버에 정상 입장한다
	var ok := _client("새앱", port, NetProtocol.MODE_CREATE)
	check(await _settle(ok) == "" and ok.is_joined() and hub.room_count() == 1, "같은 서버에 맞는 버전은 입장한다")
	old.queue_free()
	ok.queue_free()
	server.queue_free()
	await frames(4)


# ---- [4] wss ------------------------------------------------------------------

func _wss() -> void:
	print("[4] 서버가 직접 wss로 열면 TLS 클라이언트만 들어온다")
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var cert := crypto.generate_self_signed_certificate(key, "CN=localhost")
	var cert_path := "user://test_server_cert.crt"
	var key_path := "user://test_server_key.key"
	cert.save(cert_path)
	key.save(key_path)
	check(ServerMain.load_tls(cert_path, key_path) != null, "인증서/키 파일로 서버 TLS 설정이 만들어진다 (--tls-cert/--tls-key)")
	check(ServerMain.load_tls("user://없음.crt", key_path) == null, "인증서 파일이 없으면 null (서버는 네트워크를 열지 않고 끝난다)")
	var port := PORT_BASE + 2
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = port
	server.net_tls = ServerMain.load_tls(cert_path, key_path)
	server.session.participants.clear()
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	var secure := _client("보안", port, NetProtocol.MODE_CREATE, "", TLSOptions.client(cert, "localhost"))
	check(await _settle(secure) == "" and secure.is_joined() and secure.room_code != "", "wss: TLS 클라이언트가 방을 만들고 코드를 받았다 (%s)" % secure.room_code)
	var plain := _client("평문", port, NetProtocol.MODE_CREATE)
	var joined_plain := await wait_until(func(): return plain.is_joined(), 3000)
	check(not joined_plain and server.hub.room_count() == 1, "평문(ws) 클라이언트는 wss 서버에 들어오지 못한다")
	secure.queue_free()
	plain.queue_free()
	server.queue_free()
	await frames(4)


# ---- [5] 동시 방 수 한도 --------------------------------------------------------

func _room_limit() -> void:
	print("[5] 동시 방 수 한도")
	var port := PORT_BASE + 3
	var server := await _server(port)
	var hub: RoomHub = server.hub
	hub.max_rooms = 2
	hub.max_rooms_per_addr = 99   # 한 PC(같은 주소)에서 여러 방을 만든다 (프록시/터널 뒤 설정과 같다)
	var a := _client("방장1", port, NetProtocol.MODE_CREATE)
	var b := _client("방장2", port, NetProtocol.MODE_CREATE)
	check(await _settle(a) == "" and await _settle(b) == "" and hub.room_count() == 2, "한도(2)까지는 방이 만들어진다")
	var c := _client("방장3", port, NetProtocol.MODE_CREATE)
	check(await _settle(c) == NetProtocol.REJECT_BUSY and hub.room_count() == 2, "한도를 넘는 새 방은 server_busy로 거부된다 (%s)" % c.reject_reason)
	check(MainMenu.reject_text(NetProtocol.REJECT_BUSY).contains("가득"), "화면 문구: 서버가 가득 찼습니다")
	var d := _client("빠른시작", port, NetProtocol.MODE_QUICK)
	await wait_until(func(): return d.is_joined() or d.state == NetClient.State.REJECTED, 8000)
	check(d.state == NetClient.State.REJECTED and d.reject_reason == NetProtocol.REJECT_BUSY, "빠른 시작도 새 방이 필요하면 거부된다 (%s)" % d.reject_reason)
	var e := _client("입장", port, NetProtocol.MODE_JOIN, a.room_code)
	check(await _settle(e) == "" and e.is_joined(), "이미 있는 방에는 한도와 상관없이 들어갈 수 있다")
	a.close()
	e.close()
	await wait_until(func(): return hub.room_count() == 1, 8000)
	var f := _client("방장4", port, NetProtocol.MODE_CREATE)
	check(await _settle(f) == "" and hub.room_count() == 2, "방이 닫혀 자리가 나면 새 방을 만들 수 있다")
	for cl in [a, b, c, d, e, f]:
		cl.queue_free()
	server.queue_free()
	await frames(4)


# ---- [6] keepalive --------------------------------------------------------------

func _keepalive() -> void:
	print("[6] 서버 -> 클라이언트 방향이 오래 조용해도 keepalive가 간다")
	var port := PORT_BASE + 4
	var server := await _server(port)
	var a := _client("대기", port, NetProtocol.MODE_CREATE)
	await _settle(a)
	var room := server.hub.room_for(a.room_code)
	check(NetProtocol.KEEPALIVE_SEC < 60.0 and room.keepalive_sec == NetProtocol.KEEPALIVE_SEC, "기본 keepalive는 %.0f초 (Cloudflare 유휴 약 100초보다 짧다)" % NetProtocol.KEEPALIVE_SEC)
	room.keepalive_sec = 0.3
	var before := a.pongs
	await wait_until(func(): return a.pongs >= before + 3, 6000)
	check(a.pongs >= before + 3, "대기방에서 클라이언트가 아무것도 안 보내도 서버가 keepalive를 보낸다 (pong %d -> %d)" % [before, a.pongs])
	check(a.is_joined() and server.hub.room_count() == 1, "keepalive가 연결/방 상태를 바꾸지 않는다")
	a.queue_free()
	server.queue_free()
	await frames(4)


# ---- [7] 테스트용 / 정식 빌드 -----------------------------------------------------

func _build_gate() -> void:
	print("[7] 정식 빌드에서는 평문(ws://)과 서버 주소 입력이 막힌다")
	# 안드로이드 설정 파일: debug는 평문 허용, release는 불허, 매니페스트가 가리킨다
	var dbg := FileAccess.get_file_as_string("res://android/build/src/debug/res/xml/network_security_config.xml")
	var rel := FileAccess.get_file_as_string("res://android/build/src/release/res/xml/network_security_config.xml")
	check(dbg.contains('cleartextTrafficPermitted="true"') and rel.contains('cleartextTrafficPermitted="false"'), "네트워크 보안 설정: debug는 평문 허용, release는 불허 (파일이 따로 있다)")
	check(FileAccess.get_file_as_string("res://android/build/src/main/AndroidManifest.xml").contains('android:networkSecurityConfig="@xml/network_security_config"'), "매니페스트가 network_security_config를 가리킨다")
	var cfg := ConfigFile.new()
	cfg.load("res://export_presets.cfg")
	var android := {}
	for sec in cfg.get_sections():
		if cfg.get_value(sec, "platform", "") == "Android":
			android[cfg.get_value(sec, "name")] = sec
	check(android.has("Android Debug APK") and android.has("Android") and android.has("Android APK"), "안드로이드 프리셋: 테스트용(Android Debug APK)과 정식(Android, Android APK)이 나뉘어 있다")
	var all_internet := true
	for name in android:
		all_internet = all_internet and bool(cfg.get_value(android[name] + ".options", "permissions/internet", false))
	check(all_internet, "모든 안드로이드 프리셋이 INTERNET 권한을 켠다")
	# 코드: 정식 빌드를 흉내 내면 주소 칸이 잠기고 ws:// 는 접속하지 않는다
	check(MainMenu.test_build() == OS.has_feature("debug"), "테스트용 빌드 판정은 OS.has_feature(debug)다")
	var dev := MainMenu.new()
	add_child(dev)
	await frames(2)
	check(dev.server_edit.editable, "테스트용 빌드: 서버 주소 칸을 고칠 수 있다")
	dev.queue_free()
	MainMenu.force_release = true
	var rel_menu := MainMenu.new()
	rel_menu.profile_path = "user://test_menu_release.cfg"
	add_child(rel_menu)
	await frames(2)
	check(not rel_menu.server_edit.editable and rel_menu.server_edit.text == rel_menu.default_server, "정식 빌드: 서버 주소 칸은 잠기고 기본 서버(%s)다" % rel_menu.default_server)
	rel_menu.server_edit.text = "192.168.0.10:47300"   # 코드로 바꿔도
	rel_menu.name_edit.text = "정식"
	rel_menu.create_button.pressed.emit()
	check(rel_menu.client == null and rel_menu.status_label.text.contains("wss"), "정식 빌드: 평문 서버에는 접속하지 않고 안내한다 (%s)" % rel_menu.status_label.text)
	check(rel_menu.server_edit.text == rel_menu.default_server, "정식 빌드: 입력한 주소를 쓰지 않고 기본 서버로 되돌린다")
	rel_menu.queue_free()
	MainMenu.force_release = false
	await frames(2)
