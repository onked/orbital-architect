extends Control

# Main credits
# I'll also mention it here
# AI (or SI) was used in this project to assist coding, text and audio.
# Specifically, OpenCode, OpenRouter.
# For the rest of the credits check out either settings and then credits or read the code.

@onready var _header: ScreenHeader = %Header

func _ready() -> void:
	_header.back_pressed.connect(func() -> void: EventBus.goto_home.emit())
	_header.setup("CAREER / CREDITS", "CREDITS",
		"Assets, data and tools used to build Orbit Architect", "", "< HOME")

func request_exit() -> void:
	EventBus.goto_home.emit()
