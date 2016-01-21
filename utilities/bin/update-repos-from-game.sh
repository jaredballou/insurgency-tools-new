#!/bin/bash
################################################################################
# Insurgency Data Extractor
# (C) 2014,2015,2016 Jared Ballou <instools@jballou.com>
# Extracts all game file information to the data repo
################################################################################

# Which commands to run
EXTRACTFILES=0
GETMAPS=0
REMOVEBLACKLISTMAPS=0
DECOMPILEMAPS=1
SYNC_MAPS_TO_DATA=1
COPY_MAP_FILES_TO_DATA=1
CONVERT_VTF=0
MAPDATA=1
FULL_MD5_MANIFEST=0
CLEAN_MANIFEST=1
SORT_MANIFEST=0
GITUPDATE=0


# Get OS
SYSTEM=$(uname -s)

# Script name and directory
SCRIPTNAME=$(basename $(readlink -f "${BASH_SOURCE[0]}"))
SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# insurgency-tools dir
REPODIR="$(cd "${SCRIPTDIR}/../.." && pwd)"
# Game dir
GAMEDIR="$(cd "${REPODIR}/../serverfiles/insurgency" && pwd)"
# Data dir
DATADIR="${REPODIR}/public/data"
# Maps source dir
MAPSDIR="${GAMEDIR}/maps"

# MD5 manifest file
MANIFEST_FILE="${DATADIR}/manifest.md5"

# Custom maps URL
MAPSRCURL="rsync://ins.jballou.com/fastdl/maps/"

# Get current version from steam.inf
VERSION="$(grep -oP -i 'PatchVersion=([0-9\.]+)' "${GAMEDIR}/steam.inf" | cut -d'=' -f2)"

# RSYNC command
RSYNC="rsync -av"
# BSPSRC command
BSPSRC="java -cp ../../thirdparty/bspsrc/bspsrc.jar info.ata4.bspsrc.cli.BspSourceCli -no_areaportals -no_cubemaps -no_details -no_occluders -no_overlays -no_rotfix -no_sprp -no_brushes -no_cams -no_lumpfiles -no_prot -no_visgroups"
# Pakrat command
PAKRAT="java -jar ../../thirdparty/pakrat/pakrat.jar"
# VPK Converter
if [ "${SYSTEM}" == "Linux" ]; then
	VPK="${SCRIPTDIR}/vpk.php"
else
	VPK="${GAMEDIR}/../bin/vpk"
fi
# VTF2TGA Converter
if [ "${SYSTEM}" == "Linux" ]; then
	VTF2TGA="${SCRIPTDIR}/vtf2tga"
else
	VTF2TGA="${SCRIPTDIR}/VTFCmd.exe"
fi
# This version theater dir
TD="${DATADIR}/theaters/${VERSION}"
# This version playlists dir
PD="${DATADIR}/playlists/${VERSION}"
# Maps blacklist (will skip downloads and clean up date based upon these items)
BLACKLIST="${DATADIR}/thirdparty/maps-blacklist.txt"

# Directories to extract from bsp files using Pakrat
MAPSRCDIRS="materials/vgui/* materials/overviews/* resource/* maps/*.txt"

# List the paths to extract from the VPK files
declare -A VPKPATHS
VPKPATHS["insurgency_misc_dir"]="scripts/theaters:${TD} scripts/playlists:${PD} resource:${DATADIR}/resource maps:${DATADIR}/maps"
VPKPATHS["insurgency_materials_dir"]="materials/vgui:${DATADIR}/materials/vgui materials/overviews:${DATADIR}/materials/overviews"
# If the theater directory for this version is missing, extract files
if [ ! -d "${TD}" ]
then
	EXTRACTFILES=1
fi

# If theater files for this Steam version don't exist, unpack desired VPK files and copy theaters to data
# This is not the "best" way to track versions, but it works for now
function extractfiles()
{
	echo "> Extracting VPK files"
	for k in "${!VPKPATHS[@]}"
	do
		echo ">> Processing ${k}..."
		for PAIR in ${VPKPATHS[$k]}
		do
			IFS=':' read -r -a PATHS <<< "${PAIR}"
			echo ">>> Extracting ${PATHS[0]} -> ${PATHS[1]}"
			$VPK "${GAMEDIR}/${k}.vpk" "${PATHS[0]}" "${PATHS[1]}"
		done
	done
}

function getmaps()
{
	# Copy map source files
	echo "> Updating maps from repo"
	for EXT in bsp nav txt
	do
		$RSYNC -z --progress --ignore-existing --exclude='archive/' --exclude-from "${BLACKLIST}" "${MAPSRCURL}/*.${EXT}" "${GAMEDIR}/maps/"
	done
}

