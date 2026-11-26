// Does not conform: if this file were executed (for example by Node), the
// first statement would create a file. The verify script reads manifests as
// data and never runs them, so no file is ever created.
require("fs").writeFileSync("executed-on-load.marker", "the manifest ran");
window.__MOCKUP_MANIFEST__ = {
  "$kind": "reproduction",
  "$status": "complete",
  "default_screen": "home",
  "frame": "phone",
  "navigation": [],
  "screens": [{ "screen_id": "home", "kind": "html" }]
};
