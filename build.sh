#!/usr/bin/env bash

RESOURCE_DIR="/"  #default to root of pandoc container buildout
DO_GITVERSION="yes"
DO_GITSTATUS="yes"
PDF_OUTPUT=""
DOCX_OUTPUT=""
HTML_OUTPUT=""
LATEX_OUTPUT=""
PDFLOG_OUTPUT=""
VERSIONED_FILENAMES="no"
PR_NUMBER=""
PR_REPO=""
DIFFBASE=""
PDF_ENGINE=xelatex

# Start up the dbus daemon (drawio will use it later)
dbus-daemon --system || echo "Failed to start dbus daemon"

# Setup an EXIT handler
on_exit() {
	if [[ -e "${BUILD_DIR}" ]]; then
		rm -rf "${BUILD_DIR}"
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
	echo "Output Control (note that output file names are always relative to the current directory)"
	echo "  --docx=output: enable output of docx and specify the output file name."
	echo "  --pdf=output: enable output of pdf and specify the output file name."
	echo "  --latex=output: enable output of latex and specify the output file name."
	echo "  --html=output: enable output of html and specify the output file name."
	echo "  --pdflog=output: enable logging of pdf engine and specify the output file name."
	echo "  --diff=commit: create diff documents against the provided commit"
	echo
	echo "Miscellaneous"
	echo "  --resourcedir=dir: Set the resource directory, defaults to root for pandoc containers"
	echo "  --gitversion: legacy flag, no effect (default starting with 0.9.0)"
    echo "  --gitstatus: legacy flag, no effect (default starting with 0.9.0)"
	echo "  --nogitversion: Do not use git to describe the generate document version and revision metadata."
	echo "  --table_rules: legacy flag, no effect (default starting with 0.9.0)"
	echo "  --plain_quotes: legacy flag, no effect (default starting with 0.9.0)"
	echo "  --versioned_filenames: insert version information before the file extension for outputs"
	echo "  --pr_number=number: mark the document as a pull-request draft if using Git versioning."
	echo "  --pr_repo=url: provide the URL for the repository for pull-request drafts (has no effect if --PR_NUMBER is not passed)."
	echo "  --pdf_engine=(xelatex|lualatex): use the given latex engine (default xelatex)"
}


if ! options=$(getopt --longoptions=help,puppeteer,gitversion,gitstatus,nogitversion,table_rules,plain_quotes,versioned_filenames,pr_number:,pr_repo:,diff:,pdf:,latex:,pdflog:,pdf_engine:,docx:,html:,resourcedir: --options="" -- "$@"); then
	echo "Incorrect options provided"
	print_usage
	exit 1
fi

eval set -- "${options}"
while true; do
	case "$1" in
	--diff)
		DIFFBASE="${2}"
		shift 2
		;;
	--nogitversion)
		DO_GITSTATUS="no"
		DO_GITVERSION="no"
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
	--table_rules)
		# legacy option; just ignore this
		shift
		;;
	--docx)
		DOCX_OUTPUT="${2}"
		shift 2
		;;
	--latex)
		LATEX_OUTPUT="${2}"
		shift 2
		;;
	--pdflog)
		PDFLOG_OUTPUT="${2}"
		shift 2
		;;
	--pdf_engine)
		PDF_ENGINE="${2}"
		shift 2
		;;
	--pdf)
		PDF_OUTPUT="${2}"
		shift 2
		;;
	--html)
		HTML_OUTPUT="${2}"
		shift 2
		;;
	--resourcedir)
		RESOURCE_DIR="${2}"
		shift 2
		;;
	--versioned_filenames)
		VERSIONED_FILENAMES="yes"
		shift
		;;
	--pr_number)
		PR_NUMBER="${2}"
		shift 2
		;;
	--pr_repo)
		PR_REPO="${2}"
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

# Mark globals set from the command line as readonly when we're done updating them.
readonly RESOURCE_DIR
readonly DO_GITVERSION
readonly DO_GITSTATUS
readonly VERSIONED_FILENAMES
readonly PR_NUMBER
readonly PR_REPO
readonly DIFFBASE
readonly PDF_ENGINE
readonly PDFLOG_OUTPUT

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

if [ -z "${PDF_OUTPUT}${LATEX_OUTPUT}${DOCX_OUTPUT}${HTML_OUTPUT}" ]; then
	>&2 echo "Expected --pdf, --docx, --html, or --latex option"
	print_usage
	exit 1
