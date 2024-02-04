#!/usr/bin/env bash

is_tmp="yes"	  # default to no tmp directory
resource_dir="/"  #default to root of pandoc container buildout
do_gitversion="yes"
do_gitstatus="yes"
pdf_output=""
docx_output=""
html_output=""
latex_output=""
pdflog_output=""
table_rules="no"
block_quotes_are_informative_text="no"

# Setup an EXIT handler
on_exit() {
	if [[ "${is_tmp}" == "yes" && -e "${build_dir}" ]]; then
		rm -rf "${build_dir}"
	fi
}

trap on_exit EXIT

print_usage() {
	echo "Usage:"
	echo "$(basename "${0}") [options] [input-file]"
	echo
	echo "Arguments:"
	echo "  This script takes a single markdown file input for rendering to docx/pdf/LaTeX."
	echo
	echo "Options:"
	echo
	echo "Output Control"
	echo "  --docx=output: enable output of docx and specify the output file name."
	echo "  --pdf=output: enable output of pdf and specify the output file name."
	echo "  --latex=output: enable output of latex and specify the output file name."
	echo "  --html=output: enable output of html and specify the output file name."
	echo "  --pdflog=output: enable logging of pdf engine and specify the output file name."
	echo
	echo "Miscellaneous"
	echo "  --resourcedir=dir: Set the resource directory, defaults to root for pandoc containers"
	echo "  --notmp: Do not use a tempory directory for processing steps, instead create a directory called \"build\" in CWD"
	echo "  --gitversion: legacy flag, no effect (default starting with 0.9.0)"
    echo "  --gitstatus: legacy flag, no effect (default starting with 0.9.0)"
	echo "  --nogitversion: Do not use git to describe the generate document version and revision metadata."
	echo "  --table_rules: legacy flag, no effect (default starting with 0.9.0)"
	echo "  --plain_quotes: legacy flag, no effect (default starting with 0.9.0)"
	echo "  --noplain_quotes: use block-quote syntax as informative text"
}


if ! options=$(getopt --longoptions=help,puppeteer,notmp,gitversion,gitstatus,nogitversion,table_rules,plain_quotes,noplain_quotes,pdf:,latex:,pdflog:,docx:,html:,resourcedir: --options="" -- "$@"); then
	echo "Incorrect options provided"
	print_usage
	exit 1
fi

eval set -- "${options}"
while true; do
	case "$1" in
	--nogitversion)
		do_gitstatus="no"
		do_gitversion="no"
		shift
		;;
	--puppeteer)
		# legacy option; just ignore this
		shift
		;;
	--gitversion)
		# legacy option; just ignore this
		shift
		;;
	--gitstatus)
		# legacy option; just ignore this
		shift
		;;
	--plain_quotes)
		# legacy option; just ignore this
		shift
		;;
	--noplain_quotes)
		block_quotes_are_informative_text="yes"
		shift
		;;
	--notmp)
		is_tmp="no"
		shift
		;;
	--docx)
		docx_output="${2}"
		shift 2
		;;
	--latex)
		latex_output="${2}"
		shift 2
		;;
	--pdflog)
		pdflog_output="${2}"
		shift 2
		;;
	--pdf)
		pdf_output="${2}"
		shift 2
		;;
	--html)
		html_output="${2}"
		shift 2
		;;
	--resourcedir)
		resource_dir="${2}"
		shift 2
		;;
	--table_rules)
		table_rules="yes"
		shift
		;;
	--help)
		print_usage
		shift
		exit 0
		;;
	--)
		shift
		break
		;;
	esac
done

shift "$(( OPTIND - 1 ))"

