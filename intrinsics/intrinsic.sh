#!/usr/bin/env bash
#
# One-click camera-calibration script (Zenity-only UI)
#
# Dependencies: zenity, mrgingham, vnl-filter, feedgnuplot, mrcal

set -euo pipefail

###############################################################################
# 1.  Ask for the folder containing JPGs
###############################################################################
JPG_DIR=${1:-$(zenity --file-selection --directory \
                    --title="Select folder containing the JPEG images")}
[[ -z "$JPG_DIR" ]] && exit 0      # user pressed “Cancel”

###############################################################################
# 2.  Start a live log window (Zenity)
###############################################################################
LOGFILE=$JPG_DIR/calib.log

# Tail the file *into* zenity.  The forked shell keeps the pipe open.
(
    # give zenity an initial line so the window appears immediately
    echo "Opening log ..."; sleep 0.3
    tail -F "$LOGFILE"
) | zenity --text-info --title="Camera-calibration log" \
           --font="Monospace 10" --auto-scroll \
           --width=900 --height=600 &
ZENITY_PID=$!

# Ensure the Zenity window is closed and the temp file removed on exit
cleanup() {
    kill "$ZENITY_PID" 2>/dev/null || true
    rm -f "$LOGFILE"
}
trap cleanup EXIT

# Mirror everything we print to the logfile *and* to the main terminal
exec > >(tee -a "$LOGFILE") 2>&1

echo "### Calibration started $(date)"
echo "Image folder: $JPG_DIR"
cd "$JPG_DIR"

###############################################################################
# 3.  Detect chessboard corners
###############################################################################
if [[ ! -f corners.vnl ]]; then
    echo "Finding chessboard corners ..."
    mrgingham --jobs 20 --gridn 14 '*.jpg' > corners.vnl
else
    echo "Using existing corners.vnl cache"
fi

###############################################################################
# 4.  Count usable images
###############################################################################
count=$(
  < corners.vnl vnl-filter --has x -p filename | uniq | grep -v '#' | wc -l
)
echo "Images with valid corners: $count"

###############################################################################
# 5.  Generate coverage plot
###############################################################################
echo "Generating coverage plot ..."
< corners.vnl \
  vnl-filter -p x,y | \
  feedgnuplot --exit --domain --square \
              --set 'xrange [0:4096] noextend' \
              --set 'yrange [2460:0] noextend' \
              --hardcopy ret_coverage.png \
              --title "Image coverage using $count images"

###############################################################################
# 6.  Calibrate with OpenCV 4 and OpenCV 8
###############################################################################
for MODEL in 4 8; do
  echo
  echo "=== Calibrating OpenCV${MODEL} ==="

  calib_out=$(mrcal-calibrate-cameras \
              --corners-cache corners.vnl \
              --lensmodel "LENSMODEL_OPENCV${MODEL}" \
              --focal 1800 \
              --object-spacing 0.06 \
              --object-width-n 14 \
              '*.jpg' \
              2>&1 | tee -a "$LOGFILE")  

    ########################################################################
    #  Parse the numbers
    ########################################################################
    RMS_ERROR=$(   awk -F': *' '/RMS reprojection error/          {print $2}' <<<"$calib_out" \
                | awk '{print $1}' )
    WORST_ERROR=$( awk -F': *' '/Worst residual \(by measurement\)/{print $2}' <<<"$calib_out" \
                | awk '{print $1}' )

    echo "  ↳ RMS reprojection error = ${RMS_ERROR}px"
    echo "  ↳ Worst residual         = ${WORST_ERROR}px"

    ########################################################################
    #  Warn the operator if RMS is above threshold
    ########################################################################
    if awk -v r="$RMS_ERROR" 'BEGIN{exit (r>0.4)?0:1}'; then
        zenity --warning --title="Calibration quality warning" \
            --text="High RMS reprojection error: ${RMS_ERROR}px (limit 0.4).\n\
                        Please review ret_coverage.png to ensure full board coverage."
    fi


  mv camera-0.cameramodel "opencv${MODEL}.cameramodel"

  # Residual histogram
  echo "  • Saving histogram plot"
  mrcal-show-residuals \
      --histogram \
      --set 'xrange [-2:2]' \
      --unset key \
      --binwidth 0.1 \
      --title "OPENCV${MODEL} residuals" \
      --hardcopy "cv${MODEL}_histogram.png" \
      "opencv${MODEL}.cameramodel"

  # Residual magnitudes
  echo "  • Saving magnitudes plot"
  mrcal-show-residuals \
      --magnitudes \
      --set 'cbrange [0:1.5]' \
      --hardcopy "cv${MODEL}_magnitudes.png" \
      "opencv${MODEL}.cameramodel"

  # Residual directions
  echo "  • Saving directions plot"
  mrcal-show-residuals \
      --directions \
      --set 'cbrange [0:1.5]' \
      --hardcopy "cv${MODEL}_directions.png" \
      "opencv${MODEL}.cameramodel"
done

###############################################################################
# 7.  Collect results
###############################################################################
echo
echo "Collecting outputs ..."
mkdir -p results
mv -t results -- *.png *.cameramodel

sleep 2
# Show the folder in Nautilus / Dolphin / Thunar … whatever the user has
xdg-open "$JPG_DIR/results" >/dev/null 2>&1 &

echo "Done!  Results saved to: $JPG_DIR/results"
echo "### Calibration finished $(date)"