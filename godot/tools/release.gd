## Publish a release, every step in order, stopping at the first that fails.
##
##   godot --headless --path godot --script res://tools/release.gd -- 2.0.0-dev.N
##
##  1. The tree is clean and on combat-overhaul (the icons Godot rewrites are
##     put back first).
##  2. tools/version.gd stamps N; the change is committed as "Version N" and the
##     branch is pushed.
##  3. The branch's CI run must pass (every check, the pictures, the lint).
##  4. main is fast-forwarded to it and pushed (it builds the browser builds
##     and deploys the site).
##  5. The tag vN is pushed (it builds the EXE, installer and APK and makes
##     the release).
##  6. The main and tag runs must pass (they find the branch's passed run on
##     the same commit and go straight to the builds), the site's version.txt
##     must say N and the release must hold its three files and update.json,
##     whose APK size matches the APK's (the in-game Android update reads it).
## Nothing is published unless the branch's checks passed: main and the tag
## are pushed only after step 3, and their runs build only on a commit whose
## checks passed (.github/workflows/release.yml, the job `earlier`).
## Ask the owner before running it: it publishes. gh is not logged in here, so
## CI is read from the public API with curl.
extends SceneTree

const REPO := "treymun/crazy-legs-mundell-rampage"
const WORKFLOW := "release.yml"
const BRANCH := "combat-overhaul"
const SITE := "https://treymun.github.io/crazy-legs-mundell-rampage/version.txt"
const ASSETS := [
	"CrazyLegsMundellRampage.exe",
	"CrazyLegsMundellRampage_Setup.exe",
	"CrazyLegsMundellRampage.apk",
	"update.json",
]
## Seconds to wait for CI runs before giving up.
const PATIENCE := 3600
## Seconds between looks at CI (the API allows 60 calls an hour without a
## login: a release takes about 30 at this pace), and how long the site may
## take to show N.
const POLL := 20
const SITE_PATIENCE := 300

var repo_root := ""


func _init() -> void:
	repo_root = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_stop("usage: release.gd -- 2.0.0-dev.N")
		return
	var version := String(args[0]).trim_prefix("v")
	var tag := "v" + version
	_step("1. clean tree on " + BRANCH)
	_git(["checkout", "--", "godot/icons"], true)
	if _git(["rev-parse", "--abbrev-ref", "HEAD"]).strip_edges() != BRANCH:
		_stop("not on " + BRANCH)
		return
	if _git(["status", "--porcelain"]).strip_edges() != "":
		_stop("the tree has changes; commit them first:\n" + _git(["status", "--short"]))
		return
	if _git(["ls-remote", "--tags", "origin", tag]).strip_edges() != "":
		_stop(tag + " is already published")
		return

	_step("2. stamp, commit and push")
	var output := []
	var code := OS.execute(
		OS.get_executable_path(),
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--script",
			"res://tools/version.gd",
			"--",
			version
		],
		output,
		true
	)
	print("\n".join(output).strip_edges())
	if code != 0:
		_stop("version.gd failed")
		return
	_git(["checkout", "--", "godot/icons"], true)
	_git(["add", "godot/project.godot", "godot/export_presets.cfg"])
	_git(
		[
			"commit",
			"-m",
			"Version %s\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" % version
		]
	)
	_git(["push", "-q", "origin", BRANCH])
	var sha := _git(["rev-parse", "HEAD"]).strip_edges()

	_step("3. CI on the branch")
	if not _wait_runs(sha, [BRANCH]):
		_stop("the branch's CI did not pass; nothing was published")
		return

	_step("4. main")
	_git(["fetch", "-q", "origin", "main"])
	if (
		OS.execute("git", ["-C", repo_root, "merge-base", "--is-ancestor", "origin/main", "HEAD"])
		!= 0
	):
		_stop("main has commits the branch does not; it cannot fast-forward")
		return
	_git(["push", "-q", "origin", "HEAD:main"])

	_step("5. tag " + tag)
	_git(["tag", tag])
	_git(["push", "-q", "origin", tag])

	_step("6. the release and the site")
	if not _wait_runs(sha, ["main", tag]):
		_stop("a release run failed; see the Actions page")
		return
	# Pages can take a minute to serve the new deploy.
	var live := ""
	var looked := 0
	while true:
		live = _curl(SITE + "?fresh=%d" % Time.get_unix_time_from_system()).strip_edges()
		if live == version or looked >= SITE_PATIENCE:
			break
		OS.delay_msec(POLL * 1000)
		looked += POLL
	if live != version:
		_stop("the site says %s, not %s" % [live, version])
		return
	var release = JSON.parse_string(
		_curl("https://api.github.com/repos/%s/releases/tags/%s" % [REPO, tag])
	)
	var names := []
	var sizes := {}
	if release is Dictionary:
		for asset: Dictionary in release.get("assets", []):
			names.append(String(asset["name"]))
			sizes[String(asset["name"])] = int(asset.get("size", 0))
	for asset: String in ASSETS:
		if not names.has(asset):
			_stop("the release is missing " + asset)
			return
	# update.json must describe this very release's APK.
	var said = JSON.parse_string(
		_curl_follow("https://github.com/%s/releases/download/%s/update.json" % [REPO, tag])
	)
	var apk_size := -1
	if said is Dictionary and str(said.get("version", "")) == version:
		apk_size = int(said.get("files", {}).get("CrazyLegsMundellRampage.apk", {}).get("size", -1))
	if apk_size != int(sizes.get("CrazyLegsMundellRampage.apk", -2)):
		_stop("update.json does not match the release's APK (%d bytes)" % apk_size)
		return
	print("\nRELEASED %s: the site says %s and the release has %s" % [tag, live, ", ".join(ASSETS)])
	quit()


