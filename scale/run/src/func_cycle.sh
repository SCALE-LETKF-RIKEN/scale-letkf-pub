#!/bin/bash
#===============================================================================
#
#  Steps of 'cycle.sh'
#  October 2014, created   Guo-Yuan Lien
#
#===============================================================================

setting () {
#-------------------------------------------------------------------------------
# define steps

nsteps=5
stepname[1]='Run SCALE pp'
stepexecdir[1]="$TMPRUN/scale_pp"
stepexecname[1]="scale-les_pp_ens"
stepname[2]='Run SCALE init'
stepexecdir[2]="$TMPRUN/scale_init"
stepexecname[2]="scale-les_init_ens"
stepname[3]='Run ensemble forecasts'
stepexecdir[3]="$TMPRUN/scale"
stepexecname[3]="scale-les_ens"
stepname[4]='Run observation operator'
stepexecdir[4]="$TMPRUN/obsope"
stepexecname[4]="obsope"
stepname[5]='Run LETKF'
stepexecdir[5]="$TMPRUN/letkf"
stepexecname[5]="letkf"

#-------------------------------------------------------------------------------
# usage help string

USAGE="
[$myname] Run data assimilation cycles.

Configuration files:
  config.main
  config.cycle

Steps:
$(for i in $(seq $nsteps); do echo "  ${i}. ${stepname[$i]}"; done)

Usage: $myname [STIME ETIME ISTEP FSTEP TIME_LIMIT]

  STIME       Time of the first cycle (format: YYYY[MMDDHHMMSS])
  ETIME       Time of the last  cycle (format: YYYY[MMDDHHMMSS])
               (default: same as STIME)
  MEMBERS     List of forecast members
               all:     Run all members (default)
               '2 4 6': Run members 2, 4, 6
  ISTEP       The initial step in the first cycle from which this script starts
               (default: the first step)
  FSTEP       The final step in the last cycle by which this script ends
               (default: the last step)
  TIME_LIMIT  Requested time limit (only used when using a job scheduler)
               (default: 30 minutes)
"

#if [ "$1" == '-h' ] || [ "$1" == '--help' ]; then
#  echo "$USAGE"
#  exit 0
#fi

#-------------------------------------------------------------------------------
# set parameters from command line

STIME=${1:-$STIME}; shift
ETIME=${1:-$ETIME}; shift
MEMBERS=${1:-$MEMBERS}; shift
ISTEP=${1:-$ISTEP}; shift
FSTEP=${1:-$FSTEP}; shift
TIME_LIMIT="${1:-$TIME_LIMIT}"

#-------------------------------------------------------------------------------
# if some necessary parameters are not given, print the usage help and exit

#if [ -z "$STIME" ]; then
#  echo "$USAGE" >&2
#  exit 1
#fi

#-------------------------------------------------------------------------------
# error detection

if ((MACHINE_TYPE == 10 && ONLINE_STGOUT != 0)); then
  echo "[Error] $myname: When \$MACHINE_TYPE = 10, \$ONLINE_STGOUT needs to be 0." >&2
  exit 1
fi

#... more detections...

#-------------------------------------------------------------------------------
# assign default values to and standardize the parameters

STIME=$(datetime $STIME)
ETIME=$(datetime ${ETIME:-$STIME})
if [ -z "$MEMBERS" ] || [ "$MEMBERS" = 'all' ]; then
  MEMBERS='all'
#  MEMBERS="$(printf "$MEMBER_FMT " $(seq $MEMBER))"
else
  MEMBER=0
  tmpstr=''
  for m in $MEMBERS; do
    MEMBER=$((MEMBER+1))
    tmpstr="$tmpstr$(printf $MEMBER_FMT $((10#$m))) "
    (($? != 0)) && exit 1
  done
  MEMBERS="$tmpstr"
fi
ISTEP=${ISTEP:-1}
FSTEP=${FSTEP:-$nsteps}
TIME_LIMIT=${TIME_LIMIT:-"0:30:00"}

#-------------------------------------------------------------------------------
# common variables

CYCLEFLEN=$WINDOW_E     # Model forecast length in a cycle (hour)
if [ -z "$FCSTOUT" ] || ((FCSTOUT >= LTIMESLOT)); then
  CYCLEFOUT=$LTIMESLOT  # Model forecast output interval (hour)
elif ((LTIMESLOT % FCSTOUT == 0)); then
  CYCLEFOUT=$FCSTOUT
else
  echo "[Error] If \$FCSTOUT < \$LTIMESLOT, \$LTIMESLOT needs to be an exact multiple of \$FCSTOUT" >&2
  exit 1
fi

if ((BDY_FORMAT == 1 || BDY_FORMAT == -1)); then
  if ((BDYCYCLE_INT % BDYINT != 0)); then
    echo "[Error] \$BDYCYCLE_INT needs to be an exact multiple of \$BDYINT" >&2
    exit 1
  fi
  BDY_STARTFRAME_MAX=$((BDYCYCLE_INT/BDYINT))
fi

BUILTIN_STAGING=$((MACHINE_TYPE != 10 && MACHINE_TYPE != 11))

if ((TMPRUN_MODE <= 2)); then
  PROC_OPT='one'
else
  PROC_OPT='alln'
fi

#-------------------------------------------------------------------------------
}

#===============================================================================

