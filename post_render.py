#!/usr/bin/python
# -----------------------------------------------------------------
# Pre-rendering of selected regions of map to mod_tile  cache
# -----------------------------------------------------------------

import sys
import subprocess
import math

# Default number of rendering threads to spawn, should be roughly equal to number of CPU cores available
NUM_THREADS = 1
MAP_DEFAULT_NAME = 'pkk'

def deg2num(lat_deg, lon_deg, zoom):
  lat_rad = math.radians(lat_deg)
  n = 2.0 ** zoom
  xtile = int((lon_deg + 180.0) / 360.0 * n)
  ytile = int((1.0 - math.log(math.tan(lat_rad) +
						(1 / math.cos(lat_rad))) / math.pi) / 2.0 * n)
  return (xtile, ytile)

def render_tiles_per_zoom(bbox, zoom, map_name=MAP_DEFAULT_NAME, num_threads=NUM_THREADS, tms_scheme=False):
#	print 'render_tiles_per_zoom(', bbox, zoom, map_name, ' )'

	(minX, minY) = deg2num(bbox[3], bbox[0], zoom)
	(maxX, maxY) = deg2num(bbox[1], bbox[2], zoom)

	render_cmd_args = 'render_list -a -m %s -x %s -y %s -X %s -Y %s -z %s -Z %s -n %s' \
            % (map_name,
               minX, minY,
               maxX, maxY,
               zoom,
               zoom,
               num_threads)
	return subprocess.check_output(render_cmd_args, shell=True)

def render_tiles(bbox, minZoom=1, maxZoom=18, num_threads=NUM_THREADS, map_name=MAP_DEFAULT_NAME, tms_scheme=False):
#	print 'render_tiles( ', bbox, minZoom, maxZoom, map_name, ' )'

	for zoom in range(minZoom, maxZoom + 1):
		res = render_tiles_per_zoom(bbox, zoom, map_name, num_threads)
		print res

# Same for @2x
MAP_2X = 'pkk_retina'

# Tampere
bbox = (23.0 , 61 , 24.44 , 61.59293)
render_tiles(bbox, 13, 16)

# Helsinki
bbox = (24, 60, 25.3, 60.4)
render_tiles(bbox, 13, 16)

# Tampere
bbox = (23.0 , 61 , 24.44 , 61.59293)
render_tiles(bbox, 13, 16, NUM_THREADS, MAP_2X)

# Helsinki
bbox = (24, 60, 25.3, 60.4)
render_tiles(bbox, 13, 16, NUM_THREADS, MAP_2X)

sys.exit(0)