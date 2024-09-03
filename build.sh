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
versioned_filenames="no"
pr_number=""
pr_repo=""
DIFFBASE=""

# Start up the dbus daemon (drawio will use it later)
dbus-daemon --system || echo "Failed to start dbus daemon"

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
	echo "  --diff=commit: create diff documents against the provided commit"
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
	echo "  --versioned_filenames: insert version information before the file extension for outputs"
	echo "  --pr_number=number: mark the document as a pull-request draft if using Git versioning."
	echo "  --pr_repo=url: provide the URL for the repository for pull-request drafts (has no effect if --pr_number is not passed)."
}


if ! options=$(getopt --longoptions=help,puppeteer,notmp,gitversion,gitstatus,nogitversion,table_rules,plain_quotes,noplain_quotes,versioned_filenames,pr_number:,pr_repo:,diff:,pdf:,latex:,pdflog:,docx:,html:,resourcedir: --options="" -- "$@"); then
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
	--versioned_filenames)
		versioned_filenames="yes"
		shift
		;;
	--pr_number)
		pr_number="${2}"
		shift 2
		;;
	--pr_repo)
		pr_repo="${2}"
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

	if [ ! -z "${pr_number}" ]; then
		# In the case of a PR, always just provide the PR number and commit
		extra_pandoc_options+=" --metadata=pr_number:${pr_number}"
		extra_pandoc_options+=" --metadata=revision:${GIT_COMMIT}"
		status="Pull Request"
		if [ ! -z "${pr_repo}" ]; then
			extra_pandoc_options+=" --metadata=pr_repo_url:https://github.com/${pr_repo}"
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
		if [ "${do_gitstatus}" == "yes" ]; then
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
	local PREFIX=$1
	local FULL_FILENAME=$2
	local DIRNAME=$(dirname "${FULL_FILENAME}")
	local FILENAME=$(basename "${FULL_FILENAME}")
	local EXTENSION="${FILENAME##*.}"
	local STRIPPED="${FILENAME%.*}"
	local RESULT=""
	if [ ! -z "${DIRNAME}" ]; then
		RESULT="${DIRNAME}/"
	fi
	RESULT="${RESULT}${STRIPPED}${PREFIX}.${EXTENSION}"
	echo "${RESULT}"
}

# Rename output files based on version info
if [ "${versioned_filenames}" == "yes" ]; then
	if [ ! -z "${pr_number}" ]; then
		version_prefix=".pr${pr_number}.${GIT_COMMIT}"
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

	if [ ! -z "${docx_output}" ]; then
		docx_output=$(prefix_filename "${version_prefix}" "${docx_output}")
	fi
	if [ ! -z "${pdf_output}" ]; then
		pdf_output=$(prefix_filename "${version_prefix}" "${pdf_output}")
	fi
	if [ ! -z "${latex_output}" ]; then
		latex_output=$(prefix_filename "${version_prefix}" "${latex_output}")
	fi
	if [ ! -z "${html_output}" ]; then
		html_output=$(prefix_filename "${version_prefix}" "${html_output}")
	fi
fi

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
if [ ! -z "${DIFFBASE}" ]; then
	echo "diff against: ${DIFFBASE}"
fi
if test "${do_gitversion}" == "yes"; then
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

if [ "${block_quotes_are_informative_text}" == "yes" ]; then
	extra_pandoc_options+=" --lua-filter=informative-quote-blocks.lua"
fi

mkdir -p "${build_dir}/$(dirname ${input_file})"
cp "${input_file}" "${build_dir}/${input_file}"

# Hacks
do_md_fixups() {
	FIXUP_INPUT=$1

	# \newpage is rendered as the string "\newpage" in GitHub markdown.
	# Transform horizontal rules into \newpages.
	# Exception: the YAML front matter of the document, so undo the instance on the first line.
	# TODO: Turn this into a Pandoc filter.
	sed -i.bak 's/^---$/\\newpage/g;1s/\\newpage/---/g' "${FIXUP_INPUT}"

	# Transform sections before the table of contents into section*, which does not number them.
	# While we're doing this, transform the case to all-caps.
	# TODO: Turn this into a Pandoc filter.
	sed -i.bak '0,/\\tableofcontents/s/^# \(.*\)/\\section*\{\U\1\}/g' "${FIXUP_INPUT}"
}

do_md_fixups "${build_dir}/${input_file}"

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

TEMP_TEX_FILE="${build_dir}/${input_file%.*}.tmp.tex"
TEMP_DIFFBASE_TEX_FILE="${build_dir}/${input_file%.*}_diffbase.tmp.tex"
TEMP_DIFF_TEX_FILE="${build_dir}/${input_file%.*}_diff.tmp.tex"

LATEX_LOG="${build_dir}/latex.log"
LATEXDIFF_LOG="${build_dir}/latexdiff.log"

analyze_latex_logs() {
	local LOGFILE=$1

	local RUNCOUNT=$(grep "Run number " "${LOGFILE}" | tail -n 1 | cut -d ' ' -f 3)
	local PASSES="passes"
	if [ "${RUNCOUNT}" -eq "1" ]; then
		PASSES="pass"
	fi
	echo "Completed PDF rendering after ${RUNCOUNT} ${PASSES}."

	# Print any warnings from only the last run.
	local WARNINGS=$(sed -n "/Run number ${RUNCOUNT}/,$ p" "${LOGFILE}" | grep "LaTeX Warning: ")
	if [ ! -z "${WARNINGS}" ]; then
		echo "LaTeX warnings (may be ignorable - check the output!):"
		echo "${WARNINGS}"
	fi
}