staging_list () {
#-------------------------------------------------------------------------------
# TMPDAT

if ((TMPDAT_MODE == 1 && MACHINE_TYPE != 10)); then
#-------------------
  safe_init_tmpdir $TMPDAT
  safe_init_tmpdir $TMPDAT/exec
  ln -fs $MODELDIR/scale-les_pp $TMPDAT/exec
  ln -fs $MODELDIR/scale-les_init $TMPDAT/exec
  ln -fs $MODELDIR/scale-les $TMPDAT/exec
  ln -fs $ENSMODEL_DIR/scale-les_pp_ens $TMPDAT/exec
  ln -fs $ENSMODEL_DIR/scale-les_init_ens $TMPDAT/exec
  ln -fs $ENSMODEL_DIR/scale-les_ens $TMPDAT/exec
  ln -fs $COMMON_DIR/pdbash $TMPDAT/exec
  ln -fs $OBSUTIL_DIR/obsope $TMPDAT/exec
  ln -fs $LETKF_DIR/letkf $TMPDAT/exec
  ln -fs $DATADIR/rad $TMPDAT/rad
  ln -fs $DATADIR/land $TMPDAT/land
  ln -fs $DATADIR/topo $TMPDAT
  ln -fs $DATADIR/landuse $TMPDAT

# H08
  if [ -e "${RTTOV_COEF}" ] && [ -e "${RTTOV_SCCOEF}" ]; then
    safe_init_tmpdir $TMPDAT/rttov
    ln -fs ${RTTOV_COEF} $TMPDAT/rttov/rtcoef_himawari_8_ahi.dat
    ln -fs ${RTTOV_SCCOEF} $TMPDAT/rttov/sccldcoef_himawari_8_ahi.dat
  fi

  if ((DATA_BDY_TMPLOC == 1)); then
    if ((BDY_FORMAT == 2)); then
      ln -fs $DATA_BDY_WRF $TMPDAT/bdywrf
    fi
  fi

  ln -fs $OBS $TMPDAT/obs

  safe_init_tmpdir $TMPDAT/conf
  ln -fs $SCRP_DIR/config.* $TMPDAT/conf
#-------------------
else
#-------------------
  cat >> $STAGING_DIR/stagein.dat << EOF
${MODELDIR}/scale-les_pp|exec/scale-les_pp
${MODELDIR}/scale-les_init|exec/scale-les_init
${MODELDIR}/scale-les|exec/scale-les
${ENSMODEL_DIR}/scale-les_pp_ens|exec/scale-les_pp_ens
${ENSMODEL_DIR}/scale-les_init_ens|exec/scale-les_init_ens
${ENSMODEL_DIR}/scale-les_ens|exec/scale-les_ens
${COMMON_DIR}/pdbash|exec/pdbash
${OBSUTIL_DIR}/obsope|exec/obsope
${LETKF_DIR}/letkf|exec/letkf
${SCRP_DIR}/config.nml.scale_pp|conf/config.nml.scale_pp
${SCRP_DIR}/config.nml.scale_init|conf/config.nml.scale_init
${SCRP_DIR}/config.nml.scale|conf/config.nml.scale
${SCRP_DIR}/config.nml.ensmodel|conf/config.nml.ensmodel
${SCRP_DIR}/config.nml.obsope|conf/config.nml.obsope
${SCRP_DIR}/config.nml.letkf|conf/config.nml.letkf
${DATADIR}/rad|rad
${DATADIR}/land|land
EOF

# H08
  if [ -e "${RTTOV_COEF}" ] && [ -e "${RTTOV_SCCOEF}" ]; then
    cat >> $STAGING_DIR/stagein.dat << EOF
${RTTOV_COEF}|rttov/rtcoef_himawari_8_ahi.dat
${RTTOV_SCCOEF}|rttov/sccldcoef_himawari_8_ahi.dat
EOF
  fi

  if [ "$TOPO_FORMAT" != 'prep' ]; then
    if ((DISK_MODE_TOPO_LANDUSE_DB == 2)); then
      echo "${DATADIR}/topo/${TOPO_FORMAT}/Products|topo/${TOPO_FORMAT}/Products|s" >> $STAGING_DIR/stagein.dat
    else
      echo "${DATADIR}/topo/${TOPO_FORMAT}/Products|topo/${TOPO_FORMAT}/Products" >> $STAGING_DIR/stagein.dat
    fi
  fi
  if [ "$LANDUSE_FORMAT" != 'prep' ]; then
    if ((DISK_MODE_TOPO_LANDUSE_DB == 2)); then
      echo "${DATADIR}/landuse/${LANDUSE_FORMAT}/Products|landuse/${LANDUSE_FORMAT}/Products|s" >> $STAGING_DIR/stagein.dat
    else
      echo "${DATADIR}/landuse/${LANDUSE_FORMAT}/Products|landuse/${LANDUSE_FORMAT}/Products" >> $STAGING_DIR/stagein.dat
    fi
  fi

  time=$(datetime $STIME $LCYCLE s)
  while ((time <= $(datetime $ETIME $LCYCLE s))); do
    for iobs in $(seq $OBSNUM); do
      if [ "${OBSNAME[$iobs]}" != '' ] && [ -e ${OBS}/${OBSNAME[$iobs]}_${time}.dat ]; then
        echo "${OBS}/${OBSNAME[$iobs]}_${time}.dat|obs/${OBSNAME[$iobs]}_${time}.dat" >> $STAGING_DIR/stagein.dat
      fi
    done
    time=$(datetime $time $LCYCLE s)
  done

  if ((MACHINE_TYPE == 10)); then
    echo "${COMMON_DIR}/datetime|exec/datetime" >> $STAGING_DIR/stagein.dat
  fi
#-------------------
fi

#-------------------------------------------------------------------------------
# TMPOUT

if ((TMPOUT_MODE == 1 && MACHINE_TYPE != 10)); then
#-------------------
  mkdir -p $(dirname $TMPOUT)
  ln -fs $OUTDIR $TMPOUT

  time=$STIME
  while ((time <= ETIME)); do
    #-------------------
    if [ "$TOPO_FORMAT" = 'prep' ]; then
      mkdir -p $TMPOUT/${time}
      rm -fr $TMPOUT/${time}/topo
      ln -s ${DATA_TOPO} $TMPOUT/${time}/topo
    fi
    if [ "$LANDUSE_FORMAT" = 'prep' ]; then
      mkdir -p $TMPOUT/${time}
      rm -fr $TMPOUT/${time}/landuse
      if ((LANDUSE_UPDATE == 1)); then
        ln -s ${DATA_LANDUSE}/${time} $TMPOUT/${time}/landuse
      else
        ln -s ${DATA_LANDUSE} $TMPOUT/${time}/landuse
      fi
    fi
    if ((BDY_FORMAT == 0)); then
      mkdir -p $TMPOUT/${time}
      rm -fr $TMPOUT/${time}/bdy
      ln -fs ${DATA_BDY_SCALE_PREP}/${time} $TMPOUT/${time}/bdy
    fi
    time=$(datetime $time $LCYCLE s)
    #-------------------
  done

  if ((DATA_BDY_TMPLOC == 2)); then
    if ((BDY_FORMAT == 2)); then
      ln -fs $DATA_BDY_WRF $TMPOUT/bdywrf
    fi
  fi

  if ((BDY_FORMAT == 1)) || ((BDY_FORMAT == -1)); then
    find_catalogue=0
    time=$STIME
    time_bdy_prev=0
    while ((time <= ETIME)); do
      time_bdy=$(datetime $time $BDYCYCLE_INT s)
      for bdy_startframe in $(seq $BDY_STARTFRAME_MAX); do
        if [ -s "$DATA_BDY_SCALE/${time_bdy}/gues/meanf/history.pe000000.nc" ]; then
          break
        elif ((bdy_startframe == BDY_STARTFRAME_MAX)); then
          echo "[Error] Cannot find boundary files from the SCALE history files." >&2
          exit 1
        fi
        time_bdy=$(datetime $time_bdy -${BDYINT} s)
      done

      if ((DATA_BDY_TMPLOC == 1)); then
        bdyscale_dir="$TMPDAT/bdyscale"
      elif ((DATA_BDY_TMPLOC == 2)); then
        bdyscale_dir="$TMPOUT/bdyscale"
      fi
      mkdir -p $bdyscale_dir

      if ((find_catalogue == 0)); then
        time_catalogue=$(datetime $time_bdy -$BDYCYCLE_INT s)
        if [ -s "$DATA_BDY_SCALE/${time_catalogue}/log/scale/latlon_domain_catalogue.txt" ]; then
          pathin="$DATA_BDY_SCALE/${time_catalogue}/log/scale/latlon_domain_catalogue.txt"
          ln -fs ${pathin} ${bdyscale_dir}/latlon_domain_catalogue.txt
          find_catalogue=1
        fi
      fi

      if ((time_bdy != time_bdy_prev)); then
        if ((BDY_ENS == 1)); then
          for m in $(seq $mmean); do
            mem=${name_m[$m]}
            [ "$mem" = 'mean' ] && mem='meanf'
            mkdir -p ${bdyscale_dir}/${time_bdy}/${name_m[$m]}
            for ifile in $(ls $DATA_BDY_SCALE/${time_bdy}/gues/${mem}/history.*.nc 2> /dev/null); do
              pathin="$ifile"
              ln -fs ${pathin} ${bdyscale_dir}/${time_bdy}/${name_m[$m]}/$(basename $ifile)
            done
          done
        else
          mkdir -p ${bdyscale_dir}/${time_bdy}/mean
          for ifile in $(ls $DATA_BDY_SCALE/${time_bdy}/gues/meanf/history.*.nc 2> /dev/null); do
            pathin="$ifile"
            ln -fs ${pathin} ${bdyscale_dir}/${time_bdy}/mean/$(basename $ifile)
          done
        fi
        time_bdy_prev=$time_bdy
      fi
      time=$(datetime $time $LCYCLE s)
    done

    if ((find_catalogue == 0)); then
      echo "[Error] Cannot find a lat/lon domain catalogue file." >&2
      exit 1
    fi
  fi
#-------------------
else
#-------------------
  time=$STIME
  atime=$(datetime $time $LCYCLE s)
  loop=0
  while ((time <= ETIME)); do
    loop=$((loop+1))
    if ((ONLINE_STGOUT == 1)); then
      stgoutstep="stageout.loop.${loop}"
    else
      stgoutstep='stageout.out'
    fi
    #-------------------
    # stage-in
    #-------------------

    # anal
    #-------------------
    if ((loop == 1)) && ((MAKEINIT != 1)); then
      for m in $(seq $mmean); do
        for q in $(seq $mem_np); do
          path="${time}/anal/${name_m[$m]}/init$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]}
        done
      done
    fi

    # anal_ocean
    #-------------------
#    if ((OCEAN_INPUT == 1)) && ((OCEAN_FORMAT == 0)); then
#      for m in $(seq $mmean); do
#        for q in $(seq $mem_np); do
#          path="${time}/anal/${name_m[$m]}/init_ocean$(printf $SCALE_SFX $((q-1)))"
#          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]}
#        done
#      done
#    fi

    # topo
    #-------------------
    if [ "$TOPO_FORMAT" = 'prep' ]; then
      if [ "$TOPO_TARGZ" = 'T' ]; then
        if [ ! -e ${DATA_TOPO}/topo.tar.gz ] ; then
          cd ${DATA_TOPO}
          tar czvfh topo.tar.gz topo*.nc >/dev/null
          cd -
        fi
        pathin=${DATA_TOPO}/topo.tar.gz
        path=${time}/topo/topo.tar.gz
        echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
      else
        for m in $(seq $mmean); do
          for q in $(seq $mem_np); do
            pathin="${DATA_TOPO}/topo$(printf $SCALE_SFX $((q-1)))"
            path="${time}/topo/topo$(printf $SCALE_SFX $((q-1)))"
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]}
          done
        done
      fi
    elif [ "$TOPO_TARGZ" = 'T' ] ; then
      echo "[Error] TOPO_TARGZ = T option requires TOPO_FORMAT = prep" >&2
      exit 1
    fi

    # landuse
    #-------------------
    if [ "$LANDUSE_FORMAT" = 'prep' ]; then
      if [ -d "${DATA_LANDUSE}/${time}" ]; then
        pathin_pfx="${DATA_LANDUSE}/${time}"
      else
        pathin_pfx="${DATA_LANDUSE}"
      fi
      if [ "$LANDUSE_TARGZ" = 'T' ]; then
        if [ ! -e ${pathin_pfx}/landuse.tar.gz ] ; then
          cd ${pathin_pfx}
          tar czvfh landuse.tar.gz landuse*.nc >/dev/null
          cd -
        fi
        pathin=${pathin_pfx}/landuse.tar.gz
        path=${time}/landuse/landuse.tar.gz
        echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
      else
        for m in $(seq $mmean); do
          for q in $(seq $mem_np); do
            pathin="${pathin_pfx}/landuse$(printf $SCALE_SFX $((q-1)))"
            path="${time}/landuse/landuse$(printf $SCALE_SFX $((q-1)))"
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]}
          done
        done
      fi
    elif [ "$LANDUSE_TARGZ" = 'T' ] ; then
      echo "[Error] LANDUSE_TARGZ = T option requires LANDUSE_FORMAT = prep" >&2
      exit 1
    fi

    # bdy (prepared)
    #-------------------
    if ((BDY_FORMAT == 0 || BDY_FORMAT == -1)); then
      if ((BDY_ENS == 0)); then
        for m in $(seq $mmean); do
          for q in $(seq $mem_np); do
            pathin="${DATA_BDY_SCALE_PREP}/${time}/bdy/mean/boundary$(printf $SCALE_SFX $((q-1)))"
