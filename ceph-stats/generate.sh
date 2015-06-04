#!/bin/sh

#
# Globals
#

# Generate data for this date
: ${CEPHSTATS_DATE:=$(date '+%F')}

# Gnuplot command (set to empty to disable graphs)
: ${CEPHSTATS_GNUPLOT:=gnuplot}

# Location of ceph-stats scripts
: ${CEPHSTATS_BINDIR:=$(pwd)}

# Location of generated data
: ${CEPHSTATS_DATADIR:=$(pwd)/data}

# Location of generated plots
: ${CEPHSTATS_PLOTDIR:=$(pwd)/plot}

# Gnuplot command (set to empty to disable graphs)
: ${CEPHSTATS_DEBUG:=1}


# Ceph stats data to generate

CEPHSTATS_DATA_df="df 'stats total_avail' 'stats total_space' 'stats total_used'"
CEPHSTATS_DATA_monmap_election_epoch="status 'election_epoch'"
CEPHSTATS_DATA_osdmap_osds="status 'osdmap osdmap num_osds' 'osdmap osdmap num_up_osds' 'osdmap osdmap num_in_osds'"
CEPHSTATS_DATA_osdmap_remapped_pgs="status 'osdmap osdmap num_remapped_pgs'"
CEPHSTATS_DATA_pgmap_version="status 'pgmap version'"
CEPHSTATS_DATA_pgmap_data_bytes="status 'pgmap data_bytes'"
CEPHSTATS_DATA_pgmap_usage="status 'pgmap bytes_used' 'pgmap bytes_avail' 'pgmap bytes_total'"
CEPHSTATS_DATA_pgmap_bytes_sec="status 'pgmap read_bytes_sec' 'pgmap write_bytes_sec' 'pgmap recovering_bytes_per_sec'"
CEPHSTATS_DATA_pgmap_recovering="status 'pgmap recovering_objects_per_sec' 'pgmap recovering_keys_per_sec'"
CEPHSTATS_DATA_pgmap_op_per_sec="status 'pgmap op_per_sec'"
CEPHSTATS_DATA_pgmap_degraded_ratio="status 'pgmap degraded_ratio'"
CEPHSTATS_DATA_pgmap_degraded_objects="status 'pgmap degraded_objects'"
CEPHSTATS_DATA_pgmap_degraded_total="status 'pgmap degraded_total'"

for i in `seq 0 100`
do
    name=`${CEPHSTATS_BINDIR}/process.py -d "${CEPHSTATS_DATE}" df "pools ${i} name" |
          awk '$1 !~ /^#/ && $3 != "-" {print $3; exit}' |
          sed -s 's/[^[:alpha:]0-9]/_/g'`
    test -n "${name}" || continue
    eval "CEPHSTATS_DATA_df_${name}=\"df 'pools ${i} stats objects'\""
done

for i in `seq 0 100`
do
    ${CEPHSTATS_BINDIR}/process.py -d "${CEPHSTATS_DATE}" osdperf "osd_perf_infos ${i} id" |
        awk '$1 !~ /^#/ && $3 != "-" {exit 37}'
    test $? -ne 37 && continue
    eval "CEPHSTATS_DATA_osdperf_${i}=\"osdperf 'osd_perf_infos ${i} perf_stats apply_latency_ms' 'osd_perf_infos ${i} perf_stats commit_latency_ms'\""
done

#
# Functions
#

debug()
{
    test -n "${CEPHSTATS_DEBUG}" || return

    echo "DEBUG: $@" >&2
}

list_vars()
{
    local line var

    set |
    while read line
    do
        var="${line%%=*}"
        case "${var}" in
            "${line}"|*[!a-zA-Z0-9_]*)
		continue
		;;
            $1)
		echo ${var}
		;;
	esac
    done
}

generate_data()
{
    local cmd name var

    if ! mkdir -p "${CEPHSTATS_DATADIR}"
    then
	echo "Failed to create CEPHSTATS_DATADIR" >&2
	exit 1
    fi

    for var in $(list_vars 'CEPHSTATS_DATA_*')
    do
	name=${var##CEPHSTATS_DATA_}
	debug "Processing $name"
	(eval exec "${CEPHSTATS_BINDIR}/process.py" -d "${CEPHSTATS_DATE}" \
	    $(eval echo \$${var})
	) > "${CEPHSTATS_DATADIR}/${name}.${CEPHSTATS_DATE}.dat"
    done

}

generate_plots()
{
    local f

    if [ -z "${CEPHSTATS_GNUPLOT}" ]
    then
	return
    fi

    if ! mkdir -p "${CEPHSTATS_PLOTDIR}"
    then
	echo "Failed to create CEPHSTATS_PLOTDIR" >&2
	exit 1
    fi

    for f in "${CEPHSTATS_DATADIR}"/*."${CEPHSTATS_DATE}.dat"
    do
	debug "Plotting $name"
	(
	    echo "set term png size 800,600"
	    echo "set style data lp"
	    echo "set grid"
	    echo "set output '${CEPHSTATS_PLOTDIR}/$(basename $f .dat).png'"
	    echo "set timefmt '%Y-%m-%d %H:%M:%S'"
	    echo "set xdata time"
	    echo "set format x '%H:%M'"
	    echo "set xlabel 'time'"
	    echo "set ylabe '$(basename $f .${CEPHSTATS_DATE}.dat)'"
	    echo "set title '$(basename $f .${CEPHSTATS_DATE}.dat) ${CEPHSTATS_DATE}'"
	    echo -n "plot"
	    head -1 ${f} | sed -e 's/#"date" "time" "//; s/" "/\n/g; s/"//;' |
	    awk "{
                   if (NR > 1) printf \",\"
                   printf \" '%s' using 1:%d title '%s'\", \""${f}"\", NR + 2, \$0
                 }"
	    echo
	) | gnuplot
    done
}

main()
{
    make
    generate_data
    generate_plots
}

#
# Main
#

main
