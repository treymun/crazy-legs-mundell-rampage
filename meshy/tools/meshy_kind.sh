#!/bin/sh
# Meshy calls for one kind: concept (or model+rig with "model").
#   meshy/tools/meshy_kind.sh <kind> concept|model
K=$1; STEP=$2
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
cd "$SP/p16-meshy"
PY=.venv/Scripts/python.exe
if [ "$STEP" = "concept" ]; then
  $PY meshy/tools/make_requests.py $K && $PY meshy/tools/meshy.py run v1/image-to-image meshy/requests/${K}_concept.json 12 ${K}_concept ../meshy-work/meshy_out/${K}_concept | tail -2
else
  $PY meshy/tools/meshy.py run v1/image-to-3d meshy/requests/${K}_model.json 35 ${K}_model ../meshy-work/meshy_out/${K}_model | tail -2 && \
  $PY meshy/tools/meshy.py run v1/rigging meshy/requests/${K}_rig.json 8 ${K}_rig ../meshy-work/meshy_out/${K}_rig | tail -2
fi