#            pathin="${DATA_BDY_SCALE_PREP}/${time}/mean/boundary$(printf $SCALE_SFX $((q-1)))"
            path="${time}/bdy/mean/boundary$(printf $SCALE_SFX $((q-1)))"
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]}
          done
        done
      elif ((BDY_ENS == 1)); then
        for m in $(seq $mmean); do
          for q in $(seq $mem_np); do
            pathin="${DATA_BDY_SCALE_PREP}/${time}/bdy/${name_m[$m]}/boundary$(printf $SCALE_SFX $((q-1)))"
#            pathin="${DATA_BDY_SCALE_PREP}/${time}/${name_m[$m]}/boundary$(printf $SCALE_SFX $((q-1)))"
            path="${time}/bdy/${name_m[$m]}/boundary$(printf $SCALE_SFX $((q-1)))"
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]}
          done
        done
      fi
    fi

    #-------------------
    # stage-out
    #-------------------

    #++++++
    if ((SIMPLE_STGOUT == 1)); then
    #++++++

      if ((loop == 1)) && ((MAKEINIT == 1)); then
        path="${time}/anal"
        echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      fi
      if ((TOPOOUT_OPT <= 1)); then
        path="${time}/topo"
        echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      fi
      if ((LANDUSEOUT_OPT <= 1)); then
        path="${time}/landuse"
        echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      fi
      if ((BDYOUT_OPT <= 2)); then
        path="${time}/bdy"
        echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      fi
      ### anal_ocean [mean]
      path="${time}/log/scale_pp"
      echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      path="${time}/log/scale_init"
      echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      path="${time}/log/scale"
      echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}

      path="${atime}/gues"
      echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      path="${atime}/anal"
      echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      path="${atime}/obsgues"
      echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      path="${atime}/log/obsope"
      echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}
      path="${atime}/log/letkf"
      echo "${OUTDIR}/${path}|${path}|d" >> $STAGING_DIR/${stgoutstep}

    #++++++
    else
    #++++++
      for m in $(seq $MEMBER); do
        #-------------------

        for q in $(seq $mem_np); do
          #-------------------

          # bdy [members]
          #-------------------
          if ((BDYOUT_OPT <= 1)) && ((BDY_ENS == 1)); then
            path="${time}/bdy/${name_m[$m]}/boundary$(printf $SCALE_SFX $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((m-1)*mem_np+q))]}
          fi

          # gues [history]
          #-------------------
          if ((OUT_OPT <= 1)); then
            path="${atime}/gues/${name_m[$m]}/history$(printf $SCALE_SFX $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((m-1)*mem_np+q))]}
          fi

          # gues [restart]
          #-------------------
          if ((OUT_OPT <= 2)); then
            path="${atime}/gues/${name_m[$m]}/init$(printf $SCALE_SFX $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((m-1)*mem_np+q))]}
          fi

          # anal
          #-------------------
          if ((loop == 1)) && ((MAKEINIT == 1)); then
            path="${time}/anal/${name_m[$m]}/init$(printf $SCALE_SFX $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((m-1)*mem_np+q))]}
          fi
          if ((OUT_OPT <= 3)); then
            path="${atime}/anal/${name_m[$m]}/init$(printf $SCALE_SFX $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((m-1)*mem_np+q))]}
          fi

          # anal_ocean
          #-------------------
  #        if ((OCEAN_INPUT == 1)) && ((MAKEINIT != 1)); then
  #          path="${time}/anal/${name_m[$m]}/init_ocean$(printf $SCALE_SFX $((q-1)))"
  #          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((m-1)*mem_np+q))]}
  #        fi

          # obsgues
          #-------------------
          if ((OBSOUT_OPT <= 2)); then
            path="${atime}/obsgues/${name_m[$m]}/obsda.${name_m[$m]}.$(printf $PROCESS_FMT $((q-1))).dat"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((m-1)*mem_np+q))]}
          fi

          #-------------------
        done

  #      if ((LOG_OPT <= 1)); then
  #        # perturb bdy log
  #      fi

        #-------------------
      done

      #-------------------

      for q in $(seq $mem_np); do
        #-------------------

        # topo
        #-------------------
        if ((TOPOOUT_OPT <= 1)); then
          path="${time}/topo/topo$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$q]} # ues m=1 instead of m=mmean to enhance parallelization
        fi

        # landuse
        #-------------------
        if ((LANDUSEOUT_OPT <= 1)); then
          path="${time}/landuse/landuse$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$q]} # ues m=1 instead of m=mmean to enhance parallelization
        fi

        # bdy [mean]
        #-------------------
        if ((BDYOUT_OPT <= 2)); then
          path="${time}/bdy/mean/boundary$(printf $SCALE_SFX $((q-1)))"
          if ((BDY_ENS == 1)); then
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mmean-1)*mem_np+q))]}
          else
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$q]} # ues m=1 instead of m=mmean to enhance parallelization
          fi
        fi

        # anal_ocean [mean]
        #-------------------
        if ((OCEAN_INPUT == 1)) && ((MAKEINIT != 1)); then
          path="${time}/anal/mean/init_ocean$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mmean-1)*mem_np+q))]}
        fi

        # mean/sprd
        #-------------------
        if ((OUT_OPT <= 4)); then
          path="${atime}/gues/mean/init$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mmean-1)*mem_np+q))]}
          path="${atime}/gues/sprd/init$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mmean-1)*mem_np+q))]}

          path="${atime}/anal/mean/init$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mmean-1)*mem_np+q))]}
          path="${atime}/anal/sprd/init$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mmean-1)*mem_np+q))]}
        fi

        # meanf
        #-------------------
        if ((OUT_OPT <= 1)); then
          path="${atime}/gues/meanf/history$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mmean-1)*mem_np+q))]}
        fi
        if ((OUT_OPT <= 4)); then
          path="${atime}/gues/meanf/init$(printf $SCALE_SFX $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((mmean-1)*mem_np+q))]}
        fi

        # log [scale_pp/scale_init/scale/obsope/letkf]
        #-------------------
        if ((LOG_OPT <= 4)); then
          if [ "$TOPO_FORMAT" != 'prep' ] || [ "$LANDUSE_FORMAT" != 'prep' ] && ((BDY_FORMAT != 0)) && ((BDY_FORMAT != -1)); then
            path="${time}/log/scale_pp/NOUT-$(printf $PROCESS_FMT $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$q]}
          fi
          if ((BDY_FORMAT != 0)) && ((BDY_FORMAT != -1)); then
            path="${time}/log/scale_init/NOUT-$(printf $PROCESS_FMT $((q-1)))"
            echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$q]}
          fi
          path="${time}/log/scale/NOUT-$(printf $PROCESS_FMT $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$q]}
          path="${atime}/log/obsope/NOUT-$(printf $PROCESS_FMT $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$q]}
          path="${atime}/log/letkf/NOUT-$(printf $PROCESS_FMT $((q-1)))"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$q]}
        fi

        #-------------------
      done

      # log [scale_pp]
      #-------------------
      if [ "$TOPO_FORMAT" != 'prep' ] || [ "$LANDUSE_FORMAT" != 'prep' ] || ((BDY_FORMAT == 0 || BDY_FORMAT == -1)); then
        if ((LOG_OPT <= 2)); then
          path="${time}/log/scale_pp/pp_LOG${SCALE_LOG_SFX}"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[1]}
        fi
      fi

      # log [scale_init: mean]
      #-------------------
      if ((BDY_FORMAT > 0)) && ((LOG_OPT <= 2)) && ((BDY_ENS != 1)); then
        path="${time}/log/scale_init/mean_init_LOG${SCALE_LOG_SFX}"
        echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[1]}
      fi

      # log [scale: catalogue]
      #-------------------
      path="${time}/log/scale/latlon_domain_catalogue.txt"
      echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[1]}


      #-------------------

      for m in $(seq $mmean); do
        #-------------------

        # log [scale_init: members]
        #-------------------
        if ((BDY_FORMAT > 0)) && ((LOG_OPT <= 2)) && ((BDY_ENS == 1)); then
          path="${time}/log/scale_init/${name_m[$m]}_init_LOG${SCALE_LOG_SFX}"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((m-1)*mem_np+1))]}
        fi

        # log [scale]
        #-------------------
        if ((LOG_OPT <= 3)); then
          path="${time}/log/scale/${name_m[$m]}_LOG${SCALE_LOG_SFX}"
          echo "${OUTDIR}/${path}|${path}" >> $STAGING_DIR/${stgoutstep}.${mem2node[$(((m-1)*mem_np+1))]}
        fi

        #-------------------
      done
    #++++++
    fi # ((SIMPLE_STGOUT == 1))
    #++++++

    #-------------------
    time=$(datetime $time $LCYCLE s)
    atime=$(datetime $time $LCYCLE s)
  done

  #-------------------
  # stage-in
  #-------------------

  # bdy
  #-------------------
  if ((BDY_FORMAT == 1)) || ((BDY_FORMAT == -1)); then

    find_catalogue=0
    time=$STIME
    time_bdy_prev=0
    while ((time <= ETIME)); do
      time_bdy=$(datetime $time $BDYCYCLE_INT s)
      for bdy_startframe in $(seq $BDY_STARTFRAME_MAX); do
        if [ -s "$DATA_BDY_SCALE/${time_bdy}/gues/meanf/history.pe000000.nc" ]; then
          break
        elif ((bdy_startframe == BDY_STARTFRAME_MAX)); then
          echo "[Error] Cannot find boundary files from the SCALE history files." >&2
          exit 1
        fi
        time_bdy=$(datetime $time_bdy -${BDYINT} s)
      done

      if ((find_catalogue == 0)); then
        time_catalogue=$(datetime $time_bdy -$BDYCYCLE_INT s)
        if [ -s "$DATA_BDY_SCALE/${time_catalogue}/log/scale/latlon_domain_catalogue.txt" ]; then
          pathin="$DATA_BDY_SCALE/${time_catalogue}/log/scale/latlon_domain_catalogue.txt"
          path="bdyscale/latlon_domain_catalogue.txt"
