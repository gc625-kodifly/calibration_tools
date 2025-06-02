#!/bin/bash

xhost +local:docker  # More secure than 'xhost +'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSPACE_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

echo "workspace dir: $WORKSPACE_DIR}"

docker run -it --rm --runtime=nvidia --net=host --privileged \
  -e DISPLAY=$DISPLAY \
  -v "$WORKSPACE_DIR":/home/kodifly/workspace \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v $HOME/.Xauthority:/home/kodifly/.Xauthority:rw \
  -v /dev:/dev \
  docker.io/gc625kodifly/calibration-tools:latest