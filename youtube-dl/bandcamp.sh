#!/usr/bin/env bash

#################################################################################
# VERSION   : V1.01.001                                                         #
# RELEASED  : 22 June 2020                                                      #
# REQUIRES  : elinks, wget, youtube-dl                                          #
# FORMAT    : ./bandcamp.sh <(req) BANDCAMP URL> <(opt) OUTPUT AUDIO FORMAT>    #
#################################################################################
# youtube-dl wrapper script that takes a bandcamp artist URL and downloads all  #
# the albums and artwork that it can find                                       #
#################################################################################

DEBUG=0

# Get the URL and audio format from the CLI parameters
URL=$( echo $1 | sed 's/\\r//g' )

if [ -z $2 ]; then
    FORMAT='mp3'
else
    FORMAT=$( echo $2 | sed 's/\\r//g' )
fi

# Parse the URL to get the artist name
HOSTNAME=$( echo "$URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||' )
ARTIST=$( echo ${HOSTNAME//\.bandcamp\.com} | sed -e 's/[^A-Za-z0-9._-]//g' )

if [ -z ${ARTIST} ]; then
    echo "ERROR: Invalid Bandcamp URL"
    exit 1
fi

if [ ${DEBUG} -eq 1 ]; then
    echo "URL       : ${URL}" 
    echo "ARTIST    : ${ARTIST}"
    echo "AUDIO     : ${FORMAT}"
    echo ""
fi

# Get a list of albums from the main page
ALBUMS=($(elinks --dump --no-numbering ${URL} | grep -E '\.com\/(album|track)' | grep -vE '(\?|\#)' | sed 's/.*https/https/g' | cut -d " " -f 5 | uniq))

if [ -z ${ALBUMS} ]; then
    echo "ERROR: No albums or tracks found"
    exit 1
fi

# Loop through the albums
for ALBUMURL in "${ALBUMS[@]}"
do
    # Download the songs
    PLAYLISTNAME=$(basename ${ALBUMURL})
    if [ ${DEBUG} -eq 1 ]; then
        echo "ALBUM     : ${PLAYLISTNAME}"
    else
        youtube-dl --quiet --rm-cache-dir --newline --extract-audio --audio-format ${FORMAT} --output "/tmp/${ARTIST}/${PLAYLISTNAME}/%(playlist_index)s - %(title)s.%(ext)s" ${ALBUMURL}
    fi

    # Download the album artwork (a*10.jpg, a*16.jpg)
    IMAGES=($(elinks --dump --no-numbering ${ALBUMURL} | grep -E 'a[^\/]+\.(jpg|png)$' | cut -d " " -f 5 | uniq))

    if [ ! -z ${IMAGES} ]; then
        for IMAGEURL in "${IMAGES[@]}"
        do
            if [ ${DEBUG} -eq 1 ]; then
                echo "IMAGE     : ${IMAGEURL}"
            else
                wget --quiet --directory-prefix=/tmp/${ARTIST}/${PLAYLISTNAME} ${IMAGEURL}
            fi
        done
    fi
	if [ ${DEBUG} -eq 1 ]; then
	    echo ""
	fi
done

if [ ${DEBUG} -eq 1 ]; then
    exit
else
    # Zip all the files into one
    cd /tmp/${ARTIST}
    zip ${ARTIST}.zip *

    # Move it to the /tmp folder
    mv ${ARTIST}.zip /tmp

    # Clean up
    rm -Rf /tmp/${ARTIST}

    # Echo out the path to the zip file as the exit
    echo "/tmp/${ARTIST}.zip"
    exit 0
fi