#          if ((DATA_BDY_TMPLOC == 1)); then
#            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
#          elif ((DATA_BDY_TMPLOC == 2)); then
#            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
#          fi
          if ((DISK_MODE_DATA_BDY == 2)); then
            echo "${pathin}|${path}|s" >> $STAGING_DIR/stagein.dat
          else
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
          fi
          find_catalogue=1
        fi
      fi

      if ((time_bdy != time_bdy_prev)); then
        if ((BDY_ENS == 1)); then
          for m in $(seq $mmean); do
            mem=${name_m[$m]}
            [ "$mem" = 'mean' ] && mem='meanf'
            for ifile in $(ls $DATA_BDY_SCALE/${time_bdy}/gues/${mem}/history.*.nc 2> /dev/null); do
              pathin="$ifile"
              path="bdyscale/${time_bdy}/${name_m[$m]}/$(basename $ifile)"

#              if ((DATA_BDY_TMPLOC == 1)); then
#                echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
#              elif ((DATA_BDY_TMPLOC == 2)); then
#                for q in $(seq $mem_np); do
#                  echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]} ###### q: may be redundant ????
#                done
#              fi
              if ((DISK_MODE_DATA_BDY == 2)); then
                echo "${pathin}|${path}|s" >> $STAGING_DIR/stagein.dat
              else
                echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
              fi

            done
