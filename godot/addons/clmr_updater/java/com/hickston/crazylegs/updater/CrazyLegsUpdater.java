// The Android side of the update notice (src/update_notice.gd, src/apk_installer.gd):
// where the new APK is downloaded to, whether this app may hand an APK to the
// system's package installer, the system setting that allows it, and the
// hand-over itself. The game downloads and checks the APK; this only hands the
// verified file to Android, which asks the player to confirm the update (a
// sideloaded app can never install itself silently).
//
// Built into an AAR by tools/android_plugin.gd and put in the Gradle build by
// addons/clmr_updater/export_plugin.gd. Godot finds it by the manifest's
// org.godotengine.plugin.v2.CrazyLegsUpdater entry (aar/AndroidManifest.xml).
package com.hickston.crazylegs.updater;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import java.io.File;
import java.io.IOException;
import java.lang.reflect.Method;
import java.util.HashSet;
import java.util.Set;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

public class CrazyLegsUpdater extends GodotPlugin {
	/** The package installer's answer comes back with this request code. */
	private static final int INSTALL_REQUEST = 7301;
	/** The app came back to the front (from the setting, or the installer). */
	private static final SignalInfo RESUMED = new SignalInfo("resumed");
	/** The installer's answer: Activity.RESULT_OK (-1), RESULT_CANCELED (0) or a failure (1). */
	private static final SignalInfo INSTALL_RESULT = new SignalInfo("install_result", Integer.class);
	/**
	 * Godot's own FileProvider (godot-lib's manifest: authority <package>.fileprovider,
	 * serving the app's files folder): it hands the installer a content:// address
	 * for the APK, never a file:// one.
	 */
	private static final String PROVIDER = "androidx.core.content.FileProvider";

	public CrazyLegsUpdater(Godot godot) {
		super(godot);
	}

	@Override
	public String getPluginName() {
		return "CrazyLegsUpdater";
	}

	@Override
	public Set<SignalInfo> getPluginSignals() {
		Set<SignalInfo> signals = new HashSet<>();
		signals.add(RESUMED);
		signals.add(INSTALL_RESULT);
		return signals;
	}

	private Context context() {
		Activity activity = getActivity();
		return activity != null ? activity : getContext();
	}

	/** The folder downloads go to: the app's own files (never shared storage). */
	@UsedByGodot
	public String downloadDir() {
		Context c = context();
		if (c == null) {
			return "";
		}
		File dir = new File(c.getFilesDir(), "updates");
		if (!dir.isDirectory() && !dir.mkdirs()) {
			return "";
		}
		return dir.getAbsolutePath();
	}

	/** Whether Android lets this app open the package installer ("install unknown apps"). */
	@UsedByGodot
	public boolean canInstall() {
		Context c = context();
		if (c == null) {
			return false;
		}
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
			// Before Android 8 the installer itself asks about unknown sources.
			return true;
		}
		return c.getPackageManager().canRequestPackageInstalls();
	}

	/** Open the system setting that lets this app install updates (false: no activity). */
	@UsedByGodot
	public boolean openInstallSettings() {
		Activity activity = getActivity();
		if (activity == null) {
			return false;
		}
		Intent intent;
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			intent = new Intent(
					Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
					Uri.parse("package:" + activity.getPackageName()));
		} else {
			intent = new Intent(Settings.ACTION_SECURITY_SETTINGS);
		}
		final Intent open = intent;
		runOnUiThread(() -> {
			try {
				activity.startActivity(open);
			} catch (ActivityNotFoundException e) {
				// Nothing opens: the game still says where the switch is.
			}
		});
		return true;
	}

	/**
	 * Hand the APK at `path` (inside downloadDir()) to the package installer.
	 * "" once the installer is opening; otherwise what went wrong. The answer
	 * comes as install_result when the player cancels or it fails; when the
	 * update goes in, Android stops this app to replace it.
	 */
	@UsedByGodot
	public String install(String path) {
		Activity activity = getActivity();
		if (activity == null) {
			return "no activity";
		}
		File apk = new File(path);
		File dir = new File(activity.getFilesDir(), "updates");
		try {
			if (!apk.isFile() || !apk.getCanonicalPath().startsWith(dir.getCanonicalPath() + File.separator)) {
				return "not a download";
			}
		} catch (IOException e) {
			return "not a download";
		}
		Uri uri;
		try {
			Method get = Class.forName(PROVIDER).getMethod("getUriForFile", Context.class, String.class, File.class);
			uri = (Uri) get.invoke(null, activity, activity.getPackageName() + ".fileprovider", apk);
		} catch (ReflectiveOperationException | RuntimeException e) {
			return "no provider: " + e;
		}
		@SuppressWarnings("deprecation")
		Intent intent = new Intent(Intent.ACTION_INSTALL_PACKAGE);
		intent.setDataAndType(uri, "application/vnd.android.package-archive");
		intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
		intent.putExtra(Intent.EXTRA_RETURN_RESULT, true);
		intent.putExtra(Intent.EXTRA_INSTALLER_PACKAGE_NAME, activity.getPackageName());
		// Activities start on the UI thread; a failure there answers as a
		// failed install (install_result 1) so the game offers TRY AGIN.
		runOnUiThread(() -> {
			try {
				activity.startActivityForResult(intent, INSTALL_REQUEST);
			} catch (ActivityNotFoundException | SecurityException e) {
				emitSignal(INSTALL_RESULT.getName(), Integer.valueOf(Activity.RESULT_FIRST_USER));
			}
		});
		return "";
	}

	@Override
	public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
		if (requestCode == INSTALL_REQUEST) {
			emitSignal(INSTALL_RESULT.getName(), Integer.valueOf(resultCode));
		}
	}

	@Override
	public void onMainResume() {
		emitSignal(RESUMED.getName());
	}
}
