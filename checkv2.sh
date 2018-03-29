#!/bin/bash

# flac-rippien laaduntarkistusscripti, ripit ladataan hakemistoon
# $flacroot ja valmiit siirretään hakemistoon $wappudb

flacroot=/home/flac/upload
wappudb=/home/wappuradio/db

# permissionit kuntoon
find $flacroot -type f -exec chmod 644 {} +
find $flacroot -type d -exec chmod 755 {} +
# merkistösanity(loss)
convmv --notest -f ISO-8859-15 -t UTF-8 $flacroot/* &>/dev/null

# yksittäisen kansion tarkistus

function check {
    cd "$1" 2>/dev/null  || exit 2
    #merkistösanity
    convmv --notest -f ISO-8859-15 -t UTF-8 * &>/dev/null
    CUES=$(ls *.cue 2>/dev/null|wc -l)
    if [[ "$CUES" -ne "1" ]]; then
      error=1
      return 1
    fi
    LOGS=$(ls *.log 2>/dev/null|wc -l)
    if [[ "$LOGS" -ne "1" ]]; then
      error=2
      return 1
    fi
    M3US=$(ls *.m3u 2>/dev/null|wc -l)
    FLACS=$(ls *.flac 2>/dev/null|wc -l)
    FILES=$(grep -a -e "^FILE" *.cue 2>/dev/null|wc -l)
    if [[ "$FILES" -ne "$FLACS" ]]; then
      error=3
      return 1
    fi
    UTF16=$(file *.log|grep UTF-16|wc -l)
    if [[ "$UTF16" -eq "1" ]]; then
      TEMP=$(mktemp)
      #chown flac:flac $TEMP
      #chmod 755 $TEMP
      iconv -f UTF-16 -t UTF-8 *.log > $TEMP
      mv $TEMP *.log
      chown flac:flac *.log
      chmod 644 *.log
    fi
    DB=$(grep -a "Track not present" *.log 2>/dev/null|wc -l)
    if [[ "$DB" -ne "0" ]]; then
      error=4
      return 1
    fi
    AR=$(grep -a "Accurately ripped (" *.log 2>/dev/null|wc -l)
    if [[ "$AR" -ne "$FLACS" ]]; then
      error=5
      return 1
    fi
    error=0
    return 0
}

# virheenkäsittely

function status {
    case $1 in
    1)
      out="no cuesheet found."
      ;;
    2)
      out="no logfile found."
      ;;
    3)
      out="number of flac-files doesn't match cuesheet."
      ;;
    4)
      out="some tracks are not present in AccurateRip database."
      ;;
    5)
      out="not accurately ripped."
      ;;
    0)
      out="rip OK"
      ;;
    esac
    echo $out
    return 0
}

# päälooppi, joka tarkastaa $flacrootissa olevat levyt

cd "$flacroot"
if [[ "$(ls |wc -l)" -ne "0" ]]; then
for ripdir in */; do
  # täytyy tarkastaa molemmat, uploadin dirri ja NAS listaus kun NAS ei päällä
  INDBLOCAL=$(find "$wappudb"/"$ripdir" -type d 2>/dev/null |wc -l)
  ripname=$(echo "${ripdir::-1}")
  INDB=$(cat /home/wappuradio/wappuradio/dblist.txt |grep "$ripname" 2>/dev/null |wc -l)
  if [ "$INDB" -ne "0" ] || [ "$INDBLOCAL" -ne "0" ]; then
    echo "Checking $ripdir"
    echo "  Skipping, already in database."
    continue
  fi
  subdirs=$(find "$ripdir"CD* -type d 2>/dev/null)
  nsubdirs=$(echo "$subdirs" 2>/dev/null|wc -l)
  if [[ "nsubdirs" -ne "1" ]]; then
    echo "Checking $ripdir (multi CD)"
    cd "$ripdir"
    okdiscs=0
    for subdir in */; do
      check "$subdir"
      echo "  $subdir" $(status "$error")
      if [[ "$error" -eq "0" ]]; then
        let "okdiscs += 1"
      fi
      cd ..
    done
    if [[ "okdiscs" -ne "nsubdirs" ]]; then
      echo "  Multi CD rip not OK, errors found."
      cd "$flacroot"
      continue
    else
      echo "  Multi CD rip OK, moving to database."
    fi
    cd "$flacroot"
  else
    echo "Checking $ripdir"
    check "$ripdir"
    if [[ "$error" -ne "0" ]]; then
      echo "  Rip not OK," $(status "$error")
      cd "$flacroot"
      continue
    else
      echo "  Rip OK, moving to database"
    fi
    cd "$flacroot"
  fi
  mv "$ripdir" "$wappudb" 2>/dev/null || echo "Already in database."
  # irkkibotille notice
  sleep 1
  echo "/notice #radiontoimitus :$ripdir" > "/home/wappuradio/irc/irc.nebula.fi/#radiontoimitus/in"
done

# päivitetään listaus ja lähetetään munkille

ls /home/wappuradio/db > /home/wappuradio/temp.list
cat /home/wappuradio/temp.list |wc -l > /home/flac/dbcount.txt
cp /home/wappuradio/temp.list /home/flac/dblist.txt
cp /home/wappuradio/temp.list /home/flac/dblist.csv
sed -i -e 's/^/"/;s/ - [0-9]*$//g;s/$/"/;s/ - /","/' /home/flac/dblist.csv
sed -i '1s/^/"Artisti","Albumi"\n/' /home/flac/dblist.csv
#rip munkki
#scp -C /home/flac/dblist.txt wappuradio@munkki.wappuradio.fi:/home/www/intra/dblist.txt
#scp -C /home/flac/dblist.csv wappuradio@munkki.wappuradio.fi:/home/www/intra/dblist.csv
#scp -C /home/flac/dbcount.txt wappuradio@munkki.wappuradio.fi:/home/www/intra/dbcount.txt
#scp -C /home/flac/{dblist.txt,dblist.csv,dbcount.txt} upload@sauron.wappuradio.fi:/var/www/intra/
#rsync -a /home/wappuradio/db 130.230.31.82:/srv/nfs/music
fi