#            pathin="$DATA_BDY_SCALE/${time_bdy}/gues/${mem}"
#            path="bdyscale/${time_bdy}/${name_m[$m]}"
#            if ((DATA_BDY_TMPLOC == 1)); then
#              echo "${pathin}|${path}|d" >> $STAGING_DIR/stagein.dat
#            elif ((DATA_BDY_TMPLOC == 2)); then
#              for q in $(seq $mem_np); do
#                echo "${pathin}|${path}|d" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]} ###### q: may be redundant ????
#              done
#            fi
          done
        else
          for ifile in $(ls $DATA_BDY_SCALE/${time_bdy}/gues/meanf/history.*.nc 2> /dev/null); do
            pathin="$ifile"
            path="bdyscale/${time_bdy}/mean/$(basename $ifile)"

#            if ((DATA_BDY_TMPLOC == 1)); then
#              echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
#            elif ((DATA_BDY_TMPLOC == 2)); then
#              echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
#            fi
            if ((DISK_MODE_DATA_BDY == 2)); then
              echo "${pathin}|${path}|s" >> $STAGING_DIR/stagein.dat
            else
              echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
            fi
          done
#          pathin="$DATA_BDY_SCALE/${time_bdy}/gues/meanf"
#          path="bdyscale/${time_bdy}/mean"
#            if ((DATA_BDY_TMPLOC == 1)); then
#            echo "${pathin}|${path}|d" >> $STAGING_DIR/stagein.dat
#          elif ((DATA_BDY_TMPLOC == 2)); then
#            echo "${pathin}|${path}|d" >> $STAGING_DIR/stagein.out
#          fi
        fi
        time_bdy_prev=$time_bdy
      fi
      time=$(datetime $time $LCYCLE s)
    done

    if ((find_catalogue == 0)); then
      echo "[Error] Cannot find a lat/lon domain catalogue file." >&2
      exit 1
    fi

  #-------------------
  elif ((BDY_FORMAT == 2)); then

    time_dby=${STIME}
    etime_bdy=$(datetime ${ETIME} $((CYCLEFLEN+BDYINT)) s)
    while ((time_dby < etime_bdy)); do
      if ((BDY_ENS == 1)); then
        for m in $(seq $mmean); do
          pathin="$DATA_BDY_WRF/${name_m[$m]}/wrfout_${time_dby}"
          path="bdywrf/${name_m[$m]}/wrfout_${time_dby}"

