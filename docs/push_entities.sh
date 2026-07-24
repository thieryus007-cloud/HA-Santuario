#!/bin/bash
cd /config
printf '\xEF\xBB\xBF' > docs/entities_export.csv
grep -v "^Home Assistant notifications" www/entities_export.csv | grep -v "^-----" | grep -v "^$" | sed 's/^[0-9-]*T[0-9:.]*+[0-9:]* //' >> docs/entities_export.csv
> www/entities_export.csv
git add docs/entities_export.csv
git commit -m "Update entities export $(date +%Y-%m-%d_%H:%M)" || exit 0
git push
