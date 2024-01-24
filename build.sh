#!/usr/bin/env bash

is_tmp="yes"	  # default to no tmp directory
resource_dir="/"  #default to root of pandoc container buildout
do_gitversion="no"
do_gitstatus="no"
pdf_output=""
docx_output=""
html_output=""
latex_output=""
table_rules="no"
block_quotes_are_informative_text="yes"

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
	echo "  --html=output: enable outputing of html and specify the output file name."
	echo
	echo "Miscellaneous"
	echo "  --resourcedir=dir: Set the resource directory, defaults to root for pandoc containers"
	echo "  --notmp: Do not use a tempory directory for processing steps, instead create a directory called \"build\" in CWD"
	echo "  --gitversion: Use git describe to generate document version and revision metadata."
    echo "  --gitstatus: Use git describe to generate document version and revision metadata. Implies --gitversion"
	echo "  --table_rules: style tables with borders (does not work well for tables that use rowspan or colspan)"
	echo "  --plain_quotes: Support quote blocks as quote blocks instead of repurposing them as Informative Text blocks."
}


if ! options=$(getopt --longoptions=help,puppeteer,notmp,gitversion,gitstatus,table_rules,plain_quotes,pdf:,latex:,docx:,html:,resourcedir: --options="" -- "$@"); then
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
		# legacy option; just ignore this
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
	--plain_quotes)
		block_quotes_are_informative_text="no"
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

if [ "${table_rules}" == "yes" ]; then
	extra_pandoc_options+=" --lua-filter=table-rules.lua"
fi

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
# * Support fenced_divs (for informative block div syntax)
# * Implicit_figures for figure numbering/table-of-figures support for images and diagrams
# * Multiline_tables and grid_tables to support nontrivial table content
# * Table_captions so that tables can be captioned
# * DISABLING 'markdown_in_html_blocks' which breaks the ability to embed tables in HTML form.
FROM="markdown+fenced_divs+implicit_figures+multiline_tables+grid_tables+table_captions-markdown_in_html_blocks"

# First, we do a Markdown->Markdown Pandoc pass. This serves two purposes:
# 1. Generate the diagrams before pandoc-crossref starts its work. https://github.com/raghur/mermaid-filter/issues/39#issuecomment-1703911386
# 2. Mermaid-filter uses an actual browser to do its work, and sometimes that process times out. Retry if needed.
do_mermaid() {
	format=$1
	md_file_in=$2
	md_file_out=$3
	export MERMAID_FILTER_THEME="forest"
	export MERMAID_FILTER_FORMAT="${format}"
	pandoc \
		--filter=mermaid-filter \
		--standalone \
		--from=${FROM} \
		"${md_file_in}" \
		--to=markdown \
		--output="${md_file_out}"
}

# For PDF, latex, and docx outputs, create PDF figures.
if [ -n "${pdf_output}" -o "${latex_output}" -o "${docx_output}" ]; then
	# Try up to 5 times to run the Mermaid filter.
	n=0
	until [ "$n" -ge 5 ]; do
		do_mermaid "pdf" "${build_dir}/${input_file}" "${build_dir}/${input_file}.pdfmermaid.md" && echo "Generated Mermaid diagrams" &&  break
		echo "Assuming transient error. Retrying Mermaid diagrams..."
		n=$((n+1)) 
	done
fi

# Generate the pdf
if [ -n "${pdf_output}" ]; then
	mkdir -p "$(dirname ${pdf_output})"
	echo "Generating PDF Output"
	pandoc \
		--pdf-engine=lualatex \
		--embed-resources \
		--standalone \
		--template=eisvogel.latex \
		--lua-filter=parse-html.lua \
		--lua-filter=style-fenced-divs.lua \
		--filter=pandoc-crossref \
		--lua-filter=divide-code-blocks.lua \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--top-level-division=section \
		--variable=block-headings \
		--variable=numbersections \
		--metadata=date:"${DATE}" \
		--metadata=date-english:"${DATE_ENGLISH}" \
		--metadata=year:"${YEAR}" \
		--metadata=titlepage:true \
		--metadata=titlepage-background:/resources/img/cover.png \
		--metadata=crossrefYaml:/resources/filters/pandoc-crossref.yaml \
		--metadata=logo:/resources/img/tcg.png \
		--metadata=titlepage-rule-height:0 \
		--metadata=colorlinks:true \
		--metadata=contact:admin@trustedcomputinggroup.org \
		--from=${FROM} \
		${extra_pandoc_options} \
		--to=pdf \
		--output="${pdf_output}" \
		"${build_dir}/${input_file}.pdfmermaid.md"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "PDF output failed"
	else
		echo "PDF output generated to file: ${pdf_output}"
	fi
