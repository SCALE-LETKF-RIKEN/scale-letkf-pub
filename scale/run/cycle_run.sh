#!/bin/bash
#===============================================================================
#
#  Wrap cycle.sh in OFP/FUGAKU/Linux and run it.
#
#-------------------------------------------------------------------------------
#
#  Usage:
#    cycle_run.sh [..]
#
#===============================================================================

cd "$(dirname "$0")"
myname="$(basename "$0")"
job='cycle'

#===============================================================================
# Configuration

. config.main || exit $?
. config.${job} || exit $?

. src/func_datetime.sh || exit $?
. src/func_util.sh || exit $?

. src/func_common_static.sh || exit $?
. src/func_${job}_static.sh || exit $?

#-------------------------------------------------------------------------------

echo "[$(datetime_now)] Start $myname $@"

setting "$@" || exit $?


echo
print_setting || exit $?
echo

#===============================================================================
# Create and clean the temporary directory

echo "[$(datetime_now)] Create and clean the temporary directory"

#if [ -e "${TMP}" ]; then
#  echo "[Error] $0: \$TMP will be completely removed." >&2
#  echo "        \$TMP = '$TMP'" >&2
#  exit 1
#fi
safe_init_tmpdir $TMP || exit $?

#===============================================================================
# Determine the distibution schemes

echo "[$(datetime_now)] Determine the distibution schemes"

safe_init_tmpdir $NODEFILE_DIR || exit $?
#distribute_da_cycle - $NODEFILE_DIR || exit $? # TEST

#===============================================================================
# Determine the staging list

echo "[$(datetime_now)] Determine the staging list"

cat $SCRP_DIR/config.main | \
    sed -e "/\(^DIR=\| DIR=\)/c DIR=\"$DIR\"" \
    > $TMP/config.main

echo "SCRP_DIR=\"\$TMPROOT\"" >> $TMP/config.main
echo "RUN_LEVEL=4" >> $TMP/config.main

echo "PARENT_REF_TIME=$PARENT_REF_TIME" >> $TMP/config.main

safe_init_tmpdir $STAGING_DIR || exit $?
staging_list_static || exit $?
config_file_list $TMPS/config || exit $?

#-------------------------------------------------------------------------------
# Add shell scripts and node distribution files into the staging list

cp ${SCRP_DIR}/config.rc ${TMP}/
cp ${SCRP_DIR}/config.${job} ${TMP}/
cp ${SCRP_DIR}/src/${job}.sh ${TMP}/
cp -r ${SCRP_DIR}/src ${TMP}/

#===============================================================================
# Stage in

echo "[$(datetime_now)] Initialization (stage in)"

stage_in server || exit $?

#===============================================================================
# Creat a job script and submit a job

NPIN=`expr 255 / \( $PPN \) + 1`
jobscrp="$TMP/${job}_job.sh"

echo "[$(datetime_now)] Create a job script '$jobscrp'"

# OFP
if [ "$PRESET" = 'OFP' ]; then

  if [ "$RSCGRP" == "" ] ; then
    RSCGRP="regular-cache"
  fi

cat > $jobscrp << EOF
#!/bin/sh
#PJM -L rscgrp=${RSCGRP}
#PJM -L node=${NNODES}
#PJM -L elapse=${TIME_LIMIT}
#PJM --mpi proc=$((NNODES*PPN))
##PJM --mpi proc=${totalnp}
#PJM --omp thread=${THREADS}

#PJM -g $(echo $(id -ng))
# HPC
##PJM -g gx14  

#PJM -s

module unload impi
module unload intel
module load intel/2019.5.281

source /work/opt/local/cores/intel/performance_snapshots_2019.6.0.602217/apsvars.sh
export MPS_STAT_LEVEL=4

module load hdf5/1.10.5
module load netcdf/4.7.0
module load netcdf-fortran/4.4.5

export FORT_FMT_RECL=400

export HFI_NO_CPUAFFINITY=1
export I_MPI_PIN_PROCESSOR_EXCLUDE_LIST=0,1,68,69,136,137,204,205
export I_MPI_HBW_POLICY=hbw_preferred,,
export I_MPI_FABRICS_LIST=tmi
unset KMP_AFFINITY
#export KMP_AFFINITY=verbose
#export I_MPI_DEBUG=5

export OMP_NUM_THREADS=1
export I_MPI_PIN_DOMAIN=${NPIN}
export I_MPI_PERHOST=${PPN}
export KMP_HW_SUBSET=1t

export PSM2_CONNECT_WARN_INTERVAL=2400
export TMI_PSM2_CONNECT_TIMEOUT=2000


#export OMP_STACKSIZE=128m
ulimit -s unlimited

./${job}.sh "$STIME" "$ETIME" "$MEMBERS" "$CYCLE" "$CYCLE_SKIP" "$IF_VERF" "$IF_EFSO" "$ISTEP" "$FSTEP" "$CONF_MODE" || exit \$?
EOF

  echo "[$(datetime_now)] Run ${job} job on PJM"
  echo

  job_submit_PJM $jobscrp
  echo

  job_end_check_PJM $jobid
  res=$?

# FUGAKU
elif [ "$PRESET" = 'FUGAKU' ]; then

  if [ "$RSCGRP" == "" ] ; then
    RSCGRP="small"
  fi
  TPROC=$((NNODES*PPN))

  VOLUMES="/"$(readlink /data/$(id -ng) | cut -d "/" -f 2)
  if [ $VOLUMES != "/vol0004" ] ;then
    VOLUMES="${VOLUMES}:/vol0004" # spack
  fi

