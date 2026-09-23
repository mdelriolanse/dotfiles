
# Browser verification

When implementing or fixing anything in a web application (UI, layout, styling, routing, client state, or rendered data), verify the work in the browser before declaring the task complete.

- Exercise the changed feature end to end: click, type, submit, navigate. A screenshot is not verification.
- Check every page and route that shares the state, data, or components you touched.
- Hunt for regressions in the surrounding flows.
- Verify the edge states the change touches (empty, error, route and flag variants).
- When layout or styling changed, check desktop and mobile.
- If verification finds a problem, fix it and re-verify.

If no browser tools are available, verify through the closest substitute (tests, curl, a render script) and say what you could not verify.
