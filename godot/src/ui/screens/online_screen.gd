## The multiplayer screens: MULTIPLAYER, PLAY VS BOTS (the 5v5 picker),
## COUNTY SERVERS, HOST A GAME, JOIN WITH A CODE, the lobby and ALL SETTINGS
## (one instance per state). LobbyScreens and TacticalScreens draw them,
## OnlineInput reads their taps and the front end's handlers their keys.
class_name OnlineScreen
extends ZonedScreen


func draw_zoned(c: Canvas) -> void:
	if main.state == "showdown":
		TacticalScreens.draw_picker(
			c,
			main.menu,
			main.showdown_row,
			main.showdown_mode,
			main.showdown_map,
			main.showdown_long,
			main.showdown_rules,
			main.showdown_skill
		)
	else:
		LobbyScreens.draw_screen(main)


func hover_at(at: Vector2i) -> void:
	OnlineInput.hover(main, at)


func tap_at(at: Vector2i) -> void:
	OnlineInput.tap(main, at)