#          if ((DATA_BDY_TMPLOC == 1)); then
#            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
#          elif ((DATA_BDY_TMPLOC == 2)); then
#            for q in $(seq $mem_np); do
#              echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out.${mem2node[$(((m-1)*mem_np+q))]} ###### q: may be redundant ????
#            done
#          fi
          if ((DISK_MODE_DATA_BDY == 2)); then
            echo "${pathin}|${path}|s" >> $STAGING_DIR/stagein.dat
          else
            echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
          fi
        done
      else
        pathin="$DATA_BDY_WRF/mean/wrfout_${time_dby}"
        path="bdywrf/mean/wrfout_${time_dby}"

#        if ((DATA_BDY_TMPLOC == 1)); then
#          echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
#        elif ((DATA_BDY_TMPLOC == 2)); then
#          echo "${pathin}|${path}" >> $STAGING_DIR/stagein.out
#        fi
        if ((DISK_MODE_DATA_BDY == 2)); then
          echo "${pathin}|${path}|s" >> $STAGING_DIR/stagein.dat
        else
          echo "${pathin}|${path}" >> $STAGING_DIR/stagein.dat
        fi
      fi
      time_dby=$(datetime $time_dby $BDYINT s)
    done

  fi

  #-------------------

#-------------------
fi

#-------------------------------------------------------------------------------
}

#===============================================================================

enspp_1 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Pre-processing scripts"
#echo

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[1]}: Pre-processing script start" >&2
fi

if [ "$TOPO_FORMAT" == 'prep' ] && [ "$LANDUSE_FORMAT" == 'prep' ]; then
  echo "  ... skip this step (use prepared topo and landuse files)"
  exit 1
elif ((BDY_FORMAT == 0 || BDY_FORMAT == -1)); then
  echo "  ... skip this step (use prepared boundaries)"
  exit 1
fi

if ((TMPRUN_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=1
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= mmean ? repeat_mems : mmean))
fi

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_scale_pp_node.sh $MYRANK \
       $mem_nodes $mem_np $TMPRUN/scale_pp $TMPDAT/exec $TMPDAT $MEMBER_RUN $iter
fi

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[1]}: Pre-processing script end" >&2
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[1]}: $it: Pre-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= MEMBER_RUN)); then
    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/pre_scale_pp.sh $MYRANK $time \
           $TMPRUN/scale_pp/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[1]}: $it: Pre-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

enspp_2 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Post-processing scripts"
#echo

if [ "$TOPO_FORMAT" == 'prep' ] && [ "$LANDUSE_FORMAT" == 'prep' ]; then
  return 1
elif ((BDY_FORMAT == 0 || BDY_FORMAT == -1)); then
  return 1
fi

if ((TMPRUN_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=1
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= mmean ? repeat_mems : mmean))
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[1]}: $it: Post-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= MEMBER_RUN)); then
    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/post_scale_pp.sh $MYRANK $mem_np $time \
           ${name_m[$m]} $TMPRUN/scale_pp/$(printf '%04d' $m) $LOG_OPT
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[1]}: $it: Post-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

ensinit_1 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Pre-processing scripts"
#echo

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[2]}: Pre-processing script start" >&2
fi

if ((BDY_FORMAT == 0 || BDY_FORMAT == -1)); then
  echo "  ... skip this step (use prepared boundaries)"
  exit 1
elif ((BDY_FORMAT == 1)); then
#  if ((DATA_BDY_TMPLOC == 1)); then
#    bdyscale_loc=$TMPDAT/bdyscale
#  elif ((DATA_BDY_TMPLOC == 2)); then
#    bdyscale_loc=$TMPOUT/bdyscale
#  fi
  if ((DISK_MODE_DATA_BDY == 2)); then
    bdyscale_loc=${TMPDAT_S}/bdyscale
  else
    bdyscale_loc=${TMPDAT_L}/bdyscale
  fi
  time_bdy=$(datetime $time $BDYCYCLE_INT s)
  for bdy_startframe in $(seq $BDY_STARTFRAME_MAX); do
    if [ -s "$bdyscale_loc/${time_bdy}/mean/history.pe000000.nc" ]; then
      break
    elif ((bdy_startframe == BDY_STARTFRAME_MAX)); then
      echo "[Error] Cannot find boundary files from the SCALE history files." >&2
      exit 1
    fi
    time_bdy=$(datetime $time_bdy -${BDYINT} s)
  done
