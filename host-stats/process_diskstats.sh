#!/bin/sh
#
# $Id: devstat_linux26.sh 19 2010-01-05 14:43:43Z to.my.trociny $
#

#file with statistics

DISKSTATS=

#
# From Documentation/iostats.txt:
#
# Field  1 -- # of reads completed
#     This is the total number of reads completed successfully.
# Field  2 -- # of reads merged, field 6 -- # of writes merged
#     Reads and writes which are adjacent to each other may be merged for
#     efficiency.  Thus two 4K reads may become one 8K read before it is
#     ultimately handed to the disk, and so it will be counted (and queued)
#     as only one I/O.  This field lets you know how often this was done.
# Field  3 -- # of sectors read
#     This is the total number of sectors read successfully.
# Field  4 -- # of milliseconds spent reading
#     This is the total number of milliseconds spent by all reads (as
#     measured from __make_request() to end_that_request_last()).
# Field  5 -- # of writes completed
#     This is the total number of writes completed successfully.
# Field  7 -- # of sectors written
#     This is the total number of sectors written successfully.
# Field  8 -- # of milliseconds spent writing
#     This is the total number of milliseconds spent by all writes (as
#     measured from __make_request() to end_that_request_last()).
# Field  9 -- # of I/Os currently in progress
#     The only field that should go to zero. Incremented as requests are
#     given to appropriate struct request_queue and decremented as they finish.
# Field 10 -- # of milliseconds spent doing I/Os
#     This field is increases so long as field 9 is nonzero.
# Field 11 -- weighted # of milliseconds spent doing I/Os
#     This field is incremented at each I/O start, I/O completion, I/O
#     merge, or read of these stats by the number of I/Os in progress
#     (field 9) times the number of milliseconds spent doing I/O since the
#     last update of this field.  This can provide an easy measure of both
#     I/O completion time and the backlog that may be accumulating.

PROGNAME=`basename $0`
FILTER=cat
DEVICE=

#
# Functions
#

usage()
{
    echo
    echo "usage: $PROGNAME [options] <device>"
    echo
    echo "Options:"
    echo
    echo "  -h           print this help and exit"
    echo "  -f <file>    path to diskstats file (default is stdout)"
    echo "  -p <filter>  filter diskstats file using this programm (e.g. to unzip)"
    echo
}

#
# Main
#

while getopts "hf:p:" opt; do

    case "$opt" in

	h)
	    usage
	    exit 0
	    ;;
	f)
	    DISKSTATS=$OPTARG
	    ;;
	p)
	    FILTER=$OPTARG
	    ;;
	\?)
	    usage >&2
	    exit 1
	    ;;
    esac
done

shift $((OPTIND - 1))

if [ -z "$1" ]; then
    usage >&2
    exit 1
fi

DEVICE="$1"

if [ -n "$DISKSTATS" ] && ! [ -f "$DISKSTATS" -a -r "$DISKSTATS" ]; then
    echo "Can't access diskstats file '$DISKSTATS'" >&2
    exit 1
fi

eval "$FILTER" "$DISKSTATS" |
awk 'BEGIN {
         print "#day\ttime\t%timestamp\tDEV\treads/sec_completed\treads/sec_merged\tsectors/sec_read\tr_serv_msec" \
               "\twrites/sec_completed\twrites/sec_merged\tsectors/sec_written\tw_serv_msec" \
               "\tio_in_progress\t%_io\t%_io_weighted"
     }
     !/^#/ && $(3 + 3) == "'"$DEVICE"'" && t_prev {
         delta = $3 - t_prev;
         printf "%s\t%s\t%d\t%s\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%f\t%d\t%d\t%d\n", \
             $1, $2, $3, $(3 + 3) "[" $(3 + 1) "/" $(3 + 2) "]", \
             1.0 * ($(3 + 4) - reads_completed_prev) / delta, \
             1.0 * ($(3 + 5) - reads_merged_prev) / delta, \
             1.0 * ($(3 + 6) - sectors_read_prev) / delta, \
             (($(3 + 4) - reads_completed_prev) > 0 ? ($(3 + 7) - msec_reading_prev) / ($(3 + 4) - reads_completed_prev) : "+nan"), \
             1.0 * ($(3 + 8) - writes_completed_prev) / delta, \
             1.0 * ($(3 + 9) - writes_merged_prev) / delta, \
             1.0 * ($(3 + 10) - sectors_written_prev) / delta, \
             (($(3 + 8) - writes_completed_prev) > 0 ? ($(3 + 11) - msec_writing_prev) / ($(3 + 8) - writes_completed_prev) : "+nan"), \
             $(3 + 12), \
             100 * ($(3 + 13) - msec_io_prev) / (1000 * delta), \
             100 * ($(3 + 14) - msec_io_weighted_prev) / (1000 * delta)
     }
     !/^#/ && $(3 + 3) == "'"$DEVICE"'" {
             t_prev = $3
             reads_completed_prev = $(3 + 4)
             reads_merged_prev = $(3 + 5)
             sectors_read_prev = $(3 + 6)
             msec_reading_prev = $(3 + 7)
             writes_completed_prev = $(3 + 8)
             writes_merged_prev = $(3 + 9)
             sectors_written_prev = $(3 + 10)
             msec_writing_prev = $(3 + 11)
             msec_io_prev = $(3 + 13)
             msec_io_weighted_prev = $(3 + 14)
     }'
