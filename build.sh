#!/usr/bin/env bash

RESOURCE_DIR="/"  #default to root of pandoc container buildout
DO_GITVERSION="yes"
DO_GITSTATUS="yes"
PDF_OUTPUT=""
DIFFPDF_OUTPUT=""
DIFFTEX_OUTPUT=""
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
	echo "  --diffpdf=output: enable output of pdf diff and specify the output file name (requires --diffbase)"
	echo "  --difftex=output: enable output of tex diff and specify the output file name (requires --diffbase)"
	echo "  --diffbase=ref: create diff documents against the provided commit (no effect if --diffpdf or --difftex is not provided)"
	echo "  --diffpdflog=output: enable logging of pdf engine during diffing and specify the output file name."
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


if ! options=$(getopt --longoptions=help,puppeteer,gitversion,gitstatus,nogitversion,table_rules,plain_quotes,versioned_filenames,pr_number:,pr_repo:,diffbase:,pdf:,diffpdf:,difftex:,diffpdflog:,latex:,pdflog:,pdf_engine:,docx:,html:,resourcedir: --options="" -- "$@"); then
	echo "Incorrect options provided"
	print_usage
	exit 1
fi

eval set -- "${options}"
while true; do
	case "$1" in
	--diffbase)
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
	--diffpdf)
		DIFFPDF_OUTPUT="${2}"
		shift 2
		;;
	--difftex)
		DIFFTEX_OUTPUT="${2}"
		shift 2
		;;
	--diffpdflog)
		DIFFPDFLOG_OUTPUT="${2}"
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

shift "$(( OPTIND - 1 ))"