elif ((BDY_FORMAT == 2)); then
#  if ((DATA_BDY_TMPLOC == 1)); then
#    bdywrf_loc=$TMPDAT/bdywrf
#  elif ((DATA_BDY_TMPLOC == 2)); then
#    bdywrf_loc=$TMPOUT/bdywrf
#  fi
  if ((DISK_MODE_DATA_BDY == 2)); then
    bdywrf_loc=${TMPDAT_S}/bdywrf
  else
    bdywrf_loc=${TMPDAT_L}/bdywrf
  fi
fi

if ((BDY_ENS == 1)); then
  MEMBER_RUN=$mmean
elif ((TMPRUN_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=1
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= mmean ? repeat_mems : mmean))
fi

mkinit=0
if ((loop == 1)); then
  mkinit=$MAKEINIT
fi

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_scale_init_node.sh $MYRANK \
       $mem_nodes $mem_np $TMPRUN/scale_init $TMPDAT/exec $TMPDAT $MEMBER_RUN $iter
fi

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[2]}: Pre-processing script end" >&2
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[2]}: $it: Pre-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= MEMBER_RUN)); then
    if (pdrun $g $PROC_OPT); then
      #------
      if ((BDY_FORMAT == 1)); then
      #------
        if ((BDY_ENS == 1)); then
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK $mem_np \
               $TMPOUT/${time}/topo/topo $TMPOUT/${time}/landuse/landuse \
               ${bdyscale_loc}/${time_bdy}/${name_m[$m]}/history \
               $time $CYCLEFLEN $mkinit ${name_m[$m]} \
               $TMPRUN/scale_init/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT \
               $bdy_startframe
        else
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK $mem_np \
               $TMPOUT/${time}/topo/topo $TMPOUT/${time}/landuse/landuse \
               ${bdyscale_loc}/${time_bdy}/mean/history \
               $time $CYCLEFLEN $mkinit mean \
               $TMPRUN/scale_init/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT \
               $bdy_startframe
        fi
      #------
      elif ((BDY_FORMAT == 2)); then
      #------
        if ((BDY_ENS == 1)); then
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK $mem_np \
               $TMPOUT/${time}/topo/topo $TMPOUT/${time}/landuse/landuse \
               ${bdywrf_loc}/${name_m[$m]}/wrfout \
               $time $CYCLEFLEN $mkinit ${name_m[$m]} \
               $TMPRUN/scale_init/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT
        else
          bash $SCRP_DIR/src/pre_scale_init.sh $MYRANK $mem_np \
               $TMPOUT/${time}/topo/topo $TMPOUT/${time}/landuse/landuse \
               ${bdywrf_loc}/mean/wrfout \
               $time $CYCLEFLEN $mkinit mean \
               $TMPRUN/scale_init/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT
        fi
      #------
#      elif ((BDY_FORMAT == 3)); then
      #------
      #------
      fi
      #------
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[1]}: $it: Pre-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

ensinit_2 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Post-processing scripts"
#echo

if ((BDY_FORMAT == 0)); then
  return 1
fi

if ((BDY_ENS == 1)); then
  MEMBER_RUN=$mmean
elif ((TMPRUN_MODE <= 2)); then # shared run directory: only run one member per cycle
  MEMBER_RUN=1
else # local run directory: run multiple members as needed
  MEMBER_RUN=$((repeat_mems <= mmean ? repeat_mems : mmean))
fi

mkinit=0
if ((loop == 1)); then
  mkinit=$MAKEINIT
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[2]}: $it: Post-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= MEMBER_RUN)); then
    if (pdrun $g $PROC_OPT); then
      if ((BDY_FORMAT == 1 || BDY_FORMAT == 2)); then
        if ((BDY_ENS == 1)); then
          bash $SCRP_DIR/src/post_scale_init.sh $MYRANK $mem_np $time \
               $mkinit ${name_m[$m]} $TMPRUN/scale_init/$(printf '%04d' $m) $LOG_OPT
        else
          bash $SCRP_DIR/src/post_scale_init.sh $MYRANK $mem_np $time \
               $mkinit mean $TMPRUN/scale_init/$(printf '%04d' $m) $LOG_OPT
        fi
      elif ((BDY_FORMAT == 3)); then
        echo
        #........
      fi
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[2]}: $it: Post-processing script (member) start" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

ensfcst_1 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Pre-processing scripts"
#echo

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[3]}: Pre-processing script start" >&2
fi

############
#if ((BDY_FORMAT == 1 || BDY_FORMAT == -1)); then
#  if ((DATA_BDY_TMPLOC == 1)); then
#    bdyscale_loc=$TMPDAT/bdyscale
#  elif ((DATA_BDY_TMPLOC == 2)); then
#    bdyscale_loc=$TMPOUT/bdyscale
#  fi
#  time_bdy=$(datetime $time $BDYCYCLE_INT s)
#  for bdy_startframe in $(seq $BDY_STARTFRAME_MAX); do
#    if [ -s "$bdyscale_loc/${time_bdy}/mean/history.pe000000.nc" ]; then
#      break
#    elif ((bdy_startframe == BDY_STARTFRAME_MAX)); then
#      echo "[Error] Cannot find boundary files from the SCALE history files." >&2
#      exit 1
#    fi
#    time_bdy=$(datetime $time_bdy -${BDYINT} s)
#  done
#  time_bdy=$(datetime $time_bdy -$BDYCYCLE_INT s)
#fi
############

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_scale_node.sh $MYRANK \
       $mem_nodes $mem_np $TMPRUN/scale $TMPDAT/exec $TMPDAT $((MEMBER+1)) $iter $time
fi

mkinit=0
if ((loop == 1)); then
  mkinit=$MAKEINIT
fi

ocean_base='-'
if ((OCEAN_INPUT == 1)); then
  if ((mkinit != 1 || OCEAN_FORMAT != 99)); then
    ocean_base="$TMPOUT/${time}/anal/mean/init_ocean"  ### always use mean???
  fi
fi

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[3]}: Pre-processing script end" >&2
fi

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[3]}: $it: Pre-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= mmean)); then

#    if ((PERTURB_BDY == 1)); then
#      ...
#    fi

    if ((BDY_ENS == 1)); then
      bdy_base="$TMPOUT/${time}/bdy/${name_m[$m]}/boundary"
    else
      bdy_base="$TMPOUT/${time}/bdy/mean/boundary"
    fi

    if (pdrun $g $PROC_OPT); then
