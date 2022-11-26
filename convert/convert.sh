#!/bin/bash
set -u

check_system_prereqs()
{
	if ! command -v jupyter >/dev/null; then
		>&2 echo "Error: jupyter command not found"
		exit 1
	fi
}

cleanup()
{
	if [ -n "${G_TEMP_DIR-}" ]; then
		rm -r "$G_TEMP_DIR"
		unset G_TEMP_DIR
	fi
}

preflight()
{
	trap cleanup EXIT

	G_SELF="$(readlink -f "$0")"
	G_SELFDIR="$(dirname "$0")"
	G_INFILE="${G_SELFDIR}/../ES2000_MathRock_Diffusion.ipynb"
	G_TEMP_DIR="$(mktemp -d)"
	G_PYTHON_FILE_A="${G_TEMP_DIR}/ES2000_MathRock_Diffusion.a.py"
	G_PYTHON_FILE_B="${G_TEMP_DIR}/ES2000_MathRock_Diffusion.b.py"
	G_OUTFILE="${G_SELFDIR}/../ES2000_MathRock_Diffusion.py"

	check_system_prereqs
}

notebook_to_python()
{
	local INFILE="$1"
	local OUTFILE="$2"

	jupyter nbconvert --to python --output "$OUTFILE" "$INFILE" --log-level=ERROR

	if [ "$?" != "0" ]; then
		>&2 echo "Error: Failed to convert notebook to python"
		exit 1
	fi
}

do_utils_inject()
{
	local OUTFILE="$1"

	cat "$G_SELFDIR/convert-utils.py" >> "$OUTFILE" || exit
}

