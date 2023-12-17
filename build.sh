#!/usr/bin/env bash

is_tmp="yes"	  # default to no tmp directory
resource_dir="/"  #default to root of pandoc container buildout
do_puppeteer="no"
do_gitversion="no"
do_gitstatus="no"
pdf_output=""
docx_output=""
latex_output=""

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
	echo "  --docx=output: enable outputing of docx and specify the output file name."
	echo "  --pdf=output: enable outputing of pdf and specify the output file name."
	echo "  --latex=output: enable outputing of latex and specify the output file name."
	echo
	echo "Miscellaneous"
	echo "  --puppeteer: enable outputing of .puppeteer.json in current directory. This is needed for running in sandboxes eg docker containers."
	echo "  --resourcedir=dir: Set the resource directory, defaults to root for pandoc containers"
	echo "  --notmp: Do not use a tempory directory for processing steps, instead create a directory called \"build\" in CWD"
	echo "  --gitversion: Use git describe to generate document version and revision metadata."
        echo "  --gitstatus: Use git describe to generate document version and revision metadata. Implies --gitversion"
}


if ! options=$(getopt --longoptions=help,puppeteer,notmp,gitversion,gitstatus,pdf:,latex:,docx:,resourcedir: --options="" -- "$@"); then
	echo "Incorrect options provided"
	print_usage
	exit 1
fi

eval set -- "${options}"
while true; do
	case "$1" in
	--gitversion)
		do_gitversion="yes"
		shift
		;;
	--gitstatus)
		do_gitstatus="yes"
		do_gitversion="yes"
		shift
		;;
	--puppeteer)
		do_puppeteer="yes"
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
	--pdf)
		pdf_output="${2}"
		shift 2
		;;
	--resourcedir)
		resource_dir="${2}"
		shift 2
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

if [ -z "${pdf_output}${latex_output}${docx_output}" ]; then
	>&2 echo "Expected --pdf, --docx or --latex option"
	print_usage
	exit 1
fi

# Set up the output directory, either tmp or build in pwd.
if [ "${is_tmp}" == "yes" ]; then
	build_dir="$(mktemp -d)"
else
	build_dir="$(pwd)/build"
	mkdir -p "${build_dir}"
fi

# Get the default browser
if ! browser=$(command -v "chromium-browser"); then
	if ! browser=$(command -v "google-chrome"); then
		browser="none"
	fi
fi

# figure out git version and revision if needed.
extra_pandoc_options=""
if test "${do_gitversion}" == "yes"; then

	# TODO: Should we fail if dirty?
	raw_version="$(git describe --always --tags)"
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

	# scrub any leading non-numerical arguments from major_minor, ie v4.0, scrub any other nonsense as well
	major_minor="$(tr -d "[:alpha:]" <<< "${major_minor}")"

	extra_pandoc_options="--metadata=version:${major_minor} --metadata=revision:${revision}"
	
	# Do we set document status pased on git version?
	if [ "${do_gitversion}" == "yes" ]; then
		if [ "${revision}" == "0" ]; then
			status="PUBLISHED"
		else
			status="DRAFT"
		fi
		extra_pandoc_options+=" --metadata=status:${status}"
	fi

fi # Done with git version handling

echo "Starting Build with"
echo "file: ${input_file}"
echo "puppeteer: ${do_puppeteer}"
echo "docx: ${docx_output:-none}"
echo "pdf: ${pdf_output:-none}"
echo "latex: ${latex_ouput:-none}"
echo "use tmp: ${is_tmp}"
echo "resource dir: ${resource_dir}"
echo "build dir: ${build_dir}"
echo "browser: ${browser}"
echo "use git version: ${do_gitversion}"
if test "${do_gitversion}" == "yes"; then
	echo "Git Generated Document Version Information"
	echo "    version: ${major_minor}"
	echo "    revision: ${revision}"
	if [ "${do_gitstatus}" == "yes" ]; then
		echo "    status: ${status}"
	fi
fi

if [ "${do_puppeteer}" == "yes" ]; then
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
fi

# Transform 1
# GitHub Mermaid doesn't recognize the full ```{.mermaid ...} attributes-form
# Pandoc doesn't recognized mixed ```mermaid {...} form
# Hack: use sed to transform the former to the latter so everyone is happy
sed 's/```mermaid *{/```{.mermaid /g' "${input_file}" > "${build_dir}/${input_file}.1"