#      if ((BDY_FORMAT == 1 || BDY_FORMAT == -1)); then
#        bash $SCRP_DIR/src/pre_scale.sh $MYRANK $mem_np \
#             $TMPOUT/${time}/anal/${name_m[$m]}/init $ocean_base $bdy_base \
#             $TMPOUT/${time}/topo/topo $TMPOUT/${time}/landuse/landuse \
#             $time $CYCLEFLEN $LCYCLE $CYCLEFOUT $TMPRUN/scale/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT ## $time_bdy
#      elif ((BDY_FORMAT == 2)); then
        bash $SCRP_DIR/src/pre_scale.sh $MYRANK $mem_np ${name_m[$m]} \
             $TMPOUT/${time}/anal/${name_m[$m]}/init $ocean_base $bdy_base \
             $TMPOUT/${time}/topo/topo $TMPOUT/${time}/landuse/landuse \
             $time $CYCLEFLEN $LCYCLE $CYCLEFOUT $TMPRUN/scale/$(printf '%04d' $m) $TMPDAT/exec $TMPDAT
#      elif ((BDY_FORMAT == 3)); then
#      fi
      
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[3]}: $it: Pre-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

ensfcst_2 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Post-processing scripts"
#echo

for it in $(seq $its $ite); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[3]}: $it: Post-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= mmean)); then

#    if ((PERTURB_BDY == 1)); then
#      ...
#    fi

    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/post_scale.sh $MYRANK $mem_np \
           $time ${name_m[$m]} $CYCLEFLEN $TMPRUN/scale/$(printf '%04d' $m) $LOG_OPT cycle $iter
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[3]}: $it: Post-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

obsope_1 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Pre-processing scripts"
#echo

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[4]}: Pre-processing script start" >&2
fi

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_obsope_node.sh $MYRANK \
       $atime $TMPRUN/obsope $TMPDAT/exec $TMPDAT/obs \
       $mem_nodes $mem_np $slot_s $slot_e $slot_b $MEMBER
fi

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[4]}: Pre-processing script end" >&2
fi

for it in $(seq $nitmax); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[4]}: $it: Pre-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= mmean)); then
    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/pre_obsope.sh $MYRANK \
           $atime ${name_m[$m]} $(printf '%04d' $m) $TMPRUN/obsope
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[4]}: $it: Pre-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

obsope_2 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Post-processing scripts"
#echo

for it in $(seq $nitmax); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[4]}: $it: Post-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= mmean)); then
    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/post_obsope.sh $MYRANK \
           $mem_np ${atime} ${name_m[$m]} $(printf '%04d' $m) $TMPRUN/obsope $LOG_OPT $OUT_OPT
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[4]}: $it: Post-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

letkf_1 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Pre-processing scripts"
#echo

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[5]}: Pre-processing script start" >&2
fi

if (pdrun all $PROC_OPT); then
  bash $SCRP_DIR/src/pre_letkf_node.sh $MYRANK \
       $atime $TMPRUN/letkf $TMPDAT/exec $TMPDAT/obs \
       $mem_nodes $mem_np $slot_s $slot_e $slot_b $TMPOUT/${time}/topo/topo $MEMBER
fi

if ((MYRANK == 0)); then
  echo "[$(datetime_now)] ${time}: ${stepname[5]}: Pre-processing script end" >&2
fi

for it in $(seq $nitmax); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[5]}: $it: Pre-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= mmean)); then
    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/pre_letkf.sh $MYRANK \
           $TMPOUT/${time}/topo/topo $atime ${name_m[$m]} $(printf '%04d' $m) $TMPRUN/letkf
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[5]}: $it: Pre-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

letkf_2 () {
#-------------------------------------------------------------------------------

#echo
#echo "* Post-processing scripts"
#echo

for it in $(seq $nitmax); do
  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[5]}: $it: Post-processing script (member) start" >&2
  fi

  g=${proc2group[$((MYRANK+1))]}
  m=$(((it-1)*parallel_mems+g))
  if ((m >= 1 && m <= mmean)); then
    if (pdrun $g $PROC_OPT); then
      bash $SCRP_DIR/src/post_letkf.sh $MYRANK \
           $mem_np ${atime} ${name_m[$m]} $(printf '%04d' $m) $TMPRUN/letkf $LOG_OPT
    fi
  fi

  if ((MYRANK == 0)); then
    echo "[$(datetime_now)] ${time}: ${stepname[5]}: $it: Post-processing script (member) end" >&2
  fi
done

#-------------------------------------------------------------------------------
}

#===============================================================================

obstime () {
#-------------------------------------------------------------------------------
# Determine the observation time slots
#  *Require source 'func_datetime.sh'
#
# Usage: obstime TIME
#
#   TIME  Forecast start time
#
# Other input variables:
#   $LTIMESLOT
#   $WINDOW_S
#   $WINDOW_E
#   $LCYCLE
#
# Return variables:
#   $slot_s
#   $slot_e
#   $slot_b
#   $time_sl[1...$slot_e]
#   $timefmt_sl[1...$slot_e]
#-------------------------------------------------------------------------------

if (($# < 1)); then
  echo "[Error] $FUNCNAME: Insufficient arguments." >&2
  exit 1
fi

local TIME="$1"

#-------------------------------------------------------------------------------

  local otime=$(datetime $TIME)               # HISTORY_OUTPUT_STEP0 = .true.,
#  local otime=$(datetime $TIME $LTIMESLOT s)  # HISTORY_OUTPUT_STEP0 = .false.,
  local is=0
  slot_s=0
  while ((otime <= $(datetime $TIME $WINDOW_E s))); do
    is=$((is+1))
    time_sl[$is]=$otime
    timefmt_sl[$is]="$(datetime_fmt ${otime})"
    if ((slot_s == 0 && otime >= $(datetime $TIME $WINDOW_S s))); then
      slot_s=$is
    fi
    if ((otime == $(datetime $TIME $LCYCLE s))); then # $(datetime $TIME $LCYCLE,$WINDOW_S,$WINDOW_E,... s) as a variable
      slot_b=$is
    fi
  otime=$(datetime $otime $LTIMESLOT s)
  done
  slot_e=$is

#-------------------------------------------------------------------------------
}

#===============================================================================
