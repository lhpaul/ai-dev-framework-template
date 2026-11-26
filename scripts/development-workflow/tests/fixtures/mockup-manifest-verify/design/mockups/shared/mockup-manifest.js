// Deliberately invalid: the tree check skips mockups/shared/, the shared
// viewer folder, so this file must never be verified or listed.
window.__MOCKUP_MANIFEST__ = (function () {
  return { "$kind": "design-intent" };
})();