# Transform 2
# \newpage is rendered as the string "\newpage" in GitHub markdown.
# Transform horizontal rules into \newpages.
# Exception: the YAML front matter of the document, so undo the instance on the first line.
sed 's/^---$/\\newpage/g;1s/\\newpage/---/g' "${build_dir}/${input_file}.1" > "${build_dir}/${input_file}.2"

# Transform 3
# Transform sections before the table of contents into section*, which does not number them.
# While we're doing this, transform the case to all-caps.
sed '0,/\\tableofcontents/s/^# \(.*\)/\\section*\{\U\1\}/g' "${build_dir}/${input_file}.2" > "${build_dir}/${input_file}.3"

# Grab the date from the front matter and generate the full date and year.
DATE="$(grep date: "${input_file}" | head -n 1 | cut -d ' ' -f 2)"
YEAR="$(date --date="${DATE}" +%Y)"
DATE_ENGLISH="$(date --date="${DATE}" "+%B %-d, %Y")"

# Run Pandoc
export MERMAID_FILTER_THEME="forest"
export MERMAID_FILTER_FORMAT="pdf"

# Record the running result
RESULT=0

# Generate the pdf
if [ -n "${pdf_output}" ]; then
	echo "Generating PDF Output"
	pandoc \
	    --pdf-engine=lualatex \
		--embed-resources \
		--standalone \
		--template=eisvogel.latex \
		--filter=mermaid-filter \
		--filter=pandoc-crossref \
		--lua-filter=parse-html.lua \
		--lua-filter=table-rules.lua \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--top-level-division=section \
		--variable=block-headings \
		--variable=numbersections \
		--metadata=date-english:"${DATE_ENGLISH}" \
		--metadata=year:"${YEAR}" \
		--metadata=titlepage:true \
		--metadata=titlepage-background:/resources/img/cover.png \
		--metadata=logo:/resources/img/tcg.png \
		--metadata=titlepage-rule-height:0 \
		--metadata=colorlinks:true \
		--metadata=contact:admin@trustedcomputinggroup.org \
		--from=markdown+implicit_figures+grid_tables+table_captions-markdown_in_html_blocks \
		${extra_pandoc_options} \
		--to=pdf \
		"${build_dir}/${input_file}.3" \
		--output="${pdf_output}"
	echo "PDF Output Generated to file: ${pdf_output}"
fi
if [ $? -ne 0 ]; then
	RESULT=$?
fi

# Generate the LaTeX output
if [ -n "${latex_output}" ]; then
	echo "Generating LaTeX Output"
	pandoc \
	    --pdf-engine=lualatex \
		--embed-resources \
		--standalone \
		--template=eisvogel.latex \
		--filter=mermaid-filter \
		--filter=pandoc-crossref \
		--lua-filter=parse-html.lua \
		--lua-filter=table-rules.lua \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--top-level-division=section \
		--variable=block-headings \
		--variable=numbersections \
		--metadata=date-english:"${DATE_ENGLISH}" \
		--metadata=year:"${YEAR}" \
		--metadata=titlepage:true \
		--metadata=titlepage-background:/resources/img/cover.png \
		--metadata=logo:/resources/img/tcg.png \
		--metadata=titlepage-rule-height:0 \
		--metadata=colorlinks:true \
		--metadata=contact:admin@trustedcomputinggroup.org \
		--from=markdown+implicit_figures+grid_tables+table_captions-markdown_in_html_blocks \
		${extra_pandoc_options} \
		--to=latex \
		"${build_dir}/${input_file}.3" \
		--output="${latex_output}"
	echo "LaTeX Output Generated to file: ${latex_output}"
fi
if [ $? -ne 0 ]; then
	RESULT=$?
fi

# Generate the docx output
if [ -n "${docx_output}" ]; then
	echo "Generating DOCX Output"
	pandoc \
	    --pdf-engine=lualatex \
		--embed-resources \
		--standalone \
		--filter=/resources/filters/info.py \
		--filter=mermaid-filter \
		--filter=pandoc-crossref \
		--lua-filter=parse-html.lua \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--from=markdown+implicit_figures+grid_tables+table_captions-markdown_in_html_blocks \
		--reference-doc=/resources/templates/tcg_template.docx \
		${extra_pandoc_options} \
		--to=docx \
		"${build_dir}/${input_file}.3" \
		--output="${docx_output}"
	echo "DOCX Output Generated to file: ${docx_output}"
fi
if [ $? -ne 0 ]; then
	RESULT=$?
fi

if [ ${RESULT} -ne 0 ]; then
	exit 1
fi

# on success remove this output
rm -f mermaid-filter.err

exit 0
