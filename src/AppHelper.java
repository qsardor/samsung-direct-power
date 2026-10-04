import android.app.ActivityThread;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.os.Looper;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class AppHelper {
    static class AppItem implements Comparable<AppItem> {
        String pkg;
        String label;
        boolean isGame;
        AppItem(String p, String l, boolean g) {
            pkg = p;
            label = l;
            isGame = g;
        }
        @Override
        public int compareTo(AppItem o) {
            if (this.label == null && o.label == null) return 0;
            if (this.label == null) return -1;
            if (o.label == null) return 1;
            return this.label.compareToIgnoreCase(o.label);
        }
    }

    public static void main(String[] args) {
        try {
            if (Looper.myLooper() == null) {
                Looper.prepare();
            }

            Context context = ActivityThread.systemMain().getSystemContext();
            PackageManager pm = context.getPackageManager();

            String webDir = args.length > 0 ? args[0] : "/data/adb/modules/samsung_direct_power/webroot";
            File iconDir = new File(webDir, "icons");
            iconDir.mkdirs();

            // Load whitelist to prioritize and guarantee inclusion across different config folder variants
            Set<String> whitelisted = new HashSet<>();
            File wlFile = new File("/data/adb/samsung_direct_power/whitelist.json");
            if (wlFile.exists()) {
                try {
                    BufferedReader br = new BufferedReader(new FileReader(wlFile));
                    StringBuilder sb = new StringBuilder();
                    String line;
                    while ((line = br.readLine()) != null) {
                        sb.append(line);
                    }
                    br.close();
                    Matcher m = Pattern.compile("\"([a-zA-Z0-9_.]+)\"").matcher(sb.toString());
                    while (m.find()) {
                        whitelisted.add(m.group(1));
                    }
                } catch (Throwable ignored) {}
            }

            // High-speed resolution: Query user-facing launcher activities directly (~50 apps vs 400+ installed packages)
            Intent mainIntent = new Intent(Intent.ACTION_MAIN, null);
            mainIntent.addCategory(Intent.CATEGORY_LAUNCHER);
            List<ResolveInfo> launchables = pm.queryIntentActivities(mainIntent, 0);

            List<AppItem> items = new ArrayList<>();
            Set<String> seenPkgs = new HashSet<>();

            if (launchables != null) {
                for (ResolveInfo ri : launchables) {
                    if (ri.activityInfo == null || ri.activityInfo.packageName == null) continue;
                    String pkg = ri.activityInfo.packageName;
                    if (seenPkgs.contains(pkg)) continue;
                    seenPkgs.add(pkg);

                    ApplicationInfo app = ri.activityInfo.applicationInfo;
                    if (app == null) {
                        try {
                            app = pm.getApplicationInfo(pkg, 0);
                        } catch (Throwable ignored) {}
                    }

                    CharSequence labelSeq = ri.loadLabel(pm);
                    if (labelSeq == null && app != null) {
                        labelSeq = app.loadLabel(pm);
                    }
                    String label = labelSeq != null ? labelSeq.toString().trim() : pkg;
                    if (label.isEmpty()) label = pkg;
                    label = label.replace("\\", "\\\\").replace("\"", "\\\"").replaceAll("[\\p{Cntrl}]", " ");

                    boolean isGame = (app != null && (app.category == ApplicationInfo.CATEGORY_GAME || (app.flags & ApplicationInfo.FLAG_IS_GAME) != 0));
                    if (pkg.equals("com.google.android.play.games") || pkg.equals("com.samsung.android.game.gamehome")) {
                        isGame = false;
                    }

                    items.add(new AppItem(pkg, label, isGame));

                    // Cache icon ONLY for detected games or whitelisted items (prevents hundreds of expensive PNG compressions)
                    if (isGame || whitelisted.contains(pkg)) {
                        File iconFile = new File(iconDir, pkg + ".png");
                        if (!iconFile.exists() || iconFile.length() < 100) {
                            try {
                                Drawable d = ri.loadIcon(pm);
                                if (d == null && app != null) {
                                    d = app.loadIcon(pm);
                                }
                                if (d != null) {
                                    int w = d.getIntrinsicWidth();
                                    int h = d.getIntrinsicHeight();
                                    if (w <= 0 || h <= 0) {
                                        w = 72;
                                        h = 72;
                                    } else {
                                        w = Math.min(w, 96);
                                        h = Math.min(h, 96);
                                    }
                                    Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                                    Canvas canvas = new Canvas(bmp);
                                    d.setBounds(0, 0, w, h);
                                    d.draw(canvas);

                                    FileOutputStream fos = new FileOutputStream(iconFile);
                                    bmp.compress(Bitmap.CompressFormat.PNG, 90, fos);
                                    fos.flush();
                                    fos.close();
                                }
                            } catch (Throwable ignored) {}
                        }
                    }
                }
            }

            // Ensure any whitelisted app not in launcher is also added to the list
            for (String wlPkg : whitelisted) {
                if (seenPkgs.contains(wlPkg)) continue;
                seenPkgs.add(wlPkg);
                try {
                    ApplicationInfo app = pm.getApplicationInfo(wlPkg, 0);
                    CharSequence labelSeq = app.loadLabel(pm);
                    String label = labelSeq != null ? labelSeq.toString().trim() : wlPkg;
                    if (label.isEmpty()) label = wlPkg;
                    label = label.replace("\\", "\\\\").replace("\"", "\\\"").replaceAll("[\\p{Cntrl}]", " ");
                    items.add(new AppItem(wlPkg, label, true));

                    File iconFile = new File(iconDir, wlPkg + ".png");
                    if (!iconFile.exists() || iconFile.length() < 100) {
                        Drawable d = app.loadIcon(pm);
                        if (d != null) {
                            int w = d.getIntrinsicWidth();
                            int h = d.getIntrinsicHeight();
                            if (w <= 0 || h <= 0) {
                                w = 72;
                                h = 72;
                            } else {
                                w = Math.min(w, 96);
                                h = Math.min(h, 96);
                            }
                            Bitmap bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                            Canvas canvas = new Canvas(bmp);
                            d.setBounds(0, 0, w, h);
                            d.draw(canvas);

                            FileOutputStream fos = new FileOutputStream(iconFile);
                            bmp.compress(Bitmap.CompressFormat.PNG, 90, fos);
                            fos.flush();
                            fos.close();
                        }
                    }
                } catch (Throwable ignored) {}
            }

            // Alphabetical sort by label using natural Comparable ordering
            Collections.sort(items);

            StringBuilder json = new StringBuilder("[");
            boolean first = true;
            for (AppItem it : items) {
                if (!first) json.append(",");
                first = false;
                json.append("{\"pkg\":\"").append(it.pkg)
                    .append("\",\"label\":\"").append(it.label)
                    .append("\",\"game\":").append(it.isGame ? "true" : "false")
                    .append("}");
            }
            json.append("]");

            File jsonFile = new File(webDir, "apps.json");
            FileWriter fw = new FileWriter(jsonFile);
            fw.write(json.toString());
            fw.close();

            System.out.println("EXTRACTED:" + items.size());
        } catch (Throwable t) {
            t.printStackTrace(System.err);
            System.exit(1);
        }
    }
}
