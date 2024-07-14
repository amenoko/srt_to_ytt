#!/bin/bash

# default IFS is $' \t\n' and it interferes with multi-line array values
IFS=$' \t\n'
IFS_DEFAULT=$' \t\n'

sourcefile="$1"
if [ -z "$sourcefile" ]; then
    echo "No file provided, exiting."
    exit
fi

# function for converting srt timestamp to milliseconds
get_milliseconds () {
    hours=$(echo $1 | sed 's|:.*||')
    minutes=$(echo $1 | sed 's|^...||' | sed 's|:.*||')
    seconds=$(echo $1 | sed 's|^......||' | sed 's|,.*||')
    milliseconds=$(echo $1 | sed 's|.*,||')
    # numbers with leading zeroes can be interpreted as octal if not otherwise specified
    echo $((10#$hours*60*60*1000 + 10#$minutes*60*1000 + 10#$seconds*1000 + 10#$milliseconds ))
}

# create arrays of timestamps
# this will break if a subtitle contains ">"
mapfile -t timestamps_begin < <(grep ">" "$sourcefile" | awk '{print $1}')
mapfile -t timestamps_end < <(grep ">" "$sourcefile" | awk '{print $3}')
# note that the array index starts at 0, but array size (${#array[@]}) starts
# at 1 so ${array[${#array[@]}]} will not exist

# convert timestamps to milliseconds
# ${#timestamps_begin[@]} is length but starts at 1, whereas index starts at 0,
# so subtract 1 from it
for i in $(seq 0 $((${#timestamps_begin[@]} - 1))); do
    timestamps_begin[$i]=$(get_milliseconds "${timestamps_begin[$i]}")
    timestamps_end[$i]=$(get_milliseconds "${timestamps_end[$i]}")
done

# create array ${captions[@]} containing captions
mapfile -t source < "$sourcefile"
for i in $(seq 0 ${#source[@]}); do
    if [ $i != 0 ]; then
        # this will break if a subtitle contains ">"
        # exclude number lines and timecode lines: can't match number lines so match
        # timecodes and store value from previous line, check if current or previous value
        # is timecode
        if ! [[ ${source[$i]} =~ .*\>.* ]] && \
           ! [[ $previous =~ .*\>.* ]] && \
           # exclude lines that do not contain at least one letter, number, exclamation or
           # question mark
           [[ $previous =~ .*[a-z].*|.*[0-9].*|.*\..*|.*\!.*|.*\?.* ]]; then
               if [ -n "${captions[$captions_index]}" ]; then
                   IFS='' captions[$captions_index]=$(printf "${captions[$captions_index]}\n$previous")
                   IFS=$IFS_DEFAULT
               else
                   IFS='' captions[$captions_index]=$(printf "$previous")
                   IFS=$IFS_DEFAULT
               fi
        fi

        if [[ ${source[$i]} =~ .*\>.* ]] && [ $i -gt 1 ]; then
            captions_index=$((captions_index+1))
        fi
    fi
    previous=${source[$i]}
done

# output a basic ytt script with no special formatting: horizontally centered, anchored to
# bottom center, Y coordinate set to bottom of video
# wp id=0 is used by default, wp id=1 is top-aligned text
echo \
'<?xml version="1.0" encoding="utf-8"?><timedtext format="3">
  <head>
    <wp id="0" ap="7" ah="50" av="100" />
    <wp id="1" ap="1" ah="50" av="0" />
  </head>
  <body>'
for i in $(seq 0 $((${#timestamps_begin[@]} - 1))); do
    echo -n '    <p t="'${timestamps_begin[$i]}'" '
    echo -n 'd="'$(( ${timestamps_end[$i]} - ${timestamps_begin[$i]} ))'" wp="0">'
    echo "${captions[$i]}</p>"
done
echo '  </body>
</timedtext></xml>'