function removeblacklistmaps()
{
	echo "> Removing blacklisted map assets from data directory"
	for MAP in $(cut -d'.' -f1 "${BLACKLIST}")
	do
		for FILE in $(ls "${DATADIR}/maps/src/${MAP}_d.vmf" ${DATADIR}/maps/{parsed,navmesh,.}/${MAP}.* ${DATADIR}/resource/overviews/${MAP}.* "${GAMEDIR}/maps/${MAP}.bsp.zip" 2>/dev/null)
		do
			delete_datadir_file "${FILE}"
		done
	done
}

function decompilemaps()
{
	echo "> Updating decompiled maps as needed"
	MAPSRCDIRS_EGREP=$(echo $(for SRCDIR in $(echo $MAPSRCDIRS | sed -e 's/\*[^ ]*//g'); do echo -ne "${SRCDIR} "; done) | sed -e 's/ /\|/g' -e 's/\//\\\//g')
	for MAP in ${MAPSDIR}/*.bsp
	do
		# Don't do symlinks
		if [ -L "${MAP}" ]; then continue; fi
		if [ "$(echo "${MAP}" | sed -e 's/ //g')" != "${MAP}" ]
		then
			#echo "> SPACE"
			continue
		fi
		BASENAME=$(basename "${MAP}" .bsp)
		if [ $(grep -c "^${BASENAME}\..*\$" "${BLACKLIST}") -eq 0 ]
		then
			SRCFILE="${DATADIR}/maps/src/${BASENAME}_d.vmf"
			ZIPFILE="${MAP}.zip"
			if [ "${SRCFILE}" -ot "${MAP}" ]; then
				echo ">> Decompile ${MAP} to ${SRCFILE}"
				$BSPSRC "${MAP}" -o "${SRCFILE}"
				add_manifest_md5 "${SRCFILE}"
			fi
			MAPSRCLIST=$($PAKRAT -list "${MAP}" | egrep -i "^(${MAPSRCDIRS_EGREP})" | awk '{print $1}')
			echo $MAPSRCLIST
			if [ "$ZIPFILE" -ot "${MAP}" ]; then
				echo ">> Extract files from ${MAP} to ${ZIPFILE}"
				$PAKRAT -dump "${MAP}"
				echo ">> Extracting map files from ZIP"
#				unzip -o "${ZIPFILE}" -x '*.vhv' 'maps/*' 'models/*' 'scripts/*' 'sound/*' 'materials/maps/*' -d "${GAMEDIR}/maps/out"
				for SRCDIR in $MAPSRCDIRS; do
					unzip -o "${ZIPFILE}" "${SRCDIR}" -d "${DATADIR}/" 2>/dev/null
				done
			fi
		fi
	done
}

function sync_maps_to_data()
{
	echo "> Synchronizing extracted map files with data tree"
	for SRCDIR in $MAPSRCDIRS
	do
		if [ -e "${GAMEDIR}/maps/out/${SRCDIR}" ]
		then
			echo ">> Syncing ${GAMEDIR}/maps/out/${SRCDIR} to ${DATADIR}/${SRCDIR}"
			$RSYNC -c "${GAMEDIR}/maps/out/${SRCDIR}" "${DATADIR}/${SRCDIR}"
		fi
	done
}

function copy_map_files_to_data()
{
	echo "> Copying map text files"
	for TXT in ${GAMEDIR}/maps/*.txt ${GAMEDIR}/maps/out/maps/*.txt
	do
		BASENAME=$(basename "${TXT}" .txt)
		if [ $(grep -c "^${BASENAME}\..*\$" "${BLACKLIST}") -eq 0 ]
		then
			cp "${TXT}" "${DATADIR}/maps/"
			add_manifest_md5 "${DATADIR}/maps/${BASENAME}.txt"
		fi
	done
}

function convert_vtf()
{
	echo "> Create PNG files for VTF files"
	for VTF in $(find "${DATADIR}/materials/" -type f -name "*.vtf")
	do
		DIR=$(dirname "${VTF}")
		PNG="${DIR}/$(basename "${VTF}" .vtf).png"
		if [ ! -e ${PNG} ]
		then
			echo "${PNG} missing"
		fi
		if [ "$(get_manifest_md5 "${VTF}")" != "$(get_file_md5 "${VTF}")" ]
		then
			echo "> Processing ${VTF} to ${PNG}"
			if [ "${SYSTEM}" == "Linux" ]; then
				"${VTF2TGA}" "${VTF}" "${PNG}"
			else
				WINFILE=$(echo $VTF | sed -e 's/\//\\/g' -e 's/\\$//')
				WINPATH=$(echo $DIR | sed -e 's/\//\\/g' -e 's/\\$//')
				"${VTF2TGA}" -file "${WINFILE}" -output "${WINPATH}" -exportformat "png"
			fi
			add_manifest_md5 "${VTF}"
			add_manifest_md5 "${PNG}"
		fi
	done
}
# Get relative path inside data directory for a file
function get_datadir_path()
{
	if [ -f "${1}" ]
	then
		FILE="${1}"
	else
		if [ -f "${DATADIR}/${1}" ]
		then
			FILE="${DATADIR}/${1}"
		else
			return
		fi
	fi
	echo $(readlink -f "${FILE}") | sed -e "s|^${DATADIR}/||"
}
# Display MD5sum of a file
function get_file_md5()
{
	md5sum "${1}" | awk '{print $1}'
}
# Get existing MD5sum from manifest
function get_manifest_md5()
{
	FILE="$(get_datadir_path "${1}")"
	echo $(grep "^${FILE}:.*" "${MANIFEST_FILE}" | cut -d':' -f2)
}
# Add file to MD5 manifest
function add_manifest_md5()
{
	FILE="$(get_datadir_path "${1}")"
	OLDMD5="$(get_manifest_md5 "${1}")"
	if [ "${OLDMD5}" == "" ]
	then
		echo "> Adding ${FILE} to manifest.md5"
		cd "${DATADIR}" && md5sum "${FILE}" | sed -e 's/^\([^ \t]\+\)[ \t]\+\([^ \t]\+\)/\2:\1/' >> "${MANIFEST_FILE}"
		SORT_MANIFEST=1
	else
		NEWMD5="$(get_file_md5 "${DATADIR}/${FILE}")"
		if [ "${OLDMD5}" != "${NEWMD5}" ]
		then
			echo "> Updating ${FILE} in manifest.md5"
			sed -i -e "s|^\(${FILE}:\).*\$|\1${NEWMD5}|" "${MANIFEST_FILE}"
		fi
	fi
}
# Remove file from MD5 manifest
function remove_manifest_md5()
{
	FILE="$(get_datadir_path "${1}")"
	echo "> Removing ${FILE} from manifest.md5"
	sed -i "|${FILE}:.*|d" "${MANIFEST_FILE}"
}

# Delete file from datadir, will also update MD5 manifest
function delete_datadir_file()
{
	FILE="$(get_datadir_path "${1}")"
	if [ -f "${DATADIR}/${FILE}" ]
	then
		echo "> Deleting ${DATADIR}/${FILE}"
		remove_manifest_md5 "${FILE}"
		rm ${DATADIR}/${FILE}
	fi
}
# Rebuild entire MD5 manifest
function generate_manifest()
{
	echo "> Generating MD5 manifest"
	cd ${DATADIR}
	touch "${MANIFEST_FILE}"
	for FILE in $(find */ -type f | sort -u)
	do
		echo ">> Processing ${FILE}"
		add_manifest_md5 "${FILE}"
	done
	echo "> Generated MD5 manifest"
}

