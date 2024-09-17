#!/bin/bash

# Safer execution
# -e: exit immediately if a command fails
# -E: Safer -e option for traps
# -u: fail if a variable is used unset
# -o pipefail: exit immediately if command in a pipe fails
#set -eEuo pipefail
# -x: print each command before executing (great for debugging)
#set -x

# Convenient values
SCRIPT_NAME=$(basename $BASH_SOURCE)

# Default program values
TEST_CASE="all"

#
# Logging helpers
#
log() {
    echo -e "${*}"
}
info() {
    log "Info: ${*}"
}
warning() {
    log "Warning: ${*}"
}
error() {
    log "Error: ${*}"
}
die() {
    error "${*}"
    exit 1
}

#
# Line comparison
#
select_line() {
    # 1: string
    # 2: line to select
    echo "$(echo "${1}" | sed "${2}q;d")"
}

fail() {
    # 1: got
    # 2: expected
    log "Fail: got '${1}' but expected '${2}'"
}

pass() {
    # got
    log "Pass: ${1}"
}

compare_lines() {
    # 1: output
    # 2: expected
    # 3: score (output)
    declare -a output_lines=("${!1}")
    declare -a expect_lines=("${!2}")
    local __score=$3
    local partial="0"

    # Amount of partial credit for each correct output line
    local step=$(bc -l <<< "1.0 / ${#expect_lines[@]}")

    # Compare lines, two by two
    for i in ${!output_lines[*]}; do
        if [[ "${output_lines[${i}]}" == "${expect_lines[${i}]}" ]]; then
            pass "${output_lines[${i}]}"
            partial=$(bc <<< "${partial} + ${step}")
        else
            fail "${output_lines[${i}]}" "${expect_lines[${i}]}" ]]
        fi
    done

    # Return final score
    eval ${__score}="'${partial}'"
}

#
# Run generic test case
#
run_test_case() {
	#1: number of processes
	local nproc="${1}"
	shift
	#2: Executable
    local exec="${1}"
	shift
    #3+: cli arguments
    local args=("${@}")

    [[ -x "$(command -v ${exec})" ]] || \
        die "Cannot find executable '${exec}'"

    # These are global variables after the test has run so clear them out now
    unset STDOUT STDERR RET

    # Create temp files for getting stdout and stderr
    local outfile=$(mktemp)
    local errfile=$(mktemp)

    if (( ${nproc} > 1 )); then
        mpirun --use-hwthread-cpus --allow-run-as-root -n ${nproc} \
            ${exec} ${args[*]} >${outfile} 2>${errfile}
    else
        ${exec} ${args[*]} >${outfile} 2>${errfile}
    fi

    # Get the return status, stdout and stderr of the test case
    RET="${?}"
    STDOUT=$(cat "${outfile}")
    STDERR=$(cat "${errfile}")

    # Clean up temp files
    rm -f "${outfile}"
    rm -f "${errfile}"
}

run_time() {
    #1: num repetitions
    local reps="${1}"
    shift
	#2: number of processes
	local nproc="${1}"
	shift
	#3: Executable
    local exec="${1}"
	shift
    #4+: cli arguments
    local args=("${@}")

    [[ -x ${exec} ]] || \
        die "Cannot find executable '${exec}'"

    # These are global variables after the test has run so clear them out now
    unset PERF

    for i in $(seq ${reps}); do
        # Create temp files for getting stdout and stderr
        local outfile=$(mktemp)
        local errfile=$(mktemp)

        if (( ${nproc} > 1 )); then
            TIME="%e" /usr/bin/time \
                mpirun  --use-hwthread-cpus --allow-run-as-root -n ${nproc} \
                ${exec} ${args[*]} >${outfile} 2>${errfile}
        else
            TIME="%e" /usr/bin/time \
                ${exec} ${args[*]} >${outfile} 2>${errfile}
        fi

        # Last line of stderr
        local t=$(cat "${errfile}" | tail -n1)

        # Check it's the right format
        if [[ ! "${t}" =~ ^[0-9]{1,3}\.[0-9]{2}$ ]]; then
            die "Wrong timing output '${t}'"
        fi

        # Keep the best timing
        if [ -z "${PERF}" ]; then
            PERF=${t}
        elif (( $(bc <<<"${t} < ${PERF}") )); then
            PERF=${t}
        fi

        # Clean up temp files
        rm -f "${outfile}"
        rm -f "${errfile}"
    done
}

#
# Test cases
#
TEST_CASES=()

