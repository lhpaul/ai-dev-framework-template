## Serialization note

ASSERT:comma_not_in_target

A comma cannot occur inside an accepted target, because the router splits every argument on commas before resolution; the `%2C` rule is defensive only.
