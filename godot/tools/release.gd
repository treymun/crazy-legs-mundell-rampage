## Publish a release, every step in order, stopping at the first that fails.
##
##   godot --headless --path godot --script res://tools/release.gd -- 2.0.0-dev.N
##
##  1. The tree is clean and on combat-overhaul (the icons Godot rewrites are
##     put back first).
##  2. tools/version.gd stamps N; the change is committed as "Version N" and the
##     branch is pushed.
##  3. The branch's CI run must pass.
##  4. main is fast-forwarded to it and pushed (it deploys the site).
##  5. The tag vN is pushed (it builds the EXE, installer and APK).
##  6. Both runs must pass, the site's version.txt must say N and the release
##     must hold its three files.
## Ask the owner before running it: it publishes. gh is not logged in here, so
## CI is read from the public API with curl.
extends SceneTree

const REPO := "treymun/crazy-legs-mundell-rampage"
const BRANCH := "combat-overhaul"
const SITE := "https://treymun.github.io/crazy-legs-mundell-rampage/version.txt"
const ASSETS := [
	"CrazyLegsMundellRampage.exe",
	"CrazyLegsMundellRampage_Setup.exe",
	"CrazyLegsMundellRampage.apk"
]
## Seconds to wait for CI runs before giving up.
const PATIENCE := 3600

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
	if not _wait_runs(sha, 1):
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
	if not _wait_runs(sha, 3):
		_stop("a release run failed; see the Actions page")
		return
	var live := _curl(SITE + "?fresh=%d" % Time.get_unix_time_from_system()).strip_edges()
	if live != version:
		_stop("the site says %s, not %s" % [live, version])
		return
	var release = JSON.parse_string(
		_curl("https://api.github.com/repos/%s/releases/tags/%s" % [REPO, tag])
	)
	var names := []
	if release is Dictionary:
		for asset: Dictionary in release.get("assets", []):
			names.append(String(asset["name"]))
	for asset: String in ASSETS:
		if not names.has(asset):
			_stop("the release is missing " + asset)
			return
	print("\nRELEASED %s: the site says %s and the release has %s" % [tag, live, ", ".join(ASSETS)])
	quit()


## Wait until `count` CI runs of this commit (branch, main, tag) have all passed.
func _wait_runs(sha: String, count: int) -> bool:
	var waited := 0
	while waited < PATIENCE:
		var runs = JSON.parse_string(
			_curl("https://api.github.com/repos/%s/actions/runs?head_sha=%s" % [REPO, sha])
		)
		var listed: Array = runs.get("workflow_runs", []) if runs is Dictionary else []
		var done := 0
		for run: Dictionary in listed:
			if String(run["status"]) == "completed":
				if String(run.get("conclusion", "")) != "success":
					print("  %s run %s" % [run["head_branch"], run.get("conclusion")])
					return false
				done += 1
		if listed.size() >= count and done >= listed.size():
			print("  %d run(s) passed" % done)
			return true
		OS.delay_msec(20000)
		waited += 20
		if waited % 120 == 0:
			print(
				(
					"  waiting for CI (%d of %d done, %d s)"
					% [done, maxi(count, listed.size()), waited]
				)
			)
	return false


func _git(args: Array, quiet := false) -> String:
	var output := []
	var code := OS.execute("git", ["-C", repo_root] + args, output, true)
	if code != 0 and not quiet:
		push_error("git %s failed:\n%s" % [" ".join(args), "\n".join(output)])
	return "\n".join(output)


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