fi

if [ "${PDF_ENGINE}" != "xelatex" -a "${PDF_ENGINE}" != "lualatex" ]; then
	>&2 echo "Unsupported PDF engine '${PDF_ENGINE}', expected one of: xelatex, lualatex"
	print_usage
	exit 1
fi

# Set up the build directory.
readonly BUILD_DIR="/tmp/tcg.pandoc"
readonly SOURCE_DIR=$(pwd)
mkdir -p "${BUILD_DIR}"
# Copy everything into the build directory, then cd to that directory.
# This will allow us to manipulate the Git state without side effects
# to callers of docker_run.
cp -r . "${BUILD_DIR}"
cd "${BUILD_DIR}"

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
if test "${DO_GITVERSION}" == "yes"; then
	git config --global --add safe.directory /workspace

	# TODO: Should we fail if dirty?
	raw_version="$(git describe --always --tags)"
	echo "Git version: ${raw_version}"
	# Trim leading letters like v etc
	raw_version=$(echo "${raw_version}" | sed -E 's/^[a-zA-Z]*(.*)/\1/')
	IFS='-' read -r -a dash_hunks <<< "${raw_version}"

	# Assume the tags are based on semantic versioning.
    # Could be one of:
	#   Where $COMMIT is the first few digits of a commit hash
    # g$COMMIT - commit no tag (len 1)
	#   Where $VERSION is like v1.2.3
   	# $VERSION --> at the version $VERSION (len 1)
	#   Where $PRERELEASE is like rc.1
	# $VERSION-$PRERELEASE --> at the version $VERSION-$PRERELEASE (len 2)
	#   Where $REVISION is the number of commits since the last tag (e.g., 54)
	# $VERSION-$REVISION-g$COMMIT --> version without prerelease tag at a particular commit (len 3)
	# $VERSION-$PRERELEASE-$REVISION-g$COMMIT --> version with  (len 4)
	GIT_COMMIT=$(git rev-parse --short HEAD)
	len=${#dash_hunks[@]}
	case $len in
		1)
			# If there is one hunk in the version information, it's either the tag (for a release)
			# or the commit (not a release).
			if [ ! -z $(git tag --points-at HEAD) ]; then
				GIT_VERSION="${dash_hunks[0]}"
			fi
			;;
		2)
			GIT_VERSION="${dash_hunks[0]}"
			GIT_PRERELEASE="${dash_hunks[1]}"
			;;
		3)
			if [ "${dash_hunks[2]:0:1}" == "g" ]; then
				GIT_VERSION="${dash_hunks[0]}"
				GIT_REVISION="${dash_hunks[1]}"
			else
				>&2 echo "Malformed Git version: ${raw_version}"
				exit 1
			fi
			;;
		4)
			if [ "${dash_hunks[3]:0:1}" == "g" ]; then
				GIT_VERSION="${dash_hunks[0]}"
				GIT_PRERELEASE="${dash_hunks[1]}"
				GIT_REVISION="${dash_hunks[2]}"
			else
				>&2 echo "Malformed Git version: ${raw_version}"
				exit 1
			fi
			;;
		*)
	    	>&2 echo "Malformed Git version: ${raw_version}"
	    	exit 1
			;;
	esac

	if [ ! -z "${PR_NUMBER}" ]; then
		# In the case of a PR, always just provide the PR number and commit
		extra_pandoc_options+=" --metadata=PR_NUMBER:${PR_NUMBER}"
		extra_pandoc_options+=" --metadata=revision:${GIT_COMMIT}"
		status="Pull Request"
		if [ ! -z "${PR_REPO}" ]; then
			extra_pandoc_options+=" --metadata=PR_REPO_url:https://github.com/${PR_REPO}"
		fi
	else
		# Otherwise, populate the full context based on what git show said.
		extra_pandoc_options+=" --metadata=version:${GIT_VERSION}"

		if [ ! -z "${GIT_PRERELEASE}" ]; then
			extra_pandoc_options+=" --metadata=prerelease:${GIT_PRERELEASE}"
		fi

		# Omit the revision if there isn't one (i.e., we are at straight-up Version)
		if [ ! -z "${GIT_REVISION}" ]; then
			extra_pandoc_options+=" --metadata=revision:${GIT_REVISION}"
		elif [ -z "${GIT_VERSION}" ]; then
			extra_pandoc_options+=" --metadata=revision:${GIT_COMMIT}"
		fi

		# Do we set document status based on git version?
		if [ "${DO_GITSTATUS}" == "yes" ]; then
			# If revision is 0 and this is not some kind of prerelease
			if [ ! -z "${GIT_VERSION}" ] &&  [ -z "${GIT_REVISION}" ] && [ -z "${GIT_PRERELEASE}" ]; then
				status="Published"
			# If revision is 0 and this is some kind of prerelease
			elif [ -z "${GIT_REVISION}" ] && [ ! -z "${GIT_PRERELEASE}" ]; then
				status="Review"
			# Everything else is a draft
			else
				status="Draft"
			fi
		fi
	fi
	extra_pandoc_options+=" --metadata=status:\"${status}\""

