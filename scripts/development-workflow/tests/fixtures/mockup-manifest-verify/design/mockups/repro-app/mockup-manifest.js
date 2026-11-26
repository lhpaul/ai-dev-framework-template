// Reproduction example for mockup-manifest-verify.sh (#2206). A Reproduction
// harvests the running app's stylesheet, so its page is not checked for token
// mirroring: index.html beside it deliberately declares other values.
window.__MOCKUP_MANIFEST__ = {
  "$kind": "reproduction",
  "$status": "skeleton",
  "default_screen": "dashboard",
  "frame": "browser",
  "navigation": [
    {
      "label": "Workspace",
      "items": [
        {
          "screen_id": "dashboard"
        },
        {
          "screen_id": "settings"
        }
      ]
    }
  ],
  "screens": [
    {
      "screen_id": "dashboard",
      "kind": "html",
      "route": "/dashboard",
      "url": "https://app.example.test/dashboard",
      "states": [
        {
          "state_id": "loaded",
          "initial": true
        },
        {
          "state_id": "empty",
          "label": "No data yet"
        }
      ]
    },
    {
      "screen_id": "settings",
      "kind": "html",
      "route": "/settings"
    }
  ]
}
