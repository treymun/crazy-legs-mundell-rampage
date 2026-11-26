## The chapter's end card (pass 15; hud.gd intermission draws the backdrop):
## the panel with the chapter's heading and its rows (VARMINTS, SECRETS, the
## guns had, TIME, PAR and up to three of the features' rows), the bests in
## a column beside the numbers they stand for, the ribbon, NEW BEST stamped
## on when a best fell, and the ways on as plates nailed up beside the panel
## (the first is the one tap's; features/tally.gd runs the show, the front
## end fills in the ways on). Online the lobby's own line takes the plates'
## place (lobby_screens.gd draw_match).
class_name TallyCard
extends RefCounted

const TallyFeature := preload("res://src/features/tally.gd")
## The panel and where its rows start.
const PANEL := Rect2i(10, 9, 211, 177)
const ROW_TOP := 79
const ROW_LEFT := 21
const ROW_W := 187
## Pixels from one row to the next by how many there are (the bar is a
## pixel less, at most 15).
const GAPS: Array[int] = [18, 18, 18, 18, 18, 16, 14, 12, 10]
const MOST_ROWS := 8
## The bests' column: right-aligned here, clear of the widest number.
const BEST_RIGHT := 146
## The last line of the chapter's last word stays above this row.
const WORD_FOOT := 183
## The plates: one under another right of the panel, under the ribbon.
const PLATE_X := 225
const PLATE_W := 91
const PLATE_H := 20
const PLATE_TOPS: Array[int] = [118, 141, 164]
## NEW BEST in two lines over the ribbon's top, clear of the longest heading
## (the bayou's, out to column 243).
const STAMP := Rect2i(256, 11, 58, 42)
const STAMP_RED := Color(176 / 255.0, 34 / 255.0, 26 / 255.0)
const PAPER := Color(236 / 255.0, 222 / 255.0, 188 / 255.0)


## Whether the card is over play (offline: online the lobby's line and the
## MENU button stay): the touch buttons step aside, a tap anywhere is a pick.
static func up(game: Game) -> bool:
	return game != null and game.showing_tally and game.net_role == "" and not Modes.is_versus(game)


## After the campaign's last chapter the finale (finale.gd) stands in for
## the card.
static func is_finale(game: Game) -> bool:
	var last := Campaign.next_level(game.level.id) == ""
	return last and not game.history.is_empty() and not game.replay


## The card's rows: [label, value, beside it ([text, ink], or [] for none)].
static func rows_of(game: Game) -> Array:
	var show: TallyFeature = game.features.get("tally")
	var card: Dictionary = show.card if show != null else {}
	var old: Dictionary = card.get("old", {})
	var keeps := _flag(card, "kept_bests")
	var rows: Array = [
		[
			"VARMINTS",
			"%02d / %02d" % [game.kills, game.total_kills],
			_beside(keeps, old, card, "kills", "BEST %02d"),
		],
		[
			"SECRETS",
			"%02d / %02d" % [game.secrets, game.total_secrets],
			_beside(keeps, old, card, "secrets", "BEST %02d"),
		],
		["TIME", ChapterBests.clock_text(game.clock), _beside(keeps, old, card, "time", "")],
	]
	# The chapter's guns had, under the secrets (src/gun_finder.gd).
	var guns := GunFinder.tally(game)
	if not guns.is_empty():
		rows.insert(2, [guns[0], guns[1], []])
	var par := ChapterBests.par(game.level.id)
	if par > 0.0:
		var off := game.clock - par
		var word := (
			"%s UNDER" % ChapterBests.clock_text(-off)
			if off <= 0.0
			else "%s OVER" % ChapterBests.clock_text(off)
		)
		rows.append(
			["PAR", ChapterBests.clock_text(par), [word, HUD.AMBER if off <= 0.0 else HUD.LOW]]
		)
	# Features add their own rows (features.gd: accuracy, each boss's time);
	# room for three more, the rows closing up to fit.
	for row: Array in Features.tally_rows(game).slice(0, 3):
		rows.append([row[0], row[1], []])
	return rows