## Wait until this commit's workflow run on each ref (the branch, main, the
## tag) has passed; stop at the first that fails. Runs on other refs and of
## other workflows are not waited for.
func _wait_runs(sha: String, refs: Array) -> bool:
	var waited := 0
	while waited < PATIENCE:
		var url := "https://api.github.com/repos/%s/actions/workflows/%s/runs" % [REPO, WORKFLOW]
		var runs = JSON.parse_string(_curl(url + "?head_sha=%s&per_page=50" % sha))
		var listed: Array = runs.get("workflow_runs", []) if runs is Dictionary else []
		if runs is Dictionary and not runs.has("workflow_runs"):
			# The API without a login allows 60 calls an hour from one address.
			print("  the API says: %s" % runs.get("message", "?"))
		var passed := 0
		for ref: String in refs:
			# The newest run on the ref counts (a re-run replaces an older one).
			var newest: Dictionary = {}
			for run: Dictionary in listed:
				if String(run["head_branch"]) == ref and String(run["event"]) == "push":
					if newest.is_empty() or int(run["id"]) > int(newest["id"]):
						newest = run
			if newest.is_empty() or String(newest["status"]) != "completed":
				continue
			if String(newest.get("conclusion", "")) != "success":
				print("  %s run %s: %s" % [ref, newest.get("conclusion"), newest["html_url"]])
				return false
			passed += 1
		if passed == refs.size():
			print("  passed: " + ", ".join(refs))
			return true
		OS.delay_msec(POLL * 1000)
		waited += POLL
		if waited % 120 == 0:
			print("  waiting for CI (%d of %d passed, %d s)" % [passed, refs.size(), waited])
	return false


func _git(args: Array, quiet := false) -> String:
	var output := []
	var code := OS.execute("git", ["-C", repo_root] + args, output, true)
	if code != 0 and not quiet:
		push_error("git %s failed:\n%s" % [" ".join(args), "\n".join(output)])
	return "\n".join(output)


func _curl_follow(url: String) -> String:
	var output := []
	OS.execute("curl", ["-sL", url], output, true)
	return "".join(output)


func _curl(url: String) -> String:
	var output := []
	OS.execute("curl", ["-s", url], output, true)
	return "\n".join(output)


func _step(text: String) -> void:
	print("\n== " + text)


func _stop(text: String) -> void:
	push_error(text)
	print("\nRELEASE STOPPED: " + text)
	quit(1)