fi # Done with git version handling

prefix_filename() {
	local prefix=$1
	local full_filename=$2
	local dirname=$(dirname "${full_filename}")
	local filename=$(basename "${full_filename}")
	local extension="${filename##*.}"
	local stripped="${filename%.*}"
	local result=""
	if [ ! -z "${dirname}" ]; then
		result="${dirname}/"
	fi
	result="${result}${stripped}${prefix}.${extension}"
	echo "${result}"
}

# Rename output files based on version info
if [ "${VERSIONED_FILENAMES}" == "yes" ]; then
	if [ ! -z "${PR_NUMBER}" ]; then
		version_prefix=".pr${PR_NUMBER}.${GIT_COMMIT}"
	else
		version_prefix=""
		if [ ! -z "${GIT_VERSION}" ]; then
			version_prefix="${version_prefix}.${GIT_VERSION}"
		fi
		if [ ! -z "${GIT_PRERELEASE}" ]; then
			version_prefix="${version_prefix}.${GIT_PRERELEASE}"
		fi
		if [ ! -z "${GIT_REVISION}" ]; then
			version_prefix="${version_prefix}.${GIT_REVISION}"
		fi
	fi

	if [ ! -z "${DOCX_OUTPUT}" ]; then
		DOCX_OUTPUT=$(prefix_filename "${version_prefix}" "${DOCX_OUTPUT}")
	fi
	if [ ! -z "${PDF_OUTPUT}" ]; then
		PDF_OUTPUT=$(prefix_filename "${version_prefix}" "${PDF_OUTPUT}")
	fi
	if [ ! -z "${LATEX_OUTPUT}" ]; then
		LATEX_OUTPUT=$(prefix_filename "${version_prefix}" "${LATEX_OUTPUT}")
	fi
	if [ ! -z "${HTML_OUTPUT}" ]; then
		HTML_OUTPUT=$(prefix_filename "${version_prefix}" "${HTML_OUTPUT}")
	fi
fi
readonly PDF_OUTPUT
readonly DOCX_OUTPUT
readonly HTML_OUTPUT
readonly LATEX_OUTPUT

echo "Starting Build with"
echo "file: ${input_file}"
echo "docx: ${DOCX_OUTPUT:-none}"
echo "pdf: ${PDF_OUTPUT:-none} (engine: ${PDF_ENGINE})"
echo "latex: ${latex_ouput:-none}"
echo "html: ${html_ouput:-none}"
echo "resource dir: ${RESOURCE_DIR}"
echo "build dir: ${BUILD_DIR}"
echo "browser: ${browser}"
echo "use git version: ${DO_GITVERSION}"
echo "use table rules: ${TABLE_RULES}"
echo "make block quotes Informative Text: ${BLOCK_QUOTES_ARE_INFORMATIVE_TEXT}"
if [ ! -z "${DIFFBASE}" ]; then
	echo "diff against: ${DIFFBASE}"
fi
if test "${DO_GITVERSION}" == "yes"; then
	echo "Git Generated Document Version Information"
	if [ ! -z "${GIT_VERSION}" ]; then
		echo "    version: ${GIT_VERSION}"
	fi
	if [ ! -z "${GIT_PRERELEASE}" ]; then
		echo "    prerelease: ${GIT_PRERELEASE}"
	fi
	if [ ! -z "${GIT_REVISION}" ]; then
		echo "    revision: ${GIT_REVISION}"
	fi
	if [ ! -z "${GIT_COMMIT}" ]; then
		echo "    commit: ${GIT_COMMIT}"
	fi
	if [ "${DO_GITSTATUS}" == "yes" ]; then
		echo "    status: ${status}"
	fi
fi