cat > $jobscrp << EOF
#!/bin/sh 
#
#
#PJM -x PJM_LLIO_GFSCACHE=${VOLUMES}
#PJM -L "rscgrp=${RSCGRP}"
#PJM -L "node=$(((TPROC+PPN-1)/${PPN}))"
#PJM -L "elapse=${TIME_LIMIT}"
#PJM --mpi "max-proc-per-node=${PPN}"
#PJM -j
#PJM -s
#
#
export PARALLEL=${THREADS}
export OMP_NUM_THREADS=\${PARALLEL}
export FORT90L=-Wl,-T
export PLE_MPI_STD_EMPTYFILE=off
export OMP_WAIT_POLICY=active
export FLIB_BARRIER=HARD


EOF

  if (( USE_LLIO_BIN == 1 )); then
    for i in $(seq $nsteps) ; do
      echo "llio_transfer ${stepexecbin[$i]}" >> $jobscrp 
    done
    echo "" >> $jobscrp
  fi

  if (( USE_LLIO_DAT == 1 )); then
    echo "/home/system/tool/dir_transfer -l ./ ${TMPROOT}/dat" >> $jobscrp
    echo "" >> $jobscrp
  fi

  if (( USE_SPACK > 0 )); then

cat << EOF >>  $jobscrp 
SPACK_FJVER=${SPACK_FJVER}
. /vol0004/apps/oss/spack/share/spack/setup-env.sh
spack load netcdf-c%fj@\${SPACK_FJVER}
spack load netcdf-fortran%fj@\${SPACK_FJVER}
spack load parallel-netcdf%fj@\${SPACK_FJVER}

export LD_LIBRARY_PATH=/lib64:/usr/lib64:/opt/FJSVxtclanga/tcsds-latest/lib64:/opt/FJSVxtclanga/tcsds-latest/lib:\$LD_LIBRARY_PATH

EOF

  else

    if [ -z "$SCALE_NETCDF_C" ] || [ -z "$SCALE_NETCDF_F" ] || [ -z "$SCALE_PNETCDF" ] || [ -z "$SCALE_HDF" ] ; then
      echo "[Error] Export SCALE environmental parameters (e.g., SCALE_NETCDF_C)"
      exit 1
    fi

cat << EOF >>  $jobscrp 

export LD_LIBRARY_PATH=/lib64:/usr/lib64:/opt/FJSVxtclanga/tcsds-latest/lib64:/opt/FJSVxtclanga/tcsds-latest/lib:${SCALE_NETCDF_C}/lib:${SCALE_NETCDF_F}/lib:${SCALE_PNETCDF}/lib:${SCALE_HDF}/lib:\$LD_LIBRARY_PATH

EOF

  fi # USE_SPACK

cat << EOF >>  $jobscrp 
./${job}.sh "$STIME" "$ETIME" "$MEMBERS" "$CYCLE" "$CYCLE_SKIP" "$IF_VERF" "$IF_EFSO" "$ISTEP" "$FSTEP" "$CONF_MODE" || exit \$?

EOF

  if (( USE_LLIO_BIN == 1 )); then
    for i in $(seq $nsteps) ; do
      echo "llio_transfer --purge ${stepexecbin[$i]}" >> $jobscrp 
    done
    echo "" >> $jobscrp
  fi

  if (( USE_LLIO_DAT == 1 )); then
    echo "/home/system/tool/dir_transfer -p -l ./ ${TMPROOT}/dat" >> $jobscrp
    echo "" >> $jobscrp
  fi

  echo "[$(datetime_now)] Run ${job} job on PJM"
  echo
 

  job_submit_PJM $jobscrp
  echo
  
  job_end_check_PJM $jobid
  res=$?

# qsub
else

if [ $NNODES -lt 4 ] ; then
  RSCGRP=s
elif [ $NNODES -le 16 ] ; then
  RSCGRP=m
else
  echo "too many nodes required. " $NNODES " > 16"
  exit 1
fi

cat > $jobscrp << EOF
#!/bin/sh
#PBS -N $job
#PBS -q $RSCGRP
#PBS -l nodes=${NNODES}:ppn=${PPN}
#PBS -l walltime=${TIME_LIMIT}
#
#


cd \${PBS_O_WORKDIR}


export FORT_FMT_RECL=400
export GFORTRAN_UNBUFFERED_ALL=Y

source /etc/profile.d/modules.sh 
module unload mpt/2.12
module load intelmpi/5.1.2.150


export OMP_NUM_THREADS=${THREADS}
export KMP_AFFINITY=compact


ulimit -s unlimited

./${job}.sh "$STIME" "$ETIME" "$ISTEP" "$FSTEP" "$CONF_MODE" || exit \$?
EOF

  echo "[$(datetime_now)] Run ${job} job on PJM"
  echo
  
  job_submit_torque $jobscrp
  echo
  
  job_end_check_torque $jobid
  res=$?

fi

#===============================================================================
# Stage out

echo "[$(datetime_now)] Finalization (stage out)"

stage_out server || exit $?

#===============================================================================
# Finalization

echo "[$(datetime_now)] Finalization"
echo

backup_exp_setting $job $TMP $jobid ${job}_job.sh 'o e'

config_file_save $TMPS || exit $?

archive_log

#if ((CLEAR_TMP == 1)); then
#  safe_rm_tmpdir $TMP
#fi

#===============================================================================

echo "[$(datetime_now)] Finish $myname $@"

exit $res
