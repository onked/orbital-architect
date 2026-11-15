extends Node

signal goto_home
signal open_contracts
signal open_achievements
signal open_blueprints
signal open_builder
signal open_credits
signal goto_menu
signal go_back
signal open_briefing(mission: MissionDef)
signal open_hangar(mission: MissionDef)
signal start_flight(mission: MissionDef, design: Array, cost: float, layout: Array, rots: Array, hull: Array)
signal end_flight(report: Dictionary)
signal start_tutorial(mission: MissionDef)
signal toast(text: String)
