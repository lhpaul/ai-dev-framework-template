// Does not conform, with several problems reported in one result: an unknown
// screen kind (BR3), a state that declares screen-level fields (BR5), a
// navigation entry citing an unknown screen (BR7), a screen_id that is not a
// slug (BR6) and a screen with two initial states (BR4).
window.__MOCKUP_MANIFEST__ = {
  "$kind": "reproduction",
  "$status": "skeleton",
  "default_screen": "home",
  "frame": "desktop",
  "navigation": [
    {
      "label": "Main",
      "items": [
        {
          "screen_id": "home"
        },
        {
          "screen_id": "profile-settings"
        }
      ]
    }
  ],
  "screens": [
    {
      "screen_id": "home",
      "kind": "video",
      "states": [
        {
          "state_id": "default",
          "initial": true
        },
        {
          "state_id": "error-modal",
          "initial": true,
          "route": "/home/error",
          "export": "exports/error.png"
        }
      ]
    },
    {
      "screen_id": "Profile Frame 12",
      "kind": "html"
    }
  ]
};
