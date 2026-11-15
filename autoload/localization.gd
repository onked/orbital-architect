extends Node

signal language_changed(code: String)

const MANIFEST := "res://locale/languages.json"

var _languages: Array = []
var _loaded: Dictionary = {}
var _reverse: Dictionary = {}


func _ready() -> void:
	_load_manifest()
	for lang in _languages:
		var file := str((lang as Dictionary).get("file", ""))
		if file == "":
			continue
		var f := FileAccess.open(file, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if not (parsed is Dictionary):
			continue
		var tr := Translation.new()
		tr.locale = str((lang as Dictionary).get("code", ""))
		for key in (parsed as Dictionary).keys():
			tr.add_message(str(key), str((parsed as Dictionary)[key]))
			_reverse[str((parsed as Dictionary)[key])] = str(key)
		TranslationServer.add_translation(tr)
		_loaded[tr.locale] = tr
	var code := str(GameState.settings.get("locale", "en"))
	if not _has(code):
		code = "en"
	TranslationServer.set_locale(code)
	GameState.relocalize_board()


func _load_manifest() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		_languages = parsed


func _has(code: String) -> bool:
	for lang in _languages:
		if str((lang as Dictionary).get("code", "")) == code:
			return true
	return false


func languages() -> Array:
	return _languages


func current() -> String:
	return TranslationServer.get_locale()


func set_language(code: String) -> void:
	if not _has(code):
		return
	TranslationServer.set_locale(code)
	GameState.settings["locale"] = code
	GameState.relocalize_board()
	GameState.save_campaign()
	language_changed.emit(code)


func t(key: String, args: Array = []) -> String:
	var s := TranslationServer.translate(key)
	if args.is_empty():
		return s
	return s % args


func translate_any(text: String) -> String:
	if text == "":
		return text
	var key := text
	if _reverse.has(text):
		key = str(_reverse[text])
	return t(key)


func apply_tree(node: Node) -> void:
	if node.has_meta("no_translate"):
		return
	if node is Label or node is Button or node is CheckButton or node is LinkButton:
		var control := node as Control
		var text_value := ""
		if node is Label:
			text_value = (node as Label).text
		elif node is Button:
			text_value = (node as Button).text
		elif node is CheckButton:
			text_value = (node as CheckButton).text
		elif node is LinkButton:
			text_value = (node as LinkButton).text
		var translated := translate_any(text_value)
		if translated != text_value:
			if node is Label:
				(node as Label).text = translated
			elif node is Button:
				(node as Button).text = translated
			elif node is CheckButton:
				(node as CheckButton).text = translated
			elif node is LinkButton:
				(node as LinkButton).text = translated
		if control.tooltip_text != "":
			control.tooltip_text = translate_any(control.tooltip_text)
	for child in node.get_children():
		apply_tree(child)


func voice_path(id: String) -> String:
	var code := current()
	if code != "en":
		var localized := "res://assets/audio/voice/%s/%s.mp3" % [code, id]
		if ResourceLoader.exists(localized):
			return localized
	return "res://assets/audio/voice/%s.mp3" % id
