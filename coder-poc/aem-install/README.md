# AEM Shared Install Files

Place the following proprietary Adobe files here:

| File | Source | Required |
|------|--------|----------|
| `aem-quickstart.jar` | [Adobe Software Distribution](https://experience.adobe.com/#/downloads/content/software-distribution/en/aem.html) | Yes |
| `license.properties` | Provided with your AEM license | Yes |

These files are mounted **read-only** into every AEM workspace at `/opt/aem-install/`.
The JAR is referenced directly (not copied), saving ~1 GB disk per workspace.

## Setup

```bash
# 1. Place files in this directory
cp /path/to/aem-quickstart-6.5.x.jar ./aem-quickstart.jar
cp /path/to/license.properties ./license.properties

# 2. Push the template (if changed) and restart workspaces
coder templates push aem-workspace
coder restart <owner>/<workspace>
```

## Notes

- These files are `.gitignore`d — they must NOT be committed (Adobe proprietary license)
- AEM 6.5 requires the JAR name to be exactly `aem-quickstart.jar`
- Each workspace gets its own `crx-quickstart/` on persistent storage
- `license.properties` is symlinked into each AEM instance directory at startup
