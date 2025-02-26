#!/bin/bash

# Define the configs to check and replace/add
configs=(
  "user_pref(\"browser.preferences.defaultPerformanceSettings.enabled\", false);"
  "user_pref(\"browser.cache.disk.enable\", false);"
  "user_pref(\"browser.cache.memory.enable\", true);"
  "user_pref(\"browser.sessionstore.resume_from_crash\", false);"
  "user_pref(\"extensions.pocket.enabled\", false);"
  "user_pref(\"layout.css.dpi\", 0);"
  "user_pref(\"general.smoothScroll.msdPhysics.enabled\", true);"
  "user_pref(\"media.hardware-video-decoding.force-enabled\", true);"
  "user_pref(\"middlemouse.paste\", true);"
  "user_pref(\"webgl.msaa-force\", true);"
  "user_pref(\"security.sandbox.content.read_path_whitelist\", \"/sys/\");"
  "user_pref(\"browser.download.alwaysOpenPanel\", false);"
  "user_pref(\"network.ssl_tokens_cache_capacity\", 32768);"
  "user_pref(\"media.ffmpeg.vaapi.enabled\", true);"
  "user_pref(\"accessibility.force_disabled\", 1);"
  "user_pref(\"browser.eme.ui.enabled\", false);"
)

# Get the profile directory name
profile_dir_name=$(cat ~/.var/app/app.zen_browser.zen/.zen/installs.ini | grep "Default=" | cut -d '=' -f 2)

# Find the prefs.js file
prefs_file=$(find ~/.var/app/app.zen_browser.zen/.zen/ -name "prefs.js" -path "*/$profile_dir_name/*")

# Check if the prefs.js file was found
if [ -z "$prefs_file" ]; then
  echo "Error: prefs.js file not found."
  exit 1
fi

# Process each config
for config in "${configs[@]}"; do
  # Extract the prefix (part before the first comma)
  prefix=$(echo "$config" | cut -d ',' -f 1)

  # Check if the config exists in the file
  if grep -q "$prefix" "$prefs_file"; then
    # Replace the line
    sed -i "/$prefix/c\\$config" "$prefs_file"
    echo "Replaced: $prefix"
  else
    # Add the line to the end of the file
    echo "$config" >> "$prefs_file"
    echo "Added: $prefix"
  fi
done

echo "prefs.js update completed."

mv ~/Backups/zen/search.json.mozlz4  ~/.var/app/app.zen_browser.zen/.zen/6eqii8l9.Default\ \(release\)/search.json.mozlz4
wget -c https://raw.githubusercontent.com/gijsdev/ublock-hide-yt-shorts/master/list.txt