if [ "${browser}" == "none" ]; then
	>&2 echo "No Browser found, looked for chromium-browser and google-chrome"
	exit 1
fi

# There are some configuration dependencies required for Mermaid.
# They have to be in the current directory.
# --disable-gpu is added here based on:
# https://github.com/puppeteer/puppeteer/issues/11640
cat <<- EOF > ./.puppeteer.json
{
	"executablePath": "$browser",
	"args": [
		"--no-sandbox",
		"--disable-setuid-sandbox",
		"--disable-gpu"
	]
}
EOF

if [ "${BLOCK_QUOTES_ARE_INFORMATIVE_TEXT}" == "yes" ]; then
	extra_pandoc_options+=" --lua-filter=informative-quote-blocks.lua"
fi

# Hacks

# \newpage is rendered as the string "\newpage" in GitHub markdown.
# Transform horizontal rules into \newpages.
# Exception: the YAML front matter of the document, so undo the instance on the first line.
# TODO: Turn this into a Pandoc filter.
sed -i.bak 's/^---$/\\newpage/g;1s/\\newpage/---/g' "${BUILD_DIR}/${input_file}"

# Transform sections before the table of contents into section*, which does not number them.
# While we're doing this, transform the case to all-caps.
# TODO: Turn this into a Pandoc filter.
sed -i.bak '0,/\\tableofcontents/s/^# \(.*\)/\\section*\{\U\1\}/g' "${BUILD_DIR}/${input_file}"

if test "${DO_GITVERSION}" == "yes"; then
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

cp /resources/filters/mermaid-config.json .mermaid-config.json
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
	local times=$1
	shift
	local command="$@"
	local n=1
	until [ "${n}" -gt "${times}" ]; do
		eval "${command[@]}" && return 0
		if [ "${n}" -lt "${times}" ]; then
			echo "Assuming transient error. Retrying up to ${times} times..."
		fi
		n=$((n+1))
	done
	echo "Command failed after ${times}"
	return 1
}

readonly TEMP_TEX_FILE="${BUILD_DIR}/${input_file}.tex"
# LaTeX engines choose this filename based on TEMP_TEX_FILE's basename. It also emits a bunch of other files.
readonly TEMP_PDF_FILE="$(basename ${input_file}).pdf"
readonly LATEX_LOG="${BUILD_DIR}/latex.log"

analyze_latex_logs() {
	local logfile=$1

	local runcount=$(grep "Run number " "${logfile}" | tail -n 1 | cut -d ' ' -f 3)
	local passes="passes"
	if [ "${runcount}" -eq "1" ]; then
		passes="pass"
	fi
	echo "Completed PDF rendering after ${runcount} ${passes}."

	# Print any warnings from only the last run.
	local warnings=$(sed -n "/Run number ${runcount}/,$ p" "${logfile}" | grep "LaTeX Warning: ")
	if [ ! -z "${warnings}" ]; then
		echo "LaTeX warnings (may be ignorable - check the output!):"
		echo "${warnings}"
	fi
}