## A best beside its row: NEW BEST where this run set it, else the old one,
## nothing on a first run or where no bests are kept.
static func _beside(
	keeps: bool, old: Dictionary, card: Dictionary, key: String, form: String
) -> Array:
	if not keeps or old.is_empty():
		return []
	if _flag(card, key):
		return ["NEW BEST", HUD.AMBER]
	if key == "time":
		var seconds: float = old["time"]
		return ["BEST " + ChapterBests.clock_text(seconds), Menu.FADED]
	var count: int = old[key]
	return [form % count, Menu.FADED]


static func _flag(card: Dictionary, key: String) -> bool:
	var on: bool = card.get(key, false)
	return on


## The panel, its rows and last word, the ribbon and stamp as the show
## brings them, and the plates.
static func draw(c: Canvas, game: Game) -> void:
	HUD.panel(c, PANEL.position.x, PANEL.position.y, PANEL.size.x, PANEL.size.y)
	var ys: Array[int] = [20, 38]
	for i in mini(2, game.level.heading.size()):
		HUD.text(c, game.level.heading[i], 21, ys[i], "heading", HUD.AMBER)
	# The title under the heading, unless the heading says it already.
	var title_end := 21
	if not game.level.heading.has(game.level.title):
		title_end = HUD.text(c, game.level.title, 21, 61, "body", HUD.INK).end.x
	var show: TallyFeature = game.features.get("tally")
	var card: Dictionary = show.card if show != null else {}
	var played := str(card.get("difficulty", ""))
	if _flag(card, "kept_bests") and played != "":
		# Whose bests these are, on the title's line when it has room.
		var on_what := "ON " + played
		if title_end + 8 < 208 - PixelType.text_width(on_what, "mini"):
			HUD.text(c, on_what, 208, 62, "mini", Menu.FADED, false, true, true)
	c.line(21, 72, 208, 72, Color(135 / 255.0, 95 / 255.0, 63 / 255.0))
	var rows := rows_of(game)
	var count := mini(rows.size(), MOST_ROWS)
	var gap: int = GAPS[count]
	var bar := mini(15, gap - 1)
	# The rows come down one at a time with a thud, then the ribbon (tally.gd).
	var shown: int = show.rows_shown(count) if show != null else count + 1
	for i in mini(shown, count):
		var row: Array = rows[i]
		var y := ROW_TOP + i * gap
		var text_y := y + int((bar - 7) / 2.0)
		c.fill_rect(ROW_LEFT, y, ROW_W, bar, Color(30 / 255.0, 21 / 255.0, 17 / 255.0))
		HUD.text(c, str(row[0]), 26, text_y, "body", HUD.INK)
		HUD.text(c, str(row[1]), 202, text_y, "body", HUD.AMBER, false, true, true)
		var beside: Array = row[2]
		if not beside.is_empty():
			var ink: Color = beside[1]
			HUD.text(c, str(beside[0]), BEST_RIGHT, text_y + 1, "mini", ink, false, true, true)
	_last_word(c, game, ROW_TOP + (count - 1) * gap + bar + 3 if count > 0 else ROW_TOP)
	if show != null and shown > count:
		ribbon(c, show.ribbon())
	if show != null and shown > count + 1:
		stamp(c)
	if game.net_role == "":
		var plates := plates_of(game)
		for i in plates.size():
			var choice: Array = plates[i]
			_plate(c, i, choice)


## The chapter's last word under the rows, kept inside the panel: a long one
## takes two lines.
static func _last_word(c: Canvas, game: Game, top: int) -> void:
	var said := PixelType.wrap(game.level.ending, 186, "body")
	var y := mini(top, WORD_FOOT - said.size() * 9)
	for i in said.size():
		HUD.text(c, said[i], 22, y + i * 9, "body", HUD.AMBER)