convert_and_output_ipython_cell_magic()
{
	local INPUT="$1"
	local OUTFILE="$2"

	> "$OUTFILE" || exit

	INPUT="$(echo "$INPUT" | sed "s/^get_ipython().run_cell_magic('capture', '', '//g")"
	INPUT="$(echo "$INPUT" | sed "s/')$//")"

	local INS='\\n'
	local NEWL=$'\n'
	local SQ="'"
	INPUT="$(echo "$INPUT" | sed "s/${INS}/\\${NEWL}/g")"
	INPUT="$(echo "$INPUT" | sed "s/\\\'/'/g")"

	local IFS=$'\n'
	local IPYLINES=( $INPUT )
	for I in ${!IPYLINES[@]}; do
		local PLINE="${IPYLINES[$I]}"
		if [ "${PLINE:0:1}" == "!" ]; then
			PLINE="os.system(\"${PLINE:1}\")"
		fi
		if [ "$PLINE" == "')" ]; then
			continue
		fi
		echo "$PLINE" >> "$OUTFILE" || exit
	done
}

emit_cu_get_config_value_line()
{
	local INDENT="$1"
	local ASSIGN_TO="$2"
	local KEY_NAME="$3"
	local PYTYPE="$4"
	local DEFAULT_VALUE="$5"
	local OUTFILE="$6"

	local SOUT="${INDENT}${ASSIGN_TO} = cu_get_config_value('${KEY_NAME}', ${PYTYPE}, ${DEFAULT_VALUE})"
	echo "$SOUT" >> "$OUTFILE" || exit
}

handle_param_line()
{
	local LINE="$1"
	local OUTFILE="$2"
	local INDENT=""

	local VARIABLE_NAME="$(echo "$LINE" | awk '{print $1}')"

	local ASSIGNEE_NAME="$VARIABLE_NAME"
	local KEY_NAME="$VARIABLE_NAME"
	local DEFAULT_NAME="$VARIABLE_NAME"

	if echo "$LINE" | grep '#.*param.*type.*:.*boolean' >/dev/null; then
		TYPE="boolean"
	elif echo "$LINE" | grep '#.*param.*type.*:.*number' >/dev/null; then
		TYPE="number"
	elif echo "$LINE" | grep '#.*param.*type.*:.*string' >/dev/null; then
		TYPE="string"
	elif echo "$LINE" | grep '#.*param.*type.*:.*raw' >/dev/null; then
		TYPE="raw"
	elif echo "$LINE" | grep '#.*param.*type' >/dev/null; then
		TYPE="string"
	elif echo "$LINE" | grep '#.*param' >/dev/null && ! echo "$LINE" | grep '#.*type' >/dev/null; then
		# param with no specified type, defaults to string
		TYPE="string"
	else
		>&2 echo "Error: Failed to get type from param line: $LINE"
		exit
	fi

	case "$TYPE" in
		boolean)
			local PYTYPE="bool"
			;;
		number)
			local PYTYPE="float"
			;;
		string)
			local PYTYPE="str"
			;;
		raw)
			local PYTYPE="None"
			;;
		*)
			>&2 echo "Error: Invalid TYPE: $TYPE"
			exit 1
			;;
	esac

	# type overrides
	case $VARIABLE_NAME in
		n_batches)
			local PYTYPE="int"
			;;
		*)
			;;
	esac

	local I=0
	while [ "${LINE:$I:1}" == " " ]; do
		INDENT+=" "
		((I++))
	done

	echo "$LINE" >> "$OUTFILE" || exit
	emit_cu_get_config_value_line "$INDENT" "$ASSIGNEE_NAME" "$KEY_NAME" "$PYTYPE" "$DEFAULT_NAME" "$OUTFILE"

	if [ "$VARIABLE_NAME" == "width_height" ]; then
		emit_cu_get_config_value_line "$INDENT" "width_height[0]" "width" "int" "width_height[0]" "$OUTFILE"
		emit_cu_get_config_value_line "$INDENT" "width_height[1]" "height" "int" "width_height[1]" "$OUTFILE"
	elif [ "$VARIABLE_NAME" == "n_batches" ]; then
		# process_prompt_list depends on n_batches so we must call it here
		echo "text_prompt_list = process_prompt_list(text_prompt_list)" >> "$OUTFILE" || exit
	fi

	# special handling for seed
	if [ "$VARIABLE_NAME" == "set_seed" ]; then
		emit_cu_get_config_value_line "$INDENT" "seed_temp" "seed" "int" "None" "$OUTFILE"
		echo "${INDENT}if seed_temp is not None:" >> "$OUTFILE" || exit
		echo "${INDENT}    if seed_temp == -1:" >> "$OUTFILE" || exit
		echo "${INDENT}        set_seed = 'random_seed'" >> "$OUTFILE" || exit
		echo "${INDENT}    else:" >> "$OUTFILE" || exit
		echo "${INDENT}        set_seed = str(seed_temp)" >> "$OUTFILE" || exit
	fi
}

process_python_file_pass1()
{
	local INFILE="$1"
	local OUTFILE="$2"

	local OLDIFS="$IFS"
	IFS=$'\n'

	local LINES=( $(< "$INFILE") )
	IFS="$OLDIFS"

	for LNO in ${!LINES[@]}; do
		local LINE="${LINES[$LNO]}"
		local LINEOUT=

		if echo "$LINE" | grep "^get_ipython().run_cell_magic('capture', '', '" >/dev/null; then
			convert_and_output_ipython_cell_magic "$LINE" "$OUTFILE"
			continue
		else
			LINEOUT="$LINE"
		fi

		if [ -n "$LINEOUT" ]; then
			echo "$LINEOUT" >> "$OUTFILE" || exit
		fi
	done
}

# add bew cu_get_config_value() calls for variables/parameters which are
# not currently settable parameters
process_python_file_pass_add_new_config_gets()
{
	local INFILE="$1"
	local OUTFILE="$2"

	> "$OUTFILE" || exit

	local VARS=(
			"randomize_class" "bool"
			"fuzzy_prompt" "bool"
			"rand_mag" "float"
	)

	local OLDIFS="$IFS"
	IFS=$'\n'

	local LINES=( $(< "$INFILE") )
	IFS="$OLDIFS"

	for LNO in ${!LINES[@]}; do
		local LINE="${LINES[$LNO]}"
		local LINE_ELEMS=( $LINE )
		local LINEOUT="$LINE"

		if [ "${#LINE_ELEMS[@]}" == "3" ] && [ "${LINE_ELEMS[1]}" == "=" ]; then
			VNO=0
			while [ "$VNO" -lt "${#VARS[@]}" ]; do
				if [ "${LINE_ELEMS[0]} = " == "${VARS[$VNO]} = " ]; then
					echo "$LINE" >> "$OUTFILE"
					emit_cu_get_config_value_line "" "${VARS[$VNO]}" "${VARS[$VNO]}" "${VARS[$(($VNO + 1))]}" "${VARS[$VNO]}" "$OUTFILE"
					LINEOUT=
				fi
				((VNO+=2))
			done
		fi

		if [ -n "$LINEOUT" ]; then
			echo "$LINEOUT" >> "$OUTFILE"
		fi
	done
}

duplicate_indent()
{
	local S="$1"
	local I=0
	local SOUT=""

	while [ "${S:$I:1}" == " " ]; do
		SOUT+=" "
		((I++))
	done

	printf "%s" "$SOUT"
}

process_python_file_pass2()
{
	local INFILE="$1"
	local OUTFILE="$2"

	> "$OUTFILE" || exit

	local OLDIFS="$IFS"
	IFS=$'\n'

	local LINES=( $(< "$INFILE") )
	IFS="$OLDIFS"

	for LNO in ${!LINES[@]}; do
		local LINE="${LINES[$LNO]}"
		local LINEOUT=

		if [ "$LNO" == "2" ]; then
			do_utils_inject "$OUTFILE"
			echo "cu_callback_startup()" >> "$OUTFILE" || exit
		fi

		if echo "$LINE" | fgrep '#param' >/dev/null | echo "$LINE" | fgrep '#@param' >/dev/null; then
			handle_param_line "$LINE" "$OUTFILE"
			continue
		elif [ "$LINE" == "image_prompts = {" ]; then
			echo "text_prompt_list = cu_get_text_prompt_list(text_prompt_list)" >> "$OUTFILE" || exit
			LINEOUT="$LINE"
		elif [ "$LINE" == "from google.colab.patches import cv2_imshow" ]; then
			echo "if is_colab:" >> "$OUTFILE"
			LINEOUT="    ${LINE}"
		elif echo "$LINE" | grep "image.save('progress.png')$" >/dev/null; then
			local INDENT="$(duplicate_indent "$LINE")"
			echo "${INDENT}cu_callback_display_rate()" >> "$OUTFILE" || exit
			LINEOUT="$LINE"
		else
			LINEOUT="$LINE"
		fi

		LINEOUT="$(echo "$LINEOUT" | sed 's/display\.display/#display.display/')"

		if [ -n "$LINEOUT" ]; then
			echo "$LINEOUT" >> "$OUTFILE" || exit
		fi
	done
}

main()
{
	preflight "$@"

	echo "Converting notebook to python ..."
	notebook_to_python "$G_INFILE" "$G_PYTHON_FILE_A"
	echo "Processing python script (pass 1) ..."
	process_python_file_pass1 "$G_PYTHON_FILE_A" "$G_PYTHON_FILE_B"
	echo "Processing python script (pass 2) ..."
	process_python_file_pass2 "$G_PYTHON_FILE_B" "$G_PYTHON_FILE_A"
	echo "Processing python script (pass 3) ..."
	process_python_file_pass_add_new_config_gets "$G_PYTHON_FILE_A" "$G_PYTHON_FILE_B"

	echo "Writing output file: $(readlink -f "$G_OUTFILE")"
	cp "$G_PYTHON_FILE_B" "$G_OUTFILE" || exit

	echo "Done!"

	cleanup
}

main "$@"