# argcount check
if [ $# -ne 1 ]; then
	>&2 echo "Expected 1 markdown input file for processing, got: $*"
	print_usage
	exit 1
fi

# input file check
input_file=$1
if [ ! -e "${input_file}" ]; then
   >&2 echo "${input_file} does not exist, exiting..."
   exit 1
fi

if [ -z "${pdf_output}${latex_output}${docx_output}${html_output}" ]; then
	>&2 echo "Expected --pdf, --docx, --html, or --latex option"
	print_usage
	exit 1
fi

# Set up the output directory, either tmp or build in pwd.
if [ "${is_tmp}" == "yes" ]; then
	build_dir="/tmp/tcg.pandoc"
else
	build_dir="$(pwd)/build"
fi
mkdir -p "${build_dir}"

# Get the default browser
if ! browser=$(command -v "chromium-browser"); then
	if ! browser=$(command -v "chromium"); then
		if ! browser=$(command -v "google-chrome"); then
			browser="none"
		fi
	fi
fi

# figure out git version and revision if needed.
extra_pandoc_options=""
if test "${do_gitversion}" == "yes"; then
	git config --global --add safe.directory /workspace

	# TODO: Should we fail if dirty?
	raw_version="$(git describe --always --tags)"
	echo "Git version: ${raw_version}"
	IFS='-' read -r -a dash_hunks <<< "${raw_version}"

    # Could be one of:
    # gabcd - commit no tag (len 1)
   	# 4 --> tag major only (len 1)
	# 4.0 --> tag major minor (len 1)
	# 4-54-gabcd --> tag major with commits (len 3)
	# 4.0-54-gabcd --> tag major-minor with commits (len 3)
	len=${#dash_hunks[@]}
	if ! test "${len}" -eq 1 -o "${len}" -eq 3; then
	    >&2 echo "Malformed git version got: ${raw_version}"
	    exit 1
    fi

	revision="0"
	major_minor="${dash_hunks[0]}"
	if test "${len}" -eq 3; then
		revision="${dash_hunks[1]}"
	fi

	# Does this even have a major minor, or is it just a commit (8d7046adcf1b) len of 12 no dot char?
	# Note that in docker image this sha is shorter at 7 chars for some reason.
	if grep -qv '\.' <<< "${major_minor}"; then
		if test ${#major_minor} -ge 7; then

			# its a commit
			major_minor="0.0"
			revision="$(git rev-list --count HEAD)"
		else
			# its a major with no minor, append .0
			major_minor="${major_minor}.0"
		fi
	fi

	# Before scrubbing, grab the first character from 'major_minor'
	first_char=${major_minor:0:1}

	# scrub any leading non-numerical arguments from major_minor, ie v4.0, scrub any other nonsense as well
	major_minor="$(tr -d "[:alpha:]" <<< "${major_minor}")"

	extra_pandoc_options+=" --metadata=version:${major_minor}"

	# Revision 0 = no revision
	if [ "${revision}" -ne "0" ]; then
		extra_pandoc_options+=" --metadata=revision:${revision}"
	fi

	# Do we set document status based on git version?
	if [ "${do_gitstatus}" == "yes" ]; then
		# If revision is 0 and the first character of the tag is 'p' (for Published)
		if [ "${revision}" == "0" ] && [ "${first_char}" == "p" ]; then
			status="Published"
		# If revision is 0 and the first character of the tag is 'r' (for Review)
		elif [ "${revision}" == "0" ] && [ "${first_char}" == "r" ]; then
			status="Review"
		# Revision is not 0, or the tag doesn't begin with a p or an r.
		else
			status="Draft"
		fi
		extra_pandoc_options+=" --metadata=status:${status}"
	fi

fi # Done with git version handling

echo "Starting Build with"
echo "file: ${input_file}"
echo "docx: ${docx_output:-none}"
echo "pdf: ${pdf_output:-none}"
echo "latex: ${latex_ouput:-none}"
echo "html: ${html_ouput:-none}"
echo "use tmp: ${is_tmp}"
echo "resource dir: ${resource_dir}"
echo "build dir: ${build_dir}"
echo "browser: ${browser}"
echo "use git version: ${do_gitversion}"
echo "use table rules: ${table_rules}"
echo "make block quotes Informative Text: ${block_quotes_are_informative_text}"
if test "${do_gitversion}" == "yes"; then
	echo "Git Generated Document Version Information"
	echo "    version: ${major_minor}"
	echo "    revision: ${revision}"
	if [ "${do_gitstatus}" == "yes" ]; then
		echo "    status: ${status}"
	fi
fi

if [ "${browser}" == "none" ]; then
	>&2 echo "No Browser found, looked for chromium-browser and google-chrome"
	exit 1
fi

# There are some configuration dependencies required for Mermaid.
# They have to be in the current directory.
cat <<- EOF > ./.puppeteer.json
{
	"executablePath": "$browser",
	"args": [
		"--no-sandbox",
		"--disable-setuid-sandbox"
	]
}
EOF

if [ "${block_quotes_are_informative_text}" == "yes" ]; then
	extra_pandoc_options+=" --lua-filter=informative-quote-blocks.lua"
fi

mkdir -p "${build_dir}/$(dirname ${input_file})"
cp "${input_file}" "${build_dir}/${input_file}"

# Hacks

# \newpage is rendered as the string "\newpage" in GitHub markdown.
# Transform horizontal rules into \newpages.
# Exception: the YAML front matter of the document, so undo the instance on the first line.
sed -i.bak 's/^---$/\\newpage/g;1s/\\newpage/---/g' "${build_dir}/${input_file}"

# Transform sections before the table of contents into section*, which does not number them.
# While we're doing this, transform the case to all-caps.
sed -i.bak '0,/\\tableofcontents/s/^# \(.*\)/\\section*\{\U\1\}/g' "${build_dir}/${input_file}"

if test "${do_gitversion}" == "yes"; then
	# If using the git information for versioning, grab the date from there
	DATE="$(git show -s --date=format:'%Y/%m/%d' --format=%ad)"
else
	# Else, grab the date from the front matter and generate the full date and year.
	DATE="$(grep date: "${input_file}" | head -n 1 | cut -d ' ' -f 2)"
fi

YEAR="$(date --date="${DATE}" +%Y)"
DATE_ENGLISH="$(date --date="${DATE}" "+%B %-d, %Y")"

echo "Date: ${DATE}"
echo "Year: ${YEAR}"
echo "Date (English): ${DATE_ENGLISH}"

# We use the following Markdown and pandoc plugins:
# * Regular (Pandoc) markdown flavor
# * With GitHub-flavored markdown auto identifiers
# * Support fenced_divs (for informative block div syntax)
# * Implicit_figures for figure numbering/table-of-figures support for images and diagrams
# * Multiline_tables and grid_tables to support nontrivial table content
# * Table_captions so that tables can be captioned
# * DISABLING 'markdown_in_html_blocks' which breaks the ability to embed tables in HTML form.
FROM="markdown+gfm_auto_identifiers+fenced_divs+implicit_figures+multiline_tables+grid_tables+table_captions-markdown_in_html_blocks"

export MERMAID_FILTER_THEME="forest"
export MERMAID_FILTER_FORMAT="pdf"
export MERMAID_FILTER_BACKGROUND="transparent"

# The Mermaid filter loses track of the web browser it uses to render diagrams
# sometimes (maybe 5% of the time or so).
# As a hack, we run our Pandoc commands in a loop, retrying if there is any failure.
# First argument: number of times to try
# Rest of the arguments: command to run
# A better way to solve this would be to run just the Mermaid step in a
# Markdown-to-Markdown pandoc flow. Unfortunately, this is lossy, specifically
# with respect to rowspan/colspan tables: https://github.com/jgm/pandoc/issues/6344
# When the Markdown Pandoc writer can preserve rowspan and colspan tables, we
# should consider running Markdown in its own flow first.
retry () {
	local TIMES=$1
	shift
	local COMMAND="$@"
	n=1
	until [ "${n}" -gt "${TIMES}" ]; do
		eval "${COMMAND[@]}" && return 0
		if [ "${n}" -lt "${TIMES}" ]; then
			echo "Assuming transient error. Retrying up to ${TIMES} times..."
		fi
		n=$((n+1))
	done
	echo "Command failed after ${TIMES}"
	return 1
}

TEMP_FILE_PREFIX="${input_file}.temp"
TEMP_TEX_FILE="${build_dir}/${TEMP_FILE_PREFIX}.tex"
# LaTeX engines choose this filename based on TEMP_TEX_FILE's input name. It also emits a bunch of other files.
TEMP_PDF_FILE="${build_dir}/${TEMP_FILE_PREFIX}.pdf"

LATEX=xelatex
LATEX_LOG="${build_dir}/latex.log"

# Get the time in Unix epoch milliseconds of the given line
timestamp_of() {
	local LINE="$1"
	local TIMESTAMP=$(echo "${LINE}" | cut -d ' ' -f 1 | tr -d "[]")


	local SECONDS=$(echo "${TIMESTAMP}" | cut -d '.' -f 1)
	local MILLISECONDS=$(echo "${TIMESTAMP}" | cut -d '.' -f 2 | head -c 3)
	# MILLISECONDS might have some leading 0's. Trim them by converting it as a base-10 integer.
	echo $(( $SECONDS * 1000 + 10#$MILLISECONDS ))
}

# Get the duration in human-readable time between two patterns in the logfile
time_between() {
	local LOGFILE="$1"
	local FIRST_PATTERN="$2"
	local SECOND_PATTERN="$3"

	local FIRST_LINE=$(grep "${FIRST_PATTERN}" "${LOGFILE}" | head -n 1)
	local SECOND_LINE=$(grep "${SECOND_PATTERN}" "${LOGFILE}" | head -n 1)

	if [ -z "${FIRST_LINE}" -o -z "${SECOND_LINE}" ]; then
		echo "n/a"
	else
		local FIRST_TIME=$(timestamp_of "${FIRST_LINE}")
		local SECOND_TIME=$(timestamp_of "${SECOND_LINE}")

		ELAPSED_MS=$(( ${SECOND_TIME} - ${FIRST_TIME} ))

		ELAPSED_S=$(( $ELAPSED_MS / 1000 ))
		ELAPSED_MS=$(( $ELAPSED_MS % 1000 ))

		ELAPSED_M=$(( $ELAPSED_S / 60 ))
		ELAPSED_S=$(( $ELAPSED_S % 60 ))

		ELAPSED_MS="${ELAPSED_MS}ms"

		if [ ${ELAPSED_M} -gt 0 ]; then
			ELAPSED_M="${ELAPSED_M}m "
			# Don't print the milliseconds if we got more than a minute.
			ELAPSED_MS=""
		else
			ELAPSED_M=""
		fi

		if [ ${ELAPSED_S} -gt 0 ]; then
			ELAPSED_S="${ELAPSED_S}s "
		else
			ELAPSED_S=""
		fi

		echo "${ELAPSED_M}${ELAPSED_S}${ELAPSED_MS}"
	fi
}

analyze_latex_logs() {
	local LOGFILE=$1

	echo "Time to fancyhdr warning: $(time_between "${LOGFILE}" "TeX Live" "with a KOMA-Script class is not recommended.")"
	echo "Time to done: $(time_between "${LOGFILE}" "with a KOMA-Script class is not recommended." "Output written on ")"

}

# For LaTeX and PDF output, we use Pandoc to compile to an intermediate .tex file
# That way, LaTeX errors on PDF output point to lines that match the .tex.
if [ -n "${pdf_output}" -o -n "${latex_output}" ]; then
	mkdir -p "$(dirname ${pdf_output})"
	echo "Generating LaTeX Output"
	start=$(date +%s)
	CMD=(pandoc
		--standalone
		--template=tcg.tex
		--lua-filter=mermaid-code-class-pre.lua
		--filter=mermaid-filter
		--lua-filter=parse-html.lua
		--lua-filter=apply-classes-to-tables.lua
		--lua-filter=landscape-pages.lua
		--lua-filter=style-fenced-divs.lua
		--filter=pandoc-crossref
		--lua-filter=tabularx.lua
		--lua-filter=divide-code-blocks.lua
		--resource-path=.:/resources
		--data-dir=/resources
		--top-level-division=section
		--variable=block-headings
		--variable=numbersections
		--metadata=date:"'${DATE}'"
		--metadata=date-english:"'${DATE_ENGLISH}'"
		--metadata=year:"'${YEAR}'"
		--metadata=titlepage:true
		--metadata=titlepage-background:/resources/img/cover.png
		--metadata=crossrefYaml:/resources/filters/pandoc-crossref.yaml
		--metadata=logo:/resources/img/tcg.png
		--metadata=titlepage-rule-height:0
		--metadata=colorlinks:true
		--metadata=contact:admin@trustedcomputinggroup.org
		--from=${FROM}
		${extra_pandoc_options}
		--to=latex
		--output="'${TEMP_TEX_FILE}'"
		"'${build_dir}/${input_file}'")
	retry 5 "${CMD[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "LaTeX/PDF output failed"
	fi
	end=$(date +%s)
	echo "Elapsed time: $(($end-$start)) seconds"

	if [ -n "${latex_output}" ]; then
		cp "${TEMP_TEX_FILE}" "${latex_output}"
	fi

	if [ -n "${pdf_output}" ]; then
		echo "Generating cross-references for PDF output"
		start=$(date +%s)
		# Run once to populate aux, lof, lot, toc
		${LATEX} --no-pdf "${TEMP_TEX_FILE}" | ts '[%.s]' > "${LATEX_LOG}"
		if [ "${PIPESTATUS[0]}" -ne 0 ]; then
			FAILED=true
			echo "PDF output failed"
		else
			end=$(date +%s)
			echo "Elapsed time: $(($end-$start)) seconds"
			# Write any LaTeX errors to stderr.
			>&2 grep -A 5 "] ! " "${LATEX_LOG}"

			# Run a second time to render the actual PDF.
			echo "Rendering PDF"
			start=$(date +%s)
			${LATEX} "${TEMP_TEX_FILE}" | ts '[%.s]' > "${LATEX_LOG}"
			if [ "${PIPESTATUS[0]}" -ne 0 ]; then
				FAILED=true
				echo "PDF output failed"
			fi
		fi
		end=$(date +%s)

		# Clean up after LuaLaTeX and copy out just the files we need.
		mv "${TEMP_FILE_PREFIX}"* "${build_dir}"
		if [ -n "${pdflog_output}" ]; then
			cp "${LATEX_LOG}" "${pdflog_output}"
		fi
		echo "Elapsed time: $(($end-$start)) seconds"
		# Write any LaTeX errors to stderr.
		>&2 grep -A 5 "] ! " "${LATEX_LOG}"
		if [[ ! "${FAILED}" = "true" ]]; then
			cp "${TEMP_PDF_FILE}" "${pdf_output}"
			analyze_latex_logs "${LATEX_LOG}"
			echo "LaTeX warnings (may be ignorable - check the output!)"
			# Include any other warnings.
			grep "LaTeX Warning: " "${LATEX_LOG}"
		fi
	fi	
fi

# Generate the docx output
if [ -n "${docx_output}" ]; then
	# Prepare the title-page for the docx version.
	SUBTITLE="Version ${major_minor:-${DATE}}, Revision ${revision:-0}"
	# Prefix the document with a Word page-break, since Pandoc doesn't do docx
	# title pages.
	cat <<- 'EOF' > "${build_dir}/${input_file}.prefixed"
	```{=openxml}
	<w:p>
		<w:r>
			<w:br w:type="page"/>
		</w:r>
	</w:p>
	```
	EOF
	cat ${build_dir}/${input_file} >> ${build_dir}/${input_file}.prefixed

	mkdir -p "$(dirname ${docx_output})"
	echo "Generating DOCX Output"
	CMD=(pandoc
		--embed-resources
		--standalone
		--lua-filter=mermaid-code-class-pre.lua
		--filter=mermaid-filter
		--lua-filter=parse-html.lua
		--lua-filter=apply-classes-to-tables.lua
		--lua-filter=style-fenced-divs.lua
		--lua-filter=make-informative-text.lua
		--filter=pandoc-crossref
		--resource-path=.:/resources
		--data-dir=/resources
		--from='${FROM}+raw_attribute'
		--metadata=subtitle:"'${SUBTITLE}'"
		--reference-doc=/resources/templates/tcg.docx
		${extra_pandoc_options}
		--to=docx
		--output="'${docx_output}'"
		"'${build_dir}/${input_file}.prefixed'")
	retry 5 "${CMD[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "DOCX output failed"
	else
		echo "DOCX output generated to file: ${docx_output}"
	fi
fi

export MERMAID_FILTER_FORMAT="svg"

# Generate the html output
if [ -n "${html_output}" ]; then
	mkdir -p "$(dirname ${html_output})"
	echo "Generating html Output"
	CMD=(pandoc
		--toc
		-V colorlinks=true
		-V linkcolor=blue
		-V urlcolor=blue
		-V toccolor=blue
		--embed-resources
		--standalone
		--lua-filter=mermaid-code-class-pre.lua
		--filter=mermaid-filter
		--lua-filter=parse-html.lua
		--lua-filter=apply-classes-to-tables.lua
		--lua-filter=landscape-pages.lua
		--filter=pandoc-crossref
		--lua-filter=divide-code-blocks.lua
		--lua-filter=style-fenced-divs.lua
		--resource-path=.:/resources
		--data-dir=/resources
		--top-level-division=section
		--variable=block-headings
		--variable=numbersections
		--metadata=titlepage:true
		--metadata=titlepage-background:/resources/img/cover.png
		--metadata=crossrefYaml:/resources/filters/pandoc-crossref.yaml
		--metadata=logo:/resources/img/tcg.png
		--metadata=titlepage-rule-height:0
		--metadata=colorlinks:true
		--metadata=contact:admin@trustedcomputinggroup.org
		--from=${FROM}
		${extra_pandoc_options}
		--to=html
		--output="'${html_output}'"
		"'${build_dir}/${input_file}'")
	retry 5 "${CMD[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "HTML output failed"
	else
		echo "HTML output generated to file: ${html_output}"
	fi
fi

if [ "${FAILED}" = "true" ]; then
	echo "Overall workflow failed"
	exit 1
fi

# on success remove this output
rm -f core
rm -f mermaid-filter.err
rm -f .puppeteer.json
rm  "${build_dir}/${input_file}.bak"

echo "Overall workflow succeeded"
exit 0
