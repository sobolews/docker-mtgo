#!/bin/bash
do_winecfg=false
do_sound=false
do_nosound=false
while [ -n "${1:-}" ]; do
   case "${1:-}" in
     --winecfg) do_winecfg=true ;;
     --sound) do_sound=true ;;
     --disable-sound) do_nosound=true ;;
   esac
   shift
done

trap "exit" INT

run() {
    echo "${@}"
    "${@}"
}

commontricks="gdiplus=builtin"

if $do_sound; then
    gst-inspect-1.0 # seems to help avoiding wine crash when loading gstreamer
    run winetricks ${commontricks} sound=pulse winegstreamer=builtin wmp=builtin
else
    run winetricks ${commontricks} sound=alsa winegstreamer=disabled wmp=disabled
fi
$do_winecfg && (run winecfg ; run wineserver -kw; sleep 1)

run wineboot

# workaround EULA picture
#find ~/.wine/drive_c/ -name 'EULA_en.rtf' -exec sed '/^{\\pict/,/^}/ d' -i "{}" \;

# workaround cert verification crash (wine 6.19)
mkdir -pv ~/.wine/host/wine/AppData/LocalLow

cd ~/.wine/drive_c/

workaround_dotnet() {
    D="/home/wine/.wine/drive_c/windows/Microsoft.NET/Framework/v4.0.30319"
    F="mscoreei.dll"
    if [ ! -f "${D}/${F}" ]; then
        echo "THERE IS AN ISSUE WITH DOTNET!"
        echo "Trying to fix it..., wait a moment"
        run wineserver -k
        cd ${D}
        run curl -fOL https://github.com/pauleve/docker-mtgo/raw/master/extra/mscoreei.dll
        return 1
    fi
}
workaround_dotnet

setup="/opt/mtgo/mtgo.exe"
setup_url="https://mtgo.patch.daybreakgames.com/patch/mtg/live/client/setup.exe?v=5"
expected_hash="a697271499c96d888042af69646be0bc"
setup_hash="$(md5sum -b ${setup} | cut -f1 -d' ')"
if [[ "${setup_hash}" != "${expected_hash}" ]]; then
    echo "WARNING: Downloading setup.exe"
    home_setup="${HOME}/setup.exe"
    if curl -fL "${setup_url}" -o ${home_setup}; then
        setup="${home_setup}"
    fi
fi

run wine ${setup}
started=0
s=6
while :; do
    sleep $s
    winedbg --command "info proc"|grep MTGO.exe >/dev/null
    r=$?
    if [ $started -eq 0 ] && [ $r -eq 0 ]; then
        echo "====== MTGO.exe has started."
        started=1
    elif [ $started -eq 1 ] && [ $r -eq 1 ]; then
        echo "====== shutting down"
        run wineserver -kw
        exit
    fi
done
