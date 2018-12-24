FROM ubuntu:18.04

# Based on
# https://switch2osm.org/manually-building-a-tile-server-18-04-lts/

# Set up environment and renderer user
ENV TZ=Europe/Helsinki
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN adduser --disabled-password --gecos "" renderer

# Install dependencies
RUN apt-get update && apt-get install -y libboost-all-dev git-core tar unzip wget bzip2 build-essential autoconf libtool libxml2-dev \ 
	libgeos-dev libgeos++-dev libpq-dev libbz2-dev libproj-dev munin-node munin libprotobuf-c0-dev protobuf-c-compiler libfreetype6-dev \ 
	libtiff5-dev libicu-dev libgdal-dev libcairo-dev libcairomm-1.0-dev apache2 apache2-dev libagg-dev liblua5.2-dev ttf-unifont lua5.1 \
	liblua5.1-dev libgeotiff-epsg sudo \
	make cmake g++ libboost-dev libboost-system-dev libboost-filesystem-dev libexpat1-dev zlib1g-dev libbz2-dev libpq-dev libgeos-dev \
	libgeos++-dev libproj-dev lua5.2 liblua5.2-dev \
	autoconf apache2-dev libtool libxml2-dev libbz2-dev libgeos-dev libgeos++-dev libproj-dev gdal-bin libmapnik-dev mapnik-utils python-mapnik \
	fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted ttf-unifont \
	postgresql postgresql-contrib postgis postgresql-10-postgis-2.4 \
	npm nodejs curl
USER renderer

# Install latest osm2pgsql
RUN mkdir /home/renderer/src
WORKDIR /home/renderer/src
RUN git clone https://github.com/openstreetmap/osm2pgsql.git
WORKDIR /home/renderer/src/osm2pgsql
USER renderer
RUN mkdir build
WORKDIR /home/renderer/src/osm2pgsql/build
RUN cmake ..
RUN make
USER root
RUN make install
USER renderer

# Test Mapnik
RUN python -c 'import mapnik'

# Install mod_tile and renderd
WORKDIR /home/renderer/src
RUN git clone -b switch2osm https://github.com/SomeoneElseOSM/mod_tile.git
WORKDIR /home/renderer/src/mod_tile
RUN ./autogen.sh
RUN ./configure
RUN make
USER root
RUN make install
RUN make install-mod_tile
RUN ldconfig
USER renderer

# Configure renderd
USER root
RUN sed -i 's/renderaccount/renderer/g' /usr/local/etc/renderd.conf
RUN sed -i 's/hot/tile/g' /usr/local/etc/renderd.conf
USER renderer

# Configure Apache
USER root
RUN mkdir /var/lib/mod_tile
RUN chown renderer /var/lib/mod_tile
RUN mkdir /var/run/renderd
RUN chown renderer /var/run/renderd
RUN echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf
RUN a2enconf mod_tile
COPY apache.conf /etc/apache2/sites-available/000-default.conf
USER renderer

# Install Carto
USER root
RUN npm install -g carto
USER renderer

# Configure stylesheet
WORKDIR /home/renderer/src
RUN git clone https://github.com/myrtillus/openstreetmap-carto.git
WORKDIR /home/renderer/src/openstreetmap-carto
RUN git checkout pkk_summer
RUN wget -nv https://raw.githubusercontent.com/Myrtillus/osm2pgsql_style/master/pkk_maps.style
RUN carto -v
RUN carto project.mml > mapnik.xml

# Load shapefiles
WORKDIR /home/renderer/src/openstreetmap-carto
RUN ./get-shapefiles.sh

# Start running
USER root
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []