#!/usr/bin/env bash
# Helper: wrap a history JSON payload in a summary comment body.
payload="$1"
cat <<EOF
### Automated Reviewer Loop Summary

Some summary text.

<!-- reviewer-loop-history:v1 -->
\`\`\`json
${payload}
\`\`\`

*Posted automatically by \`pr-review-loop.sh\`.*
EOF
