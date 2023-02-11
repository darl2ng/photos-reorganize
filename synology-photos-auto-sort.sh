#!/bin/bash

### INFO #################################################
# Synology photos and videos auto sort
# By Gulivert
# https://github.com/Gulivertx/synology-photos-auto-sort
##########################################################

VERSION="1.2"
PID_FILE="/tmp/synology_photos_auto_sort.pid"
LOG_DIRECTORY="logs"

# Define a folder where the images will be moved for process error
ERROR_DIRECTORY="error"

# Define a folder where the images will be moved for duplicate images
DUPLICATE_DIRECTORY="duplicate"

# Define exif command
CMD_EXIF="exif"

### Allowed image and videos extensions
ALLOWED_EXT="jpg JPG jpeg JPEG png PNG heic HEIC mov MOV heiv HEIV m4v M4V mp4 MP4"

### HELP #################################################
# Help
##########################################################
Help()
{
   # Display Help
    echo "Synology photos and videos auto sort version $VERSION"
    echo "https://github.com/Gulivertx/synology-photos-auto-sort"
    echo ""
    echo "Arguments"
    echo "source folder"
    echo "target folder"
    echo "Ex.: synology-photos-auto-sort.sh /path_to_source /path_to_target"
    echo ""
    echo "Options:"
    echo "-h     Print this Help."
    echo ""
}

### OPTIONS ##############################################
# Process the input options. Add options as needed
##########################################################
# Get the options
while getopts ":h:r:" option; do
   case ${option} in
      h) # display Help
         Help
         exit
         ;;
   esac
done

### Verify if a script already running
if [[ -f ${PID_FILE} ]]; then
    echo "Error: an other process of the script is still running" >&2
    exit 0
fi

### Create a pid file
echo $$ > ${PID_FILE}

### Verify if exif installed
if ! [[ -x "$(command -v ${CMD_EXIF})" ]]; then
    echo "Error: ${CMD_EXIF} is not installed" >&2
    rm -f ${PID_FILE}
    exit 1
fi

### Get script arguments source and target folders
SOURCE=$1
TARGET=$2

if [[ -z ${SOURCE} ]] || [[ -z ${TARGET} ]]; then
    rm -f ${PID_FILE}
    Help
    exit 1
fi

echo "Source folder : $SOURCE"
echo "Target folder : $TARGET"
echo ""

echo "Allowed formats: ${ALLOWED_EXT}"
echo ""

### Move to source folder
cd ${SOURCE}

echo "Start process"

# Count files
FILES_COUNTER=$(ls *.* 2> /dev/null | wc -l | xargs)
TOTAL_FILES_COUNTER=${FILES_COUNTER}

# Get all files in an array
FILES_ARR=(*.*)

echo "$FILES_COUNTER files to process"
echo ""