do_latex() {
	start=$(date +%s)
	input=$1
	output=$2
	CMD=(pandoc
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
		--output="'${output}'"
		"'${input}'")
	retry 5 "${CMD[@]}"
	if [ $? -ne 0 ]; then
		FAILED=true
		echo "LaTeX/PDF output failed"
	fi
	end=$(date +%s)
	echo "Elapsed time: $(($end-$start)) seconds"
}

do_pdf() {
	TEX_INPUT="$1"
	PDF_OUTPUT="$2"
	LOG_OUTPUT="$3"
	TEMP_PDF_OUTPUT="$(basename ${TEX_INPUT%.*}).pdf"

	echo "Rendering PDF of ${TEX_INPUT} to ${PDF_OUTPUT}"
		start=$(date +%s)
	# Runs twice to populate aux, lof, lot, toc, then update the page numbers due
		# to the impact of populating the lof, lot, toc.
	latexmk "${TEX_INPUT}" -pdflatex=xelatex -pdf -diagnostics > "${LOG_OUTPUT}"
		if [ $? -ne 0 ]; then
			FAILED=true
			echo "PDF output failed"
		fi
		end=$(date +%s)
		# Write any LaTeX errors to stderr.
	>&2 grep -A 5 "] ! " "${LOG_OUTPUT}"

	# Clean up after latexmk. Deliberately leave behind aux, lof, lot, and toc to speed up future runs.

	echo "Elapsed time: $(($end-$start)) seconds"
	# Write any LaTeX errors to stderr.
	>&2 grep -A 5 "! " "${LATEX_LOG}"
	if [[ ! "${FAILED}" = "true" ]]; then
		mv "${TEMP_PDF_OUTPUT}" "${PDF_OUTPUT}"
		analyze_latex_logs "${LATEX_LOG}"
	fi
	rm -f *.fls
	rm -f *.log
	rm -f "${LATEX_LOG}"
}

# For LaTeX and PDF output, we use Pandoc to compile to an intermediate .tex file
# That way, LaTeX errors on PDF output point to lines that match the .tex.
if [ -n "${pdf_output}" -o -n "${latex_output}" ]; then
	mkdir -p "$(dirname ${pdf_output})"
	echo "Generating LaTeX Output"
	do_latex "${build_dir}/${input_file}" "${TEMP_TEX_FILE}"

	if [ -n "${latex_output}" ]; then
		cp "${TEMP_TEX_FILE}" "${latex_output}"
	fi

	if [ -n "${pdf_output}" ]; then
		do_pdf "${TEMP_TEX_FILE}" "${pdf_output}" "${LATEX_LOG}"
		if [ -n "${pdflog_output}" ]; then
			cp "${LATEX_LOG}" "${pdflog_output}"
		fi
	fi	
fi

if [ -n "${DIFFBASE}" -a -n "${pdf_output}" ]; then
	echo "Generating PDF diff against ${DIFFBASE}..."
	githead=$(git symbolic-ref -q --short HEAD || git describe --tags --exact-match)
	# Check if we need to stash
	git diff-index --quiet HEAD --
	GIT_DIR_IS_CLEAN=$?
	if [ $GIT_DIR_IS_CLEAN -ne 0 ]; then
		git stash push -m pandoc_diff_stash
	fi
	git checkout "${DIFFBASE}"
	cp "${input_file}" "${build_dir}/${input_file}"
	do_md_fixups "${build_dir}/${input_file}"

	do_latex "${build_dir}/${input_file}" "${TEMP_DIFFBASE_TEX_FILE}"
	echo "latexdiffing"
	latexdiff --type CCHANGEBAR --driver xetex "${TEMP_DIFFBASE_TEX_FILE}" "${TEMP_TEX_FILE}" > "${TEMP_DIFF_TEX_FILE}" 2>"${LATEXDIFF_LOG}"
	diff_tex_output=$(prefix_filename _diff "${latex_output}")
	diff_output=$(prefix_filename _diff "${pdf_output}")
	do_pdf "${TEMP_DIFF_TEX_FILE}" "${diff_output}" "${LATEX_LOG}"

	if [ -n "${latex_output}" ]; then
		cp "${TEMP_DIFF_TEX_FILE}" "${diff_tex_output}"
	fi

	echo "Reverting repository state to ${githead}"
	git checkout ${githead}
	if [ $GIT_DIR_IS_CLEAN -ne 0 ]; then
		git stash apply stash^{/pandoc_diff_stash}
	fi
	cp "${input_file}" "${build_dir}/${input_file}"
	do_md_fixups "${build_dir}/${input_file}"

fi

# Generate the docx output
if [ -n "${docx_output}" ]; then
	# Prepare the title-page for the docx version.
	SUBTITLE="Version ${GIT_VERSION:-${DATE}}, Revision ${GIT_REVISION:-0}"
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
		--lua-filter=convert-images.lua
		--lua-filter=parse-html.lua
		--lua-filter=apply-classes-to-tables.lua
		--lua-filter=landscape-pages.lua
		--lua-filter=style-fenced-divs.lua
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
rm -f mermaid-filter.err .mermaid-config.json
rm -f .puppeteer.json
rm -f "${build_dir}/${input_file}.bak"

echo "Overall workflow succeeded"
exit 0
