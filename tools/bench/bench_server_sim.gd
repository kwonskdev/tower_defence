extends Node

func _ready() -> void:
	var server := ServerMain.new()
	add_child(server)
	var stack := int(ServerMain.arg_value("stack", "0"))
	if stack > 0:
		var inj: Node = load("res://tools/bench/stack_injector.gd").new()
		inj.server = server
		inj.target = stack
		add_child(inj)