# Move all allowed files to target folder
MoveFiles()
{
if [[ ${FILES_COUNTER} != 0 ]]; then
    PROGRESS=0
    echo -ne "${PROGRESS}%\033[0K\r"

    for FILE in ${FILES_ARR[@]}; do
        FILENAME="${FILE%.*}" # Get filename
        EXT="${FILE##*.}" # Get file extension

        # Verify if the extension is allowed
        if [[ ${ALLOWED_EXT} == *"$EXT"* ]]; then

            DATETIME=$(${CMD_EXIF} --tag="Date and Time" --machine-readable ${FILE} 2>/dev/null)
            # Verify if we have exif datetime data available
            if [[ -z ${DATETIME} ]]; then
                let PROGRESS++
                echo -ne "$((${PROGRESS} * 100 / ${FILES_COUNTER}))%\033[0K\r"
                continue
            fi
            
            MANUFACTURER=$(${CMD_EXIF} --tag=Manufacturer --machine-readable ${FILE} 2>/dev/null)
            if [[ -z ${MANUFACTURER} ]]; then
                MANUFACTURER="Unknown"
            else
                MANUFACTURER="${MANUFACTURER// /_}"
            fi  

            MODEL=$(${CMD_EXIF} --tag=Model --machine-readable ${FILE} 2>/dev/null)
            if [[ -z ${MODEL} ]]; then
                MODEL="Unknown"
            else
                MODEL="${MODEL// /_}"
            fi

            # Extract date, time year and month and build new filename
            DATE=${DATETIME:0:10}
            TIME=${DATETIME:11:8}
            YEAR=${DATE:0:4}
            MONTH=${DATE:5:2}
            NEW_FILENAME=${DATE//:}_${TIME//:}.${EXT,,}

            # Get target file path
            TARGET_FOLDER=${TARGET}/${MANUFACTURER}/${MODEL}/${YEAR}/${MONTH}
            TARGET_FILEPATH=${TARGET_FOLDER}/${NEW_FILENAME}

            # Create target folder
            mkdir -p "${TARGET_FOLDER}"

            # Move the file to target folder if not exist in target folder
            if [[ ! -f ${TARGET_FOLDER}/${NEW_FILENAME} ]]; then
                mv -n "${FILE}" "${TARGET_FOLDER}/${NEW_FILENAME}"

                # Remove the moved file from the array
                let FILES_COUNTER--
                FILES_ARR=("${FILES_ARR[@]/$FILE}")
            fi
        fi

        let PROGRESS++
        echo -ne "$((${PROGRESS} * 100 / ${TOTAL_FILES_COUNTER}))%\033[0K\r"
    done

    # Wait until the process is done
    wait

    echo "Parsable files have been moved"
    echo ""
fi
}

### Move all files still not moved by the above rule in an error folder
MoveUnmovedFiles()
{
TOTAL_FILES_COUNTER=${FILES_COUNTER}

if [[ ${FILES_COUNTER} != 0 ]]; then
    echo "$FILES_COUNTER unmoved files, check for duplicate and process again..."
    echo ""

    PROGRESS=0
    echo -ne "${PROGRESS}%\033[0K\r"

    mkdir -p ${ERROR_DIRECTORY}
    mkdir -p ${DUPLICATE_DIRECTORY}
    mkdir -p ${LOG_DIRECTORY}

    # Create a new log file
    CURRENT_DATE=`date +"%Y-%m-%d_%H-%M"`
    LOG_FILE="${LOG_DIRECTORY}/${CURRENT_DATE}.log"
    touch ${LOG_FILE}

    for FILE in ${FILES_ARR[@]}; do
        FILENAME="${FILE%.*}" # Get filename
        EXT="${FILE##*.}" # Get file extension

        # Verify if the extension is allowed
        if [[ ${ALLOWED_EXT} == *"$EXT"* ]]; then
                        
            DATETIME=$(${CMD_EXIF} --tag="Date and Time" --machine-readable ${FILE} 2>/dev/null)            

            # Verify if we have exif datetime data available
            if [[ -z ${DATETIME} ]]; then
                
                NEW_FILENAME=${FILENAME=//:}.${EXT,,}
                echo "No exif data available for image ${FILE}, moved into ${ERROR_DIRECTORY}" >> ${LOG_FILE}
                mv "${FILE}" "${ERROR_DIRECTORY}/${NEW_FILENAME}"

                let PROGRESS++
                echo -ne "$((${PROGRESS} * 100 / ${TOTAL_FILES_COUNTER}))%\033[0K\r"

                # Remove the moved file from the array
                let FILES_COUNTER--
                FILES_ARR=("${FILES_ARR[@]/$FILE}")

                continue
            else
 
                MANUFACTURER=$(${CMD_EXIF} --tag=Manufacturer --machine-readable ${FILE} 2>/dev/null)
                if [[ -z ${MANUFACTURER} ]]; then
                    MANUFACTURER="Unknown"
                else
                    MANUFACTURER="${MANUFACTURER// /_}"
                fi  

                MODEL=$(${CMD_EXIF} --tag=Model --machine-readable ${FILE} 2>/dev/null)
                if [[ -z ${MODEL} ]]; then
                    MODEL="Unknown"
                else
                    MODEL="${MODEL// /_}"
                fi

                DATE=${DATETIME:0:10}
                TIME=${DATETIME:11:8}
                YEAR=${DATE:0:4}
                MONTH=${DATE:5:2}
                NEW_FILENAME=${DATE//:}_${TIME//:}.${EXT,,}

                # Get target file path
                TARGET_FOLDER=${TARGET}/${MANUFACTURER}/${MODEL}/${YEAR}/${MONTH}
                TARGET_FILEPATH=${TARGET_FOLDER}/${NEW_FILENAME}

                # Test if existing file is the same
                # Get base64 encoded image
                SOURCE_FILE_BASE64="$(cat ${FILE} | base64)"
                TARGET_FILE_BASE64="$(cat ${TARGET_FILEPATH} | base64)"

                #See if files are the same
                if [[ ${SOURCE_FILE_BASE64} == ${TARGET_FILE_BASE64} ]]; then
                    NEW_FILENAME=${FILENAME=//:}.${EXT,,}
                    echo "The file ${FILE} already exist and is the same! File ${FILE} moved into ${DUPLICATE_DIRECTORY} and renamed as ${NEW_FILENAME}" >> ${LOG_FILE}
                    mv "${FILE}" "${DUPLICATE_DIRECTORY}/${NEW_FILENAME}"

                    let PROGRESS++
                    echo -ne "$((${PROGRESS} * 100 / ${TOTAL_FILES_COUNTER}))%\033[0K\r"

                    # Remove the moved file from the array
                    let FILES_COUNTER--
                    FILES_ARR=("${FILES_ARR[@]/$FILE}")

                    continue
                else
                    # Generate a unique ID
                    #UUID=$(cat /proc/sys/kernel/random/uuid)
                    UUID="U$(date +%s%N)"

                    NEW_FILENAME=${FILENAME=//:}_${UUID}.${EXT,,}

                    mv -n "${FILE}" "${TARGET_FOLDER}/${NEW_NAME}"

                    let PROGRESS++
                    echo -ne "$((${PROGRESS} * 100 / ${TOTAL_FILES_COUNTER}))%\033[0K\r"

                    # Remove the moved file from the array
                    let FILES_COUNTER--
                    FILES_ARR=("${FILES_ARR[@]/$FILE}")
                fi
            fi
        fi
    done

    # Wait until the process is done
    wait
fi
}

MoveFiles
MoveUnmovedFiles

# Clean @eaDir
if [[ -d "${SOURCE/}@eaDir" ]]; then
    rm -Rf "${SOURCE/}@eaDir"
fi

rm -f ${PID_FILE}

exit 0
