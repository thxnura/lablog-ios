# Screenshots

| Path | What it is |
|---|---|
| `NNN-*.png` / `NNN-*.log` | Evidence for failure NNN in [`../failure-log.md`](../failure-log.md). The `.log` is the saved output; the `.png` shows it in a Terminal window. Failure 003 has before/after app screenshots, and 010 has the receipt that showed "Location: Not available". Failure 007 was reported from my iPhone, and 013 has no image (see the log). |
| `ui/` | Every screen, captured by the UI tests (`ui-01` to `ui-33`, in flow order) |
| `ui-dark/` | The same screens in dark mode |
| `ui-v1/` | The first working build, before the redesign (ADR-013) |
| `ui-redesign-before-after.png` | The first build and the redesign side by side |
| `device-01-home-iphone17pro.png` | The app running on my iPhone 17 Pro |
| `report/` | Figures and diagrams used in the report (`fig-architecture`, `fig-sync-sequence`, `fig-03` to `fig-13`) |

UI-test screenshots can be regenerated: run the `LabLogUITests` with `-resultBundlePath`, then
`xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`.