#
# Correctness
#
mandelbrot_serial_correct() {

    local arg_size=(512     1024    2048    4096)
    local arg_xcen=(-0.722  -0.722  -0.722  -0.722)
    local arg_ycen=(0.246   0.246   0.246   0.246)
    local arg_zoom=(12.000  14.800  15.000  15.420)
    local arg_cutf=(127     255     255     255)

    local line_array=()
    local corr_array=()
    for i in $(seq 0 3); do
        run_test_case 1 ./mandelbrot_serial "${arg_size[${i}]}" "${arg_xcen[${i}]}" \
            "${arg_ycen[${i}]}" "${arg_zoom[${i}]}" "${arg_cutf[${i}]}"

        run_test_case 1 compare -fuzz 1% -metric AE \
            "mandel_${arg_size[${i}]}_${arg_xcen[${i}]}_${arg_ycen[${i}]}_${arg_zoom[${i}]}_${arg_cutf[${i}]}_ref.pgm" \
            "mandel_${arg_size[${i}]}_${arg_xcen[${i}]}_${arg_ycen[${i}]}_${arg_zoom[${i}]}_${arg_cutf[${i}]}.pgm" \
            diff.pgm

        line_array+=("$(select_line "${STDERR}" "1")")
        corr_array+=("0")

        rm -f "mandel_${arg_size[${i}]}_${arg_xcen[${i}]}_${arg_ycen[${i}]}_${arg_zoom[${i}]}_${arg_cutf[${i}]}.pgm" diff.pgm
    done

    local score
    compare_lines line_array[@] corr_array[@] score
    log "${score}"
}
TEST_CASES+=("mandelbrot_serial_correct")

mandelbrot_mpi_correct() {

    local arg_size=(512     1024    2048    4096)
    local arg_xcen=(-0.722  -0.722  -0.722  -0.722)
    local arg_ycen=(0.246   0.246   0.246   0.246)
    local arg_zoom=(12.000  14.800  15.000  15.420)
    local arg_cutf=(127     255     255     255)

    local line_array=()
    local corr_array=()
    for i in $(seq 0 3); do
        run_test_case 8 ./mandelbrot_mpi "${arg_size[${i}]}" "${arg_xcen[${i}]}" \
            "${arg_ycen[${i}]}" "${arg_zoom[${i}]}" "${arg_cutf[${i}]}"

        run_test_case 1 compare -fuzz 1% -metric AE \
            "mandel_${arg_size[${i}]}_${arg_xcen[${i}]}_${arg_ycen[${i}]}_${arg_zoom[${i}]}_${arg_cutf[${i}]}_ref.pgm" \
            "mandel_${arg_size[${i}]}_${arg_xcen[${i}]}_${arg_ycen[${i}]}_${arg_zoom[${i}]}_${arg_cutf[${i}]}.pgm" \
            diff.pgm

        line_array+=("$(select_line "${STDERR}" "1")")
        corr_array+=("0")

        rm -f "mandel_${arg_size[${i}]}_${arg_xcen[${i}]}_${arg_ycen[${i}]}_${arg_zoom[${i}]}_${arg_cutf[${i}]}.pgm" diff.pgm
    done

    local score
    compare_lines line_array[@] corr_array[@] score
    log "${score}"
}
TEST_CASES+=("mandelbrot_mpi_correct")

#
# Speed
#
NREPS=2
mandelbrot_serial_speed()
{
    run_time ${NREPS} 1 ./ref_mandelbrot_serial 1024 -0.722 0.246 15.420 255
    local ref_perf=${PERF}

    rm -f "mandel_1024_-0.722_0.246_15.420_255.pgm"

    run_time ${NREPS} 1 ./mandelbrot_serial 1024 -0.722 0.246 15.420 255
    local tst_perf=${PERF}

    rm -f "mandel_1024_-0.722_0.246_15.420_255.pgm"

    local ratio=$(bc -l <<<"${tst_perf} / ${ref_perf}")
    log "${ratio}"
}
TEST_CASES+=("mandelbrot_serial_speed")

mandelbrot_mpi_speed()
{
    run_time ${NREPS} 8 ./ref_mandelbrot_mpi 2048 -0.722 0.246 15.420 255
    local ref_perf=${PERF}

    rm -f "mandel_2048_-0.722_0.246_15.420_255.pgm"

    run_time ${NREPS} 8 ./mandelbrot_mpi 2048 -0.722 0.246 15.420 255
    local tst_perf=${PERF}

    rm -f "mandel_2048_-0.722_0.246_15.420_255.pgm"

    local ratio=$(bc -l <<<"${tst_perf} / ${ref_perf}")
    log "${ratio}"
}
TEST_CASES+=("mandelbrot_mpi_speed")

#
# Main functions
#
parse_argvs() {
    local OPTIND opt

    while getopts "h?s:t:" opt; do
        case "$opt" in
            h|\?)
                echo "${SCRIPT_NAME}: [-t <test_case>]" 1>&2
                exit 0
                ;;
            t)  TEST_CASE="${OPTARG}"
                ;;
        esac
    done
}

check_vals() {
    # Check test case
    [[ " ${TEST_CASES[@]} all " =~ " ${TEST_CASE} " ]] || \
        die "Cannot find test case '${TEST_CASE}'"
    }

grade() {
    # Run test case(s)
    if [[ "${TEST_CASE}" == "all" ]]; then
        # Run all test cases
        for t in "${TEST_CASES[@]}"; do
            log "--- Running test case: ${t} ---"
            ${t}
            log "\n"
        done
    else
        # Run specific test case
        ${TEST_CASE}
    fi
}

parse_argvs "$@"
check_vals
grade