## The ways on: [key word, label, action] each, the front end's (tally.gd
## `choices`), or with no front end (a picture tool) the campaign's two.
static func plates_of(game: Game) -> Array:
	var show: TallyFeature = game.features.get("tally")
	if show != null and not show.choices.is_empty():
		return show.choices
	var on := Campaign.next_level(game.level.id) != "" and not game.replay
	var words: Array = (
		["A", "Y"]
		if game.input_device == "pad"
		else (["TAP", "TAP"] if game.input_device == "touch" else ["ENTER", "TAB"])
	)
	if not on:
		return [[words[0], "RETURN TO TITLE", "title", 0]]
	return [[words[0], "NEXT CHAPTER", "next", 0], [words[1], "THE CROSSROADS", "hub", 1]]


static func plate_rect(index: int) -> Rect2i:
	return Rect2i(PLATE_X, PLATE_TOPS[index], PLATE_W, PLATE_H)


## A plate: its key word over what it does, the one tap's lit.
static func _plate(c: Canvas, index: int, choice: Array) -> void:
	if index >= PLATE_TOPS.size():
		return
	var at := plate_rect(index)
	Menu.plate_button(c, at, "", index == 0)
	var mid := at.position.x + at.size.x / 2
	var ink := Menu.BRIGHT if index == 0 else Menu.PAINT
	HUD.text(c, str(choice[0]), mid, at.position.y + 2, "mini", HUD.AMBER, true)
	HUD.text(c, str(choice[1]), mid, at.position.y + 11, "body", ink, true)


## The slot (BetweenChapters GO, OTHER, AGAIN) of the plate at `point`
## (picture columns), or -1 off them.
static func plate_at(game: Game, point: Vector2i) -> int:
	if not up(game) or is_finale(game):
		return -1
	var plates := plates_of(game)
	for i in mini(plates.size(), PLATE_TOPS.size()):
		if plate_rect(i).grow(1).has_point(point):
			var choice: Array = plates[i]
			var slot: int = choice[3] if choice.size() > 3 else i
			return slot
	return -1


## A tap's way on: the plate's under it, else the one tap's (anywhere goes on).
static func zone_at(game: Game, point: Vector2i) -> int:
	return maxi(0, plate_at(game, point))


## The county fair ribbon pinned beside the tally: how the chapter went.
static func ribbon(c: Canvas, word: String) -> void:
	var red := Color(150 / 255.0, 30 / 255.0, 24 / 255.0)
	var gold := Color(236 / 255.0, 196 / 255.0, 104 / 255.0)
	c.fill_rect(229, 58, 84, 34, Color(.08, .05, .04))
	c.fill_rect(228, 56, 84, 34, red)
	c.fill_rect(230, 58, 80, 1, gold)
	c.fill_rect(230, 87, 80, 1, gold)
	HUD.text(c, "RANKED", 270, 61, "mini", gold, true)
	HUD.text(c, word, 270, 72, "body", HUD.INK, true)
	# The ribbon's two tails.
	for x: int in [248, 288]:
		c.fill_rect(x, 90, 8, 14, red)
		c.fill_rect(x + 2, 104, 4, 3, red)


## NEW BEST, inked on like the fair's judge's stamp.
static func stamp(c: Canvas) -> void:
	var x := STAMP.position.x
	var y := STAMP.position.y
	var w := STAMP.size.x
	var h := STAMP.size.y
	c.fill_rect(x + 1, y + 2, w, h, Color(.08, .05, .04))
	c.fill_rect(x, y, w, h, PAPER)
	for inset: int in [1, 3]:
		c.fill_rect(x + inset, y + inset, w - inset * 2, 1, STAMP_RED)
		c.fill_rect(x + inset, y + h - 1 - inset, w - inset * 2, 1, STAMP_RED)
		c.fill_rect(x + inset, y + inset, 1, h - inset * 2, STAMP_RED)
		c.fill_rect(x + w - 1 - inset, y + inset, 1, h - inset * 2, STAMP_RED)
	HUD.text(c, "NEW", x + w / 2, y + 6, "heading", STAMP_RED, true, false)
	HUD.text(c, "BEST", x + w / 2, y + 22, "heading", STAMP_RED, true, false)
