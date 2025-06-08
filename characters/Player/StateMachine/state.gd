extends Node
class_name State

var state_machine: StateMachine
var player: CharacterBody3D


func enter():
	pass

func exit():
	pass

func update(_delta: float):
	pass

func physics_update(_delta: float):
	pass

func change_to(new_state: String):
	state_machine.change_state(new_state)