fi

# Generate the LaTeX output
if [ -n "${latex_output}" ]; then
	mkdir -p "$(dirname ${latex_output})"
	echo "Generating LaTeX Output"
	pandoc \
		--pdf-engine=lualatex \
		--embed-resources \
		--standalone \
		--template=eisvogel.latex \
		--lua-filter=parse-html.lua \
		--lua-filter=style-fenced-divs.lua \
		--filter=pandoc-crossref \
		--lua-filter=divide-code-blocks.lua \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--top-level-division=section \
		--variable=block-headings \
		--variable=numbersections \
		--metadata=titlepage:true \
		--metadata=titlepage-background:/resources/img/cover.png \
		--metadata=crossrefYaml:/resources/filters/pandoc-crossref.yaml \
		--metadata=logo:/resources/img/tcg.png \
		--metadata=titlepage-rule-height:0 \
		--metadata=colorlinks:true \
		--metadata=contact:admin@trustedcomputinggroup.org \
		--from=${FROM} \
		${extra_pandoc_options} \
		--to=latex \
		--output="${latex_output}" \
		"${build_dir}/${input_file}.pdfmermaid.md"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "LaTeX output failed"
	else
		echo "LaTeX output generated to file: ${latex_output}"
	fi
fi

# Generate the docx output
if [ -n "${docx_output}" ]; then
	mkdir -p "$(dirname ${docx_output})"
	echo "Generating DOCX Output"
	# workaround to make mermaid and crossref play nice together: https://github.com/raghur/mermaid-filter/issues/39#issuecomment-1703911386
	pandoc \
		--pdf-engine=lualatex \
		--embed-resources \
		--standalone \
		--filter=/resources/filters/info.py \
		--lua-filter=parse-html.lua \
		--lua-filter=style-fenced-divs.lua \
		--filter=pandoc-crossref \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--from=${FROM} \
		--reference-doc=/resources/templates/tcg_template.docx \
		${extra_pandoc_options} \
		--to=docx \
		--output="${docx_output}" \
		"${build_dir}/${input_file}.pdfmermaid.md"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "DOCX output failed"
	else
		echo "DOCX output generated to file: ${docx_output}"
	fi
fi

# For HTML outputs, create SVG figures.
if [ -n "${html_output}" ]; then
	# Try up to 5 times to run the Mermaid filter.
	n=0
	until [ "$n" -ge 5 ]; do
		do_mermaid "svg" "${build_dir}/${input_file}" "${build_dir}/${input_file}.svgmermaid.md" && break
		n=$((n+1)) 
	done
fi


# Generate the html output
if [ -n "${html_output}" ]; then
	mkdir -p "$(dirname ${html_output})"
	echo "Generating html Output"
	pandoc \
		--toc \
		-V colorlinks=true \
		-V linkcolor=blue \
		-V urlcolor=blue \
		-V toccolor=blue \
		--embed-resources \
		--standalone \
		--lua-filter=parse-html.lua \
		--filter=pandoc-crossref \
		--lua-filter=divide-code-blocks.lua \
		--lua-filter=style-fenced-divs.lua \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--top-level-division=section \
		--variable=block-headings \
		--variable=numbersections \
		--metadata=titlepage:true \
		--metadata=titlepage-background:/resources/img/cover.png \
		--metadata=crossrefYaml:/resources/filters/pandoc-crossref.yaml \
		--metadata=logo:/resources/img/tcg.png \
		--metadata=titlepage-rule-height:0 \
		--metadata=colorlinks:true \
		--metadata=contact:admin@trustedcomputinggroup.org \
		--from=${FROM} \
		${extra_pandoc_options} \
		--to=html \
		--output="${html_output}" \
		"${build_dir}/${input_file}.svgmermaid.md"
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