# argcount check
if [ $# -ne 1 ]; then
	>&2 echo "Expected 1 markdown input file for processing, got: $*"
	print_usage
	exit 1
fi

# input file check
INPUT_FILE=$1
if [ ! -e "${INPUT_FILE}" ]; then
   >&2 echo "${INPUT_FILE} does not exist, exiting..."
   exit 1
fi

# at least one output must be requested
if [ -z "${PDF_OUTPUT}${LATEX_OUTPUT}${DOCX_OUTPUT}${HTML_OUTPUT}" ]; then
	>&2 echo "Expected --pdf, --docx, --html, or --latex option"
	print_usage
	exit 1
fi

# the pdf engine must be supported
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

# Let git work
git config --global --add safe.directory "${BUILD_DIR}"

# make sure the diff arguments make sense
if [ -n "${DIFFPDF_OUTPUT}" -o -n "${DIFFTEX_OUTPUT}" ]; then
	# --diffbase must be provided, and it must make sense to Git
	if [ -z "${DIFFBASE}" ]; then
		>&2 echo "--diffpdf was provided, but --diffbase was not."
		print_usage
		exit 1
	fi
	git rev-parse --verify "${DIFFBASE}" > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		>&2 echo "--diffbase was provided, but it was not a valid Git commit, tag, or branch name."
		print_usage
		exit 1
	fi
fi

# Get the default browser
if ! browser=$(command -v "chromium-browser"); then
	if ! browser=$(command -v "chromium"); then
		if ! browser=$(command -v "google-chrome"); then
			browser="none"
		fi
	fi
fi

# figure out git version and revision if needed.
EXTRA_PANDOC_OPTIONS=""
if test "${DO_GITVERSION}" == "yes"; then
	if [ ! -z "${PR_NUMBER}" ] && $(git rev-parse HEAD^2 >/dev/null 2>/dev/null); then
		# For PR workflows, base the version info on the right parent.
		# In the context of a GitHub pull request, HEAD is a merge commit where
		# parent1 (HEAD^1) is the target branch and parent2 (HEAD~2) is the source
		GIT_COMMIT=$(git rev-parse --short HEAD^2)
	else
		# Otherwise, base the version info on HEAD.
		GIT_COMMIT=$(git rev-parse --short HEAD)
	fi

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
		EXTRA_PANDOC_OPTIONS+=" --metadata=PR_NUMBER:${PR_NUMBER}"
		EXTRA_PANDOC_OPTIONS+=" --metadata=revision:${GIT_COMMIT}"
		status="Pull Request"
		if [ ! -z "${PR_REPO}" ]; then
			EXTRA_PANDOC_OPTIONS+=" --metadata=PR_REPO_url:https://github.com/${PR_REPO}"
		fi
	else
		# Otherwise, populate the full context based on what git show said.
		EXTRA_PANDOC_OPTIONS+=" --metadata=version:${GIT_VERSION}"

		if [ ! -z "${GIT_PRERELEASE}" ]; then
			EXTRA_PANDOC_OPTIONS+=" --metadata=prerelease:${GIT_PRERELEASE}"
		fi

		# Omit the revision if there isn't one (i.e., we are at straight-up Version)
		if [ ! -z "${GIT_REVISION}" ]; then
			EXTRA_PANDOC_OPTIONS+=" --metadata=revision:${GIT_REVISION}"
		elif [ -z "${GIT_VERSION}" ]; then
			EXTRA_PANDOC_OPTIONS+=" --metadata=revision:${GIT_COMMIT}"
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
	EXTRA_PANDOC_OPTIONS+=" --metadata=status:\"${status}\""

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
	if [ ! -z "${DIFFPDF_OUTPUT}" ]; then
		DIFFPDF_OUTPUT=$(prefix_filename ".$(echo ${DIFFBASE} | cut -c1-10).to${version_prefix}" "${DIFFPDF_OUTPUT}")
	fi
	if [ ! -z "${DIFFTEX_OUTPUT}" ]; then
		DIFFTEX_OUTPUT=$(prefix_filename ".$(echo ${DIFFBASE} | cut -c1-10).to${version_prefix}" "${DIFFTEX_OUTPUT}")
	fi
	if [ ! -z "${PDFLOG_OUTPUT}" ]; then
		PDFLOG_OUTPUT=$(prefix_filename "${version_prefix}" "${PDFLOG_OUTPUT}")
	fi
	if [ ! -z "${DIFFPDFLOG_OUTPUT}" ]; then
		DIFFPDFLOG_OUTPUT=$(prefix_filename ".$(echo ${DIFFBASE} | cut -c1-10).to${version_prefix}" "${DIFFPDFLOG_OUTPUT}")
	fi
	if [ ! -z "${LATEX_OUTPUT}" ]; then
		LATEX_OUTPUT=$(prefix_filename "${version_prefix}" "${LATEX_OUTPUT}")
	fi
	if [ ! -z "${HTML_OUTPUT}" ]; then
		HTML_OUTPUT=$(prefix_filename "${version_prefix}" "${HTML_OUTPUT}")
	fi
fi
readonly PDF_OUTPUT
readonly DIFFPDF_OUTPUT
readonly DIFFTEX_OUTPUT
readonly DOCX_OUTPUT
readonly HTML_OUTPUT
readonly LATEX_OUTPUT
readonly PDFLOG_OUTPUT
readonly DIFFPDFLOG_OUTPUT

echo "Starting Build with"
echo "file: ${INPUT_FILE}"
echo "docx: ${DOCX_OUTPUT:-none}"
echo "pdf: ${PDF_OUTPUT:-none} (engine: ${PDF_ENGINE})"
echo "diff pdf: ${DIFFPDF_OUTPUT:-none} (engine: ${PDF_ENGINE})"
echo "latex: ${latex_ouput:-none}"
echo "diff latex: ${DIFFTEX_OUTPUT:-none} "
echo "html: ${html_ouput:-none}"
echo "resource dir: ${RESOURCE_DIR}"
echo "build dir: ${BUILD_DIR}"
echo "browser: ${browser}"
echo "use git version: ${DO_GITVERSION}"
if [ ! -z "${DIFFBASE}" ]; then
	echo "diff against: ${DIFFBASE} ($(git rev-parse --verify ${DIFFBASE}))"
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
	EXTRA_PANDOC_OPTIONS+=" --lua-filter=informative-quote-blocks.lua"
fi

# Use sed to perform some basic fixups on certain input files.
do_md_fixups() {
	local input=$1
	# \newpage is rendered as the string "\newpage" in GitHub markdown.
	# Transform horizontal rules into \newpages.
	# Exception: the YAML front matter of the document, so undo the instance on the first line.
	# TODO: Turn this into a Pandoc filter.
	sed -i.bak 's/^---$/\\newpage/g;1s/\\newpage/---/g' "${input}"

	# Transform sections before the table of contents into section*, which does not number them.
	# While we're doing this, transform the case to all-caps.
	# TODO: Turn this into a Pandoc filter.
	sed -i.bak '0,/\\tableofcontents/s/^# \(.*\)/\\section*\{\U\1\}/g' "${input}"
}

# latexdiff is pretty great, but it has some incompatibilities with our template, so we
# unfortunately have to do a lot of massaging of the diff .tex file here.
# In the future, we should explore whether latexdiff can be further configured, our
# our custom extensions can be redesigned to avoid some of these problems.
do_diff_tex_fixups() {
	local input=$1
	# latexdiff is appending its own generated preamble to our custom one
	# (in apparent contradiction of the documentation). Strip it out.
	sed -i.bak '/^% End Custom TCG/,/^%DIF END PREAMBLE EXTENSION/d' "${input}"

	# latexdiff uses %DIF < and %DIF > to prefix changed lines in code environments
	# prefix these lines with + and - and replace %DIF with DIFDIFDIFDIF (inside DIFverbatim) so that
	# we don't delete the verbatim diff markers when we delete comments below.
	sed -i.bak '/\\begin{DIFverbatim}/,/\\end{DIFverbatim}/s/^%DIF < /DIFDIFDIFDIF <- /g' "${input}"
	sed -i.bak '/\\begin{DIFverbatim}/,/\\end{DIFverbatim}/s/^%DIF > /DIFDIFDIFDIF >+ /g' "${input}"

	# Remove all block begin and end markers after the beginning of the document. See latexdiff.tex for some discussion on this.
	# TL;DR: the begin and end markers get put into tricky places, and we don't need to do anything inside those commands.
	sed -i.bak '/^\\begin{document}/,$s/\\DIF\(add\|del\|mod\)\(begin\|end\)\(FL\|\) //g ' "${input}"

	# latexdiff erroneously puts \DIFadd inside the second argument to \multicolumn.
	# Move it out.
	sed -i.bak 's/\\multicolumn{\([^{}]*\)}{\\DIFadd{\([^{}]*\|[^{}]*{[^{}]*}\)}}/\\multicolumn{\1}{\2}/g' "${input}"

	# Delete all lines containing only comments.
	sed -i.bak '/^\s*%.*$/d' "${input}"

	# Strip comments (everything after unescaped percent signs) inside of xltabular to make the below steps easier.
	sed -i.bak '/\\begin{xltabular}/,/\\end{xltabular}/s/\([^\\]\)%.*$/\1/g' "${input}"
	sed -i.bak 's/^%.*$//g' "${input}"

	# Combine lines inside of the xltabular environment so that (non-empty) lines all end in \\ or \\*
	perl -ne 's/\n/ / if $s = /\\begin{xltabular}/ .. ($e = /\\end{xltabular}/)
                                    and $s > 1 and !$e and !/.*\\\\$/ and !/.*\\\\\*$/;
                  print' < "${input}" > "${input}".bak && mv "${input}".bak "${input}"

	# Put newlines after \endhead, \endfirsthead, \endfoot, and \endlastfoot
	sed -i.bak 's/\(\\end\(head\|firsthead\|foot\|lastfoot\)\)/\1\n/g' "${input}"

	# latexdiff inserts its markers before \multicolumn sometimes.
	# The \multicolumn needs to be the first thing in the cell.
	# Swap the order of any \DIF stuff and \multicolumn invocation inside a cell.
	sed -i.bak 's/\(\\DIF[^&]*\)\(\\multicolumn{[^{}]*}\({[^{}]*}\|{[^{}]*{[^{}]*}}\)\)/\2\1/g' "${input}"
	
	# latexdiff inserts its markers before \hline sometimes.
	# After the transformations above, \hline needs to be the first thing in a line of text.
	sed -i.bak 's/\(\s*\)\(.*\)\(\\hline \|\\hlineifmdframed \)\(.*\)/\1\3\2\4/g' "${input}"

	# latexdiff inside of \texttt breaks. Prefer \ttfamily.
	sed -i.bak 's/\\texttt{/{\\ttfamily /g' "${input}"

	# Delete all empty DIFadd/mod/del
	sed -i.bak 's/\\DIF\(add\|del\|mod\){}\(FL\|\)//g' "${input}"

}

if test "${DO_GITVERSION}" == "yes"; then
	# If using the git information for versioning, grab the date from there
	DATE="$(git show -s --date=format:'%Y/%m/%d' --format=%ad)"
else
	# Else, grab the date from the front matter and generate the full date and year.
	DATE="$(grep date: "${INPUT_FILE}" | head -n 1 | cut -d ' ' -f 2)"
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

# Greps the latex logs to surface relevant errors and warnings.
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

# Takes Markdown input and writes LaTeX output using pandoc.
do_latex() {
	local input=$1
	local output=$2
	local extra_pandoc_options=$3
	mkdir -p "$(dirname ${output})"

	# TODO: https://github.com/TrustedComputingGroup/pandoc/issues/164
	# highlighting breaks diffing due to the \xxxxTok commands generated during highlighting being fragile.
	# Citations: https://pandoc.org/MANUAL.html#other-relevant-metadata-fields
	echo "Generating LaTeX Output"
	local start=$(date +%s)
	local cmd=(pandoc
		--standalone
		--no-highlight
		--template=tcg.tex
		--lua-filter=mermaid-filter.lua
		--lua-filter=informative-sections.lua
		--lua-filter=convert-images.lua
		--lua-filter=center-images.lua
		--lua-filter=parse-html.lua
		--lua-filter=apply-classes-to-tables.lua
		--lua-filter=landscape-pages.lua
		--lua-filter=style-fenced-divs.lua
		--filter=pandoc-crossref
		--citeproc
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
		--metadata=link-citations
		--metadata=link-bibliography
		--metadata=titlepage-background:/resources/img/cover.png
		--metadata=crossrefYaml:/resources/filters/pandoc-crossref.yaml
		--metadata=logo:/resources/img/tcg.png
		--metadata=titlepage-rule-height:0
		--metadata=colorlinks:true
		--metadata=contact:admin@trustedcomputinggroup.org
		--from=${FROM}
		${extra_pandoc_options}
		--to=latex
		--output="'${output}'"
		"'${input}'")
	retry 5 "${cmd[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "LaTeX/PDF output failed"
	fi
	local end=$(date +%s)
	echo "Elapsed time: $(($end-$start)) seconds"
}

# Takes LaTeX input and writes PDF output and logs using the PDF engine of choice.
do_pdf() {
	local input=$1
	local output=$2
	mkdir -p "$(dirname ${output})"

	local logfile=$3
	# LaTeX engines choose this filename based on TEMP_TEX_FILE's basename. It also emits a bunch of other files.
	local temp_pdf_file="$(basename ${input%.*}).pdf"

	echo "Rendering PDF"
	local start=$(date +%s)
	# latexmk takes care of repeatedly calling the PDF engine. A run may take multiple passes due to the need to
	# update .toc and other files.
	latexmk "${input}" -pdflatex="${PDF_ENGINE}" -pdf -diagnostics > "${logfile}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "PDF output failed"
	fi
	local end=$(date +%s)
	# Write any LaTeX errors to stderr.
	>&2 grep -A 5 "] ! " "${logfile}"

	# Copy aux, lof, lot, toc, upa, and upb files (if any) back to the source directory so they can be cached and speed up future runs.
	cp *.aux "${SOURCE_DIR}" 2>/dev/null
	cp *.lof "${SOURCE_DIR}" 2>/dev/null
	cp *.lot "${SOURCE_DIR}" 2>/dev/null
	cp *.toc "${SOURCE_DIR}" 2>/dev/null
	cp *.upa "${SOURCE_DIR}" 2>/dev/null
	cp *.upb "${SOURCE_DIR}" 2>/dev/null
	# Copy converted images so they can be cached as well.
	cp *.convert.pdf "${SOURCE_DIR}" 2>/dev/null
	cp *.mermaid.pdf "${SOURCE_DIR}" 2>/dev/null
	echo "Elapsed time: $(($end-$start)) seconds"
	# Write any LaTeX errors to stderr.
	>&2 grep -A 5 "! " "${logfile}"
	if [[ ! "${FAILED}" = "true" ]]; then
		mv "${temp_pdf_file}" "${output}"
		analyze_latex_logs "${logfile}"
	fi
}

# Takes Markdown input and writes Docx output using pandoc.
do_docx() {
	local input=$1
	local output=$2
	mkdir -p "$(dirname ${output})"
	# Prepare the title-page for the docx version.
	local subtitle="Version ${GIT_VERSION:-${DATE}}, Revision ${GIT_REVISION:-0}"
	# Prefix the document with a Word page-break, since Pandoc doesn't do docx
	# title pages.
	cat <<- 'EOF' > "${input}.prefixed"
	```{=openxml}
	<w:p>
		<w:r>
			<w:br w:type="page"/>
		</w:r>
	</w:p>
	```
	EOF
	cat "${BUILD_DIR}/${INPUT_FILE}" >> "${input}.prefixed"

	echo "Generating DOCX Output"
	cmd=(pandoc
		--embed-resources
		--standalone
		--lua-filter=mermaid-filter.lua
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
		${EXTRA_PANDOC_OPTIONS}
		--to=docx
		--output="'${output}'"
		"'${input}.prefixed'")
	retry 5 "${cmd[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "DOCX output failed"
	else
		echo "DOCX output generated to file: ${output}"
	fi
}

# Takes Markdown input and writes HTML output using pandoc.
do_html() {
	local input=$1
	local output=$2
	mkdir -p "$(dirname ${output})"
	echo "Generating HTML Output"
	local cmd=(pandoc
		--toc
		-V colorlinks=true
		-V linkcolor=blue
		-V urlcolor=blue
		-V toccolor=blue
		--embed-resources
		--standalone
		--lua-filter=mermaid-filter.lua
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
		${EXTRA_PANDOC_OPTIONS}
		--to=html
		--output="'${output}'"
		"'${input}'")
	retry 5 "${cmd[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "HTML output failed"
	else
		echo "HTML output generated to file: ${output}"
	fi
}

# Generate .tex output if either latex or pdf formats were requested, because
# the .tex is an intermediate requirement to the pdf.
readonly TEMP_TEX_FILE="${BUILD_DIR}/${INPUT_FILE}.tex"
if [ -n "${PDF_OUTPUT}" -o -n "${LATEX_OUTPUT}" -o -n "${DIFFPDF_OUTPUT}" -o -n "${DIFFTEX_OUTPUT}" ]; then
	do_md_fixups "${BUILD_DIR}/${INPUT_FILE}"
	do_latex "${BUILD_DIR}/${INPUT_FILE}" "${TEMP_TEX_FILE}" "${EXTRA_PANDOC_OPTIONS}"
fi
if [ -n "${LATEX_OUTPUT}" ]; then
	cp "${TEMP_TEX_FILE}" "${SOURCE_DIR}/${LATEX_OUTPUT}"
fi

# Generate the PDF output
readonly LATEX_LOG="${BUILD_DIR}/latex.log"
if [ -n "${PDF_OUTPUT}" ]; then
	do_pdf "${TEMP_TEX_FILE}" "${SOURCE_DIR}/${PDF_OUTPUT}" "${LATEX_LOG}"

	# Copy the logs, if requested.
	if [ -n "${PDFLOG_OUTPUT}" ]; then
		mkdir -p "$(dirname ${SOURCE_DIR}/${PDFLOG_OUTPUT})"
		cp "${LATEX_LOG}" "${SOURCE_DIR}/${PDFLOG_OUTPUT}"
	fi
fi	

# Generate the docx output
if [ -n "${DOCX_OUTPUT}" ]; then
	do_docx "${BUILD_DIR}/${INPUT_FILE}" "${SOURCE_DIR}/${DOCX_OUTPUT}"
fi

# Diffs may fail in some circumstances. Do not fail the entire workflow here.
PRE_DIFFING_FAILED="${FAILED}"

# Generate the diff output
# Do this last so we can do whatever we want to the build directory
readonly TEMP_DIFFBASE_TEX_FILE="${BUILD_DIR}/${INPUT_FILE}.diffbase.tex"
readonly TEMP_DIFF_TEX_FILE="${BUILD_DIR}/${INPUT_FILE}.diff.tex"
readonly TEMP_LATEXDIFF_LOG="${BUILD_DIR}/latexdiff.log"
if [ -n "${DIFFPDF_OUTPUT}" -o -n "${DIFFTEX_OUTPUT}" ]; then
	git fetch --unshallow --quiet 2>/dev/null
	git reset --hard ${DIFFBASE}
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "diff output failed"
	else
		do_md_fixups "${BUILD_DIR}/${INPUT_FILE}"
		do_latex "${BUILD_DIR}/${INPUT_FILE}" "${TEMP_DIFFBASE_TEX_FILE}" "${EXTRA_PANDOC_OPTIONS} -V keepstaleimages=true"
		echo "Running latexdiff... (this may take a while for complex changes)"
		start=$(date +%s)
		latexdiff-fast --math-markup=whole --preamble /resources/templates/latexdiff.tex --config /resources/templates/latexdiff.cfg --append-safecmd /resources/templates/latexdiff.safe --exclude-safecmd /resources/templates/latexdiff.unsafe "${TEMP_DIFFBASE_TEX_FILE}" "${TEMP_TEX_FILE}" > "${TEMP_DIFF_TEX_FILE}" 2>"${TEMP_LATEXDIFF_LOG}"
		end=$(date +%s)
		echo "Elapsed time: $(($end-$start)) seconds"
		if [ $? -ne 0 ]; then
			FAILED=true
			>&2 cat "${TEMP_LATEXDIFF_LOG}"
			echo "latexdiff failed"
		else
			do_diff_tex_fixups "${TEMP_DIFF_TEX_FILE}"
			if [ -n "${DIFFTEX_OUTPUT}" ]; then
				mkdir -p "$(dirname ${SOURCE_DIR}/${DIFFTEX_OUTPUT})"
				cp "${TEMP_DIFF_TEX_FILE}" "${SOURCE_DIR}/${DIFFTEX_OUTPUT}"
			fi
		fi
	fi
fi
if [ "${FAILED}" != "true" -a -n "${DIFFPDF_OUTPUT}" ]; then
	echo "Rendering diff PDF..."
	do_pdf "${TEMP_DIFF_TEX_FILE}" "${SOURCE_DIR}/${DIFFPDF_OUTPUT}" "${LATEX_LOG}"

	# Copy the logs, if requested. Note that this file gets the latexdiff and PDF driver output.
	if [ -n "${DIFFPDFLOG_OUTPUT}" ]; then
		mkdir -p "$(dirname ${SOURCE_DIR}/${DIFFPDFLOG_OUTPUT})"
		echo "latexdiff output:" > "${SOURCE_DIR}/${DIFFPDFLOG_OUTPUT}"
		cat "${TEMP_LATEXDIFF_LOG}" >> "${SOURCE_DIR}/${DIFFPDFLOG_OUTPUT}"
		echo "" >> "${SOURCE_DIR}/${DIFFPDFLOG_OUTPUT}"
		echo "${PDF_ENGINE} output:" >> "${SOURCE_DIR}/${DIFFPDFLOG_OUTPUT}"
		cat "${LATEX_LOG}" >> "${SOURCE_DIR}/${DIFFPDFLOG_OUTPUT}"
	fi
fi

if [ "${PRE_DIFFING_FAILED}" == "true" ]; then
	echo "Overall workflow failed"
	exit 1
fi

echo "Overall workflow succeeded"
exit 0