# For LaTeX and PDF output, we use Pandoc to compile to an intermediate .tex file
# That way, LaTeX errors on PDF output point to lines that match the .tex.
if [ -n "${PDF_OUTPUT}" -o -n "${LATEX_OUTPUT}" ]; then
	if [ -n "${PDF_OUTPUT}" ]; then
		mkdir -p "${SOURCE_DIR}/$(dirname ${PDF_OUTPUT})"
	fi
	if [ -n "${LATEX_OUTPUT}" ]; then
		mkdir -p "${SOURCE_DIR}/$(dirname ${LATEX_OUTPUT})"
	fi
	echo "Generating LaTeX Output"
	start=$(date +%s)
	cmd=(pandoc
		--standalone
		--template=tcg.tex
		--lua-filter=mermaid-code-class-pre.lua
		--filter=mermaid-filter
		--lua-filter=informative-sections.lua
		--lua-filter=convert-images.lua
		--lua-filter=center-images.lua
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
		"'${BUILD_DIR}/${input_file}'")
	retry 5 "${cmd[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "LaTeX/PDF output failed"
	fi
	end=$(date +%s)
	echo "Elapsed time: $(($end-$start)) seconds"

	if [ -n "${LATEX_OUTPUT}" ]; then
		cp "${TEMP_TEX_FILE}" "${SOURCE_DIR}/${LATEX_OUTPUT}"
	fi

	if [ -n "${PDF_OUTPUT}" ]; then
		echo "Rendering PDF"
		start=$(date +%s)
		# latexmk takes care of repeatedly calling the PDF engine. A run may take multiple passes due to the need to
		# update .toc and other files.
		latexmk "${TEMP_TEX_FILE}" -pdflatex="${PDF_ENGINE}" -pdf -diagnostics > "${LATEX_LOG}"
		if [ $? -ne 0 ]; then
			FAILED=true
			echo "PDF output failed"
		fi
		end=$(date +%s)
		# Write any LaTeX errors to stderr.
		>&2 grep -A 5 "] ! " "${LATEX_LOG}"

		# Copy aux, lof, lot, and toc files back to the source directory so they can be cached and speed up future runs.
		if [ -n "${PDFLOG_OUTPUT}" ]; then
			cp "${LATEX_LOG}" "${PDFLOG_OUTPUT}"
		fi
		cp *.aux "${SOURCE_DIR}"
		cp *.lof "${SOURCE_DIR}"
		cp *.lot "${SOURCE_DIR}"
		cp *.toc "${SOURCE_DIR}"
		# Copy converted images so they can be cached as well.
		cp *.convert.pdf "${SOURCE_DIR}"
		echo "Elapsed time: $(($end-$start)) seconds"
		# Write any LaTeX errors to stderr.
		>&2 grep -A 5 "! " "${LATEX_LOG}"
		if [[ ! "${FAILED}" = "true" ]]; then
			mv "${TEMP_PDF_FILE}" "${SOURCE_DIR}/${PDF_OUTPUT}"
			analyze_latex_logs "${LATEX_LOG}"
		fi
	fi	
fi

# Generate the docx output
if [ -n "${DOCX_OUTPUT}" ]; then
	# Prepare the title-page for the docx version.
	subtitle="Version ${GIT_VERSION:-${DATE}}, Revision ${GIT_REVISION:-0}"
	# Prefix the document with a Word page-break, since Pandoc doesn't do docx
	# title pages.
	cat <<- 'EOF' > "${BUILD_DIR}/${input_file}.prefixed"
	```{=openxml}
	<w:p>
		<w:r>
			<w:br w:type="page"/>
		</w:r>
	</w:p>
	```
	EOF
	cat ${BUILD_DIR}/${input_file} >> ${BUILD_DIR}/${input_file}.prefixed

	mkdir -p "${SOURCE_DIR}/$(dirname ${DOCX_OUTPUT})"
	echo "Generating DOCX Output"
	cmd=(pandoc
		--embed-resources
		--standalone
		--lua-filter=mermaid-code-class-pre.lua
		--filter=mermaid-filter
		--lua-filter=convert-images.lua
		--lua-filter=parse-html.lua
		--lua-filter=apply-classes-to-tables.lua
		--lua-filter=landscape-pages.lua
		--lua-filter=style-fenced-divs.lua
		--filter=pandoc-crossref
		--resource-path=.:/resources
		--data-dir=/resources
		--from='${FROM}+raw_attribute'
		--metadata=subtitle:"'${subtitle}'"
		--reference-doc=/resources/templates/tcg.docx
		${extra_pandoc_options}
		--to=docx
		--output="'${SOURCE_DIR}/${DOCX_OUTPUT}'"
		"'${BUILD_DIR}/${input_file}.prefixed'")
	retry 5 "${cmd[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "DOCX output failed"
	else
		echo "DOCX output generated to file: ${DOCX_OUTPUT}"
	fi
fi

# Generate the html output
export MERMAID_FILTER_FORMAT="svg"
if [ -n "${HTML_OUTPUT}" ]; then
	mkdir -p "${SOURCE_DIR}/$(dirname ${HTML_OUTPUT})"
	echo "Generating html Output"
	cmd=(pandoc
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
		--output="'${SOURCE_DIR}/${HTML_OUTPUT}'"
		"'${BUILD_DIR}/${input_file}'")
	retry 5 "${cmd[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "HTML output failed"
	else
		echo "HTML output generated to file: ${HTML_OUTPUT}"
	fi
fi

if [ "${FAILED}" = "true" ]; then
	echo "Overall workflow failed"
	exit 1
fi

# on success remove this output
rm -f core
rm -f mermaid-filter.err .mermaid-config.json
rm -f .puppeteer.json
rm -f "${BUILD_DIR}/${input_file}.bak"

echo "Overall workflow succeeded"
exit 0
