#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "usage: <import|run>"
    echo "commands:"
    echo "    import: Set up the database and import /osm-data/data.osm.pbf"
    echo "    run: Runs Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png"
    echo "environment variables:"
    echo "    THREADS: defines number of threads used for importing / tile rendering"
    echo "    NODEMEM: defines node memory for osm2pgsql"
    exit 1
fi

if [ "$1" = "import" ]; then
    # Kubernetes emptydir-volume hack
    rm -rf /var/lib/postgresql/10/main
    cp -R /var/lib/postgresql/10/main2/* /var/lib/postgresql/10/main/
    rm -rf /var/lib/postgresql/10/main2
    chown -R postgres:postgres /var/lib/postgresql/10/main
    chmod 700 /var/lib/postgresql/10/main

    # Initialize PostgreSQL
    service postgresql start
    sudo -u postgres createuser renderer
    sudo -u postgres createdb -E UTF8 -O renderer gis
    sudo -u postgres psql -c "ALTER USER renderer PASSWORD '${PGPASSWORD:-renderer}'"
    sudo -u postgres psql -d gis -c "CREATE EXTENSION postgis;"
    sudo -u postgres psql -d gis -c "CREATE EXTENSION hstore;"
    sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderer;"
    sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"

    # Download Finland if no data is provided
    if [ ! -f /osm-data/data.osm.pbf ]; then
        echo "WARNING: No import file at /data.osm.pbf, so importing Finland as default..."
        mkdir -p /osm-data
        wget -nv http://download.geofabrik.de/europe/finland-latest.osm.pbf -O /osm-data/data.osm.pbf
    fi

    # Import data
    # Tried using --drop: db size dropped to 1/3 however rendering slowed down dramatically
    exec sudo -u renderer osm2pgsql -d gis --create --slim -G --hstore -C ${NODEMEM:-2048} --number-processes ${THREADS:-4} -S /home/renderer/src/pkk_summer/pkk_maps.style /osm-data/data.osm.pbf

    exit 0
fi

function init_for_rendering() {
    # Initialize PostgreSQL and Apache
    echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars
    service postgresql start
    service apache2 restart
    sleep 5
    service apache2 restart

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /usr/local/etc/renderd.conf

    # Kubernetes emptydir volume hack
    touch /var/lib/mod_tile/planet-import-complete
    chown -R renderer:renderer /var/lib/mod_tile
    chmod a+r /var/lib/mod_tile/planet-import-complete
}

if [ "$1" = "pre-render" ]; then
    
    init_for_rendering
      
    # Start rendering & do healthcheck
    sudo -u renderer renderd -f -c /usr/local/etc/renderd.conf &
    sleep 20 && tileserver_ok=$(curl -m 30 -s http://localhost/health/)

    if [ "$tileserver_ok" = "OK" ]; then
        # Start pre-rendering
        echo
        echo "Starting pre-rendering"
        echo
        sudo -u renderer /usr/local/bin/pre_render.py
        pre_rendering=$?
        echo "Pre-rendering exited with $pre_rendering"
        service postgresql stop
        exit $pre_rendering
    else
        echo "Healthcheck failed"
        echo $tileserver_ok
        service postgresql stop
        exit 1
    fi

    exit 0
fi

if [ "$1" = "run" ]; then

    init_for_rendering
    
    # Run
    exec sudo -u renderer renderd -f -c /usr/local/etc/renderd.conf

    exit 0
fi

if [ "$1" = "run-fresh" ]; then

    init_for_rendering
    
    # Clean cache, only needed for Docker named volume 
    rm -rf /var/lib/mod_tile/*
        
    # Start pre-rendering as a background job
    sleep 20 && sudo -u renderer /usr/local/bin/pre_render.py &

    # Run
    exec sudo -u renderer renderd -f -c /usr/local/etc/renderd.conf

    exit 0
fi

echo "invalid command"
exit 1