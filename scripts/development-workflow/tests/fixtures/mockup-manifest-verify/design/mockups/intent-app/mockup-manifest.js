// Design intent example for mockup-manifest-verify.sh (#2206).
// The file assigns one plain JSON object; only comments may surround it.
window.__MOCKUP_MANIFEST__ = {
  "$kind": "design-intent",
  "$status": "complete",
  "default_screen": "login-email",
  "frame": "phone",
  "viewports": [
    {
      "id": "phone",
      "label": "Phone",
      "width": 390,
      "height": 844
    },
    {
      "id": "tablet",
      "label": "Tablet",
      "width": 820,
      "height": 1180
    }
  ],
  "navigation": [
    {
      "label": "Authentication",
      "items": [
        {
          "screen_id": "login-email",
          "items": [
            {
              "screen_id": "login-code",
              "label": "Code step",
              "items": [
                {
                  "screen_id": "onboarding-illustration",
                  "label": "Welcome"
                }
              ]
            }
          ]
        }
      ]
    },
    {
      "label": "App",
      "items": [
        {
          "screen_id": "home"
        }
      ]
    }
  ],
  "screens": [
    {
      "screen_id": "login-email",
      "kind": "html",
      "route": "/login",
      "title": "Sign in",
      "design_ref": "Login / Email v2",
      "state_label": "Email form",
      "states": [
        {
          "state_id": "empty",
          "initial": true
        },
        {
          "state_id": "filled",
          "label": "Email typed"
        },
        {
          "state_id": "invalid",
          "label": "Validation error",
          "title": "Sign in - check your email"
        }
      ]
    },
    {
      "screen_id": "login-code",
      "kind": "html",
      "route": "/login/code",
      "nav_screen": "login-email",
      "states": [
        {
          "state_id": "empty",
          "initial": true
        },
        {
          "state_id": "resend-ready",
          "label": "Resend available"
        }
      ]
    },
    {
      "screen_id": "home",
      "kind": "html",
      "route": "/",
      "dom_id": "home-screen"
    },
    {
      "screen_id": "onboarding-illustration",
      "kind": "image",
      "export": "exports/onboarding-illustration.png",
      "title": "Welcome illustration"
    }
  ]
};
