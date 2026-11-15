extends Control

# Thought just having a campaign was a bit boring so we decided to do a little sandbox, cool thing I feel
const ROW := preload("res://scenes/components/home_row.tscn")

@onready var _header: ScreenHeader = %Header
@onready var _rows: VBoxContainer = %Rows
@onready var _refresh: Button = %Refresh
@onready var _free: Button = %FreeBuild
@onready var _builder: Button = %Builder
@onready var _funds: Label = %Funds
@onready var _destination: OptionButton = %Destination

const TIER_COLORS := [UiKit.CYAN, UiKit.AMBER, UiKit.VIOLET]

func _ready() -> void:
	GameState.ensure_board()
	_header.back_pressed.connect(func() -> void: EventBus.goto_home.emit())
	_refresh.pressed.connect(_on_refresh)
	_free.pressed.connect(_on_free_build)
	_builder.pressed.connect(func() -> void: EventBus.open_builder.emit())
	_destination.item_selected.connect(_on_destination)
	_build_destinations()
	_fill()

func _build_destinations() -> void:
	_destination.clear()
	var selected := str(GameState.settings.get("sandbox_target", "moon"))
	var selected_index := -1
	for raw in GameData.body_list:
		var body: CelestialBody = raw
		if body.id == "sun" or body.id == "earth" or body.soi_or_default() <= 0.0:
			continue
		var label := Localization.t(body.display_name)
		_destination.add_item(label)
		_destination.set_item_metadata(_destination.item_count - 1, body.id)
		if body.id == selected:
			selected_index = _destination.item_count - 1
	if selected_index < 0:
		for i in range(_destination.item_count):
			if str(_destination.get_item_metadata(i)) == "moon":
				selected_index = i
				break
	if selected_index >= 0:
		_destination.select(selected_index)

func _on_destination(index: int) -> void:
	GameState.set_sandbox_target(str(_destination.get_item_metadata(index)))

func _fill() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	_header.setup(Localization.t("SANDBOX / CONTRACTS"), Localization.t("CONTRACT BOARD"),
		Localization.t("Funds %s   /   Reputation %d", [UiKit.money(float(GameState.credits)), GameState.reputation]),
		"", "< HOME")
	_funds.text = Localization.t("FUNDS %s", [UiKit.money(float(GameState.credits))])

	if not GameState.active_contract.is_empty():
		var active: Dictionary = GameState.active_contract
		var active_mission: Dictionary = active.get("mission", {})
		var row: HomeRow = ROW.instantiate()
		_rows.add_child(row)
		row.setup(">", Localization.t("RESUME: %s", [Localization.t(str(active_mission.get("name", "CONTRACT")))]),
			Localization.t("Accepted contract in progress"), "[ACTIVE]", UiKit.GREEN, true, true, "RESUME")
		row.activated.connect(_on_resume)

	for i in range(GameState.board.size()):
		var offer: Dictionary = GameState.board[i]
		var mission: Dictionary = offer.get("mission", {})
		var tier: int = int(offer.get("tier", 1))
		var row: HomeRow = ROW.instantiate()
		_rows.add_child(row)
		row.setup(">", Localization.t(str(mission.get("name", "CONTRACT"))),
			Localization.t("TIER %d  /  %s  /  +%s  /  ADV %s  /  DUE %dd", [tier,
				Localization.t(str(offer.get("template", "")).to_upper()),
				UiKit.money(float(offer.get("reward", 0))),
				UiKit.money(float(offer.get("advance", 0))),
				int(ceil(float(offer.get("expires_day", 0.0)) - GameState.campaign_day))]),
			"[T%d]" % tier, TIER_COLORS[clampi(tier - 1, 0, 2)], true, true, "ACCEPT")
		row.activated.connect(_on_accept.bind(i))

func _on_accept(index: int) -> void:
	var mission: MissionDef = GameState.accept_contract(index)
	if mission != null:
		EventBus.open_briefing.emit(mission)

func _on_resume() -> void:
	var mission: MissionDef = GameState.active_mission()
	if mission != null:
		EventBus.open_briefing.emit(mission)

func _on_refresh() -> void:
	GameState.refresh_board()
	_fill()

func _on_free_build() -> void:
	EventBus.open_hangar.emit(GameState.sandbox_mission())

func request_exit() -> void:
	EventBus.goto_home.emit()