# Clean missing files from MD5 manifest
function clean_manifest()
{
	echo "> Cleaning MD5 manifest"
	for FILE in $(cut "${MANIFEST_FILE}" -d':' -f1); do
		if [ ! -e "${DATADIR}/${FILE}" ]; then
			echo ">> Removing ${FILE} from manifest"
			remove_manifest_md5 "${FILE}"
		fi
	done
	echo "> Cleaned MD5 manifest"
}
# Perform Git update
function gitupdate()
{
	echo "> Adding everything to Git and committing"
	OD=$(pwd)
	cd "${DATADIR}"
	git pull origin master
	git add "*"
	git commit -m "Updated game data files from script"
	git push origin master
	cd "${OD}"
}

# Do the execution

if [ $EXTRACTFILES == 1 ]
then
	extractfiles
fi

if [ $GETMAPS == 1 ]
then
	getmaps
fi

if [ $REMOVEBLACKLISTMAPS == 1 ]
then
	removeblacklistmaps
fi

if [ $DECOMPILEMAPS == 1 ]
then
	decompilemaps
fi

if [ $SYNC_MAPS_TO_DATA == 1 ]
then
	sync_maps_to_data
fi

if [ $COPY_MAP_FILES_TO_DATA == 1 ]
then
	copy_map_files_to_data
fi

if [ $CONVERT_VTF == 1 ]
then
	convert_vtf
fi

if [ $MAPDATA == 1 ]
then
	"${SCRIPTDIR}/mapdata.php"
fi

if [ $FULL_MD5_MANIFEST == 1 ]; then
	generate_manifest
fi
if [ $CLEAN_MANIFEST == 1 ]; then
	clean_manifest
fi
if [ $SORT_MANIFEST == 1 ]; then
	ex -s +'%!sort' -cxa "${MANIFEST_FILE}"
fi

if [ $GITUPDATE == 1 ]
then
	gitupdate
fi
