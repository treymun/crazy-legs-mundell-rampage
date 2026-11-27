#!/bin/sh
# Meshy calls for one kind: concept (or model+rig with "model").
#   meshy/tools/meshy_kind.sh <kind> concept|model
K=$1; STEP=$2
SP="C:/Users/treym/AppData/Local/Temp/claude/1dc8348830e70b38/f2338a2e-3874-4eaf-9e39-f1352f903b29/scratchpad"
# (MESHY_WT / MESHY_WORK: a second agent's own worktree and work folder)
WT=${MESHY_WT:-$SP/p16-meshy}; MW=${MESHY_WORK:-$SP/meshy-work}
cd "$WT"
PY=.venv/Scripts/python.exe
if [ "$STEP" = "concept" ]; then
  $PY meshy/tools/make_requests.py $K && $PY meshy/tools/meshy.py run v1/image-to-image meshy/requests/${K}_concept.json 12 ${K}_concept $MW/meshy_out/${K}_concept | tail -2
else
  $PY meshy/tools/meshy.py run v1/image-to-3d meshy/requests/${K}_model.json 35 ${K}_model $MW/meshy_out/${K}_model | tail -2 && \
  $PY meshy/tools/meshy.py run v1/rigging meshy/requests/${K}_rig.json 8 ${K}_rig $MW/meshy_out/${K}_rig | tail -2
fi
