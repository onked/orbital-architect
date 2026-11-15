class_name PartCard
extends PanelContainer

signal add_requested(part: PartDef)
signal select_requested(part: PartDef)

var part: PartDef = null

@onready var _icon: TextureRect = %Icon
@onready var _name: Label = %Name
@onready var _meta: Label = %Meta
@onready var _add: Button = %Add

func setup(p: PartDef, can_add: bool) -> void:
	part = p
	_name.text = Localization.t(p.display_name)
	_meta.text = UiKit.money(p.cost_usd)
	var bits: Array = [UiKit.kg(p.mass_kg), UiKit.money(p.cost_usd)]
	if p.fuel_kg > 0.0:
		bits.append("+%d kg prop" % int(p.fuel_kg))
	if p.isp_s > 0.0:
		bits.append("Isp %d s" % int(p.isp_s))
	if p.power_w != 0.0:
		bits.append(power_label(p.power_w))
	tooltip_text = "%s\n%s\n%s" % [Localization.t(p.display_name),
		Localization.t(p.description), "  /  ".join(bits)]
	var tex: Texture2D = Art.part_icon(p)
	_icon.texture = tex
	_icon.visible = tex != null
	_add.disabled = not can_add
	_add.visible = false
	_add.pressed.connect(_on_add)
	set_selected(false)
	UiKit.attach_hover(self)

static func power_label(w: float) -> String:
	if w > 0.0:
		return "+%d W" % int(w)
	return "%d W" % int(w)

func set_selected(on: bool) -> void:
	var border: Color = UiKit.CYAN if on else UiKit.LINE
	add_theme_stylebox_override("panel", UiKit.style_panel(UiKit.PANEL_ALT, border, 3, 2))
	if has_meta("ui_hover_style"):
		remove_meta("ui_hover_style")
	if has_meta("ui_hover_base"):
		remove_meta("ui_hover_base")

func _gui_input(event: InputEvent) -> void:
	if part == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			select_requested.emit(part)

func _on_add() -> void:
	if part != null:
		add_requested.emit(part)

func _get_drag_data(_pos: Vector2) -> Variant:
	if part == null or _add.disabled:
		return null
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.style_panel(UiKit.PANEL_ALT, UiKit.CYAN, 4, 4))
	var label := Label.new()
	label.text = "  %s  " % part.display_name
	label.add_theme_font_size_override("font_size", 13)
	box.add_child(label)
	set_drag_preview(box)
	return {"kind": "part", "part": part.id}
