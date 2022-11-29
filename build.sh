#!/usr/bin/env bash

is_tmp="yes"	  # default to no tmp directory
resource_dir="/"  #default to root of pandoc container buildout
do_puppeteer="no"
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
	echo "  This script takes a single markdown file input for rendering to docx/pdf/LaTex."
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
	echo "  --resouredir=dir: Set the resource directory, defaults to root for pandoc containers"
	echo "  --notmp: Do not use a tempory directory for processing steps, instead create a directory called \"build\" in CWD"
}


if ! options=$(getopt --longoptions=help,puppeteer,pdf:,latex:,docx:,notmp,resouredir: --options="" -- "$@"); then
	echo "Incorrect options provided"
	print_usage
	exit 1
fi

eval set -- "${options}"
while true; do
	case "$1" in
	--puppeteer)
		do_puppeteer="yes"
		shift 2
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
	--notmp)
		is_tmp="no"
		shift
		;;
	--resouredir)
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
# Transform sections before the table of contents into addsec, which does not number them.
# While we're doing this, transform the case to all-caps.
sed '0,/\\tableofcontents/s/^# \(.*\)/\\addsec\{\U\1\}/g' "${build_dir}/${input_file}.2" > "${build_dir}/${input_file}.3"

# Grab the date from the front matter and generate the full date and year.
DATE="$(grep date: "${input_file}" | head -n 1 | cut -d ' ' -f 2)"
YEAR="$(date --date="${DATE}" +%Y)"
DATE_ENGLISH="$(date --date="${DATE}" "+%B %-d, %Y")"

# Run Pandoc
export MERMAID_FILTER_THEME="forest"
export MERMAID_FILTER_FORMAT="pdf"

# Generate the pdf
if [ -n "${pdf_output}" ]; then
	echo "Generating PDF Output"
	pandoc \
		--embed-resources \
		--standalone \
		--template=eisvogel.latex \
		--filter=mermaid-filter \
		--filter=pandoc-crossref \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--top-level-division=section \
		--variable=block-headings \
		--variable=numbersections \
		--variable=table-use-row-colors \
		--metadata=date-english:"${DATE_ENGLISH}" \
		--metadata=year:"${YEAR}" \
		--metadata=titlepage:true \
		--metadata=titlepage-background:/resources/img/cover.png \
		--metadata=logo:/resources/img/tcg.png \
		--metadata=titlepage-rule-height:0 \
		--metadata=colorlinks:true \
		--metadata=contact:admin@trustedcomputinggroup.org \
		--from=markdown+implicit_figures+table_captions \
		--to=pdf \
		"${build_dir}/${input_file}.3" \
		--output="${pdf_output}"
	echo "PDF Output Generated to file: ${pdf_output}"
fi

# Generate the LaTeX output
if [ -n "${latex_output}" ]; then
	echo "Generating LaTeX Output"
	pandoc \
		--embed-resources \
		--standalone \
		--template=eisvogel.latex \
		--filter=mermaid-filter \
		--filter=pandoc-crossref \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--top-level-division=section \
		--variable=block-headings \
		--variable=numbersections \
		--variable=table-use-row-colors \
		--metadata=date-english:"${DATE_ENGLISH}" \
		--metadata=year:"${YEAR}" \
		--metadata=titlepage:true \
		--metadata=titlepage-background:/resources/img/cover.png \
		--metadata=logo:/resources/img/tcg.png \
		--metadata=titlepage-rule-height:0 \
		--metadata=colorlinks:true \
		--metadata=contact:admin@trustedcomputinggroup.org \
		--from=markdown+implicit_figures+table_captions \
		--to=latex \
		"${build_dir}/${input_file}.3" \
		--output="${latex_output}"
	echo "LaTeX Output Generated to file: ${latex_output}"
fi

# Generate the docx output
if [ -n "${docx_output}" ]; then
	echo "Generating DOCX Output"
	pandoc \
		--embed-resources \
		--standalone \
		--filter=/resources/filters/info.py \
		--filter=mermaid-filter \
		--filter=pandoc-crossref \
		--resource-path=.:/resources \
		--data-dir=/resources \
		--from=markdown+implicit_figures+table_captions \
		--reference-doc=/resources/templates/tcg_template.docx \
		--to=docx \
		"${build_dir}/${input_file}.3" \
		--output="${docx_output}"
	echo "DOCX Output Generated to file: ${docx_output}"
fi
if [ $? -ne 0 ]; then
	exit 1
fi

# on success remove this output
rm -f mermaid-filter.err

exit 0
