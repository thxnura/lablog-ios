# Screenshots

| Path | What it is |
|---|---|
| `NNN-*.png` / `NNN-*.log` | Evidence for failure NNN in [`../failure-log.md`](../failure-log.md). The `.log` is the saved output; the `.png` shows it in a Terminal window. Failure 003 has before/after app screenshots, and 010 has the receipt that showed "Location: Not available". Failures 007 and 020 were reported from my iPhone (`020-popover-no-sign-in.png` is my phone's screenshot; `020-popover-sign-in-id` is the test failure met while fixing it), 017b to 017e are later dropped taps of the 017 kind, and 013 has no image (see the log). Failures 024, 026 and 028 were reported in words from my iPhone, so they have no image; 029b and 030b are frames from the UI test's screen recording (the 401 in the editor; Save still spinning). |
| `ui/` | Every screen, captured by the UI tests (`ui-01` to `ui-40`, in flow order; `ui-21` to `ui-23` and `ui-12b` are sign-in, sign-out and the restore, `ui-37` to `ui-40` the lecturer's labs) |
| `ui-dark/` | A selection of the same screens in dark mode |
| `ui-v1/` | The first working build, before the redesign (ADR-013) |
| `ui-redesign-before-after.png` | The first build and the redesign side by side |
| `device-01-home-iphone17pro.png` | The app running on my iPhone 17 Pro |
| `report/` | Figures and diagrams used in the report (`fig-architecture`, `fig-sync-sequence`, `fig-03` to `fig-14`) |

UI-test screenshots can be regenerated: run the `LabLogUITests` with `-resultBundlePath`, then
`xcrun xcresulttool export attachments --path <bundle> --output-path <dir>`. The bundle also holds
a screen recording of each UI test, which is where 029b and 030b came from.
