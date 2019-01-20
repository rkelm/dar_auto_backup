#!/bin/ash
# dar_backup.sh <basename> <full_interval> <full_diff_interval>
#

# *** Load Configuration
source dar_backup.conf

# Load aws credentials.
if test -n "$aws_credentials" ; then
  . "$aws_credentials"
fi 

# Use locally installed dar library.
export LD_LIBRARY_PATH="/usr/local/lib"

set -o pipefail

# *** Subroutines.
show_usage () {
  echo "usage: dar_backup.sh <basename> <backup_root_path> <full_interval> <full_diff_interval> [no_validate] [upload]"
  echo "<basename> base name for naming of backup files."
  echo "<backup_root_path> path to source directory"  
  echo "Time interval for full backup <full_interval> = <Integer>D|W|M|Y"
  echo "Time interval for diff to full backup <full_diff_interval> = = <Integer>D|W|M|Y"
  echo "default is to validate backup, use no_validate option to skip validation"
  echo "upload to glacier vault optional"
}

error_exit () {
  if test -z $1 ; then
    exit 1
  else
    exit $1
  fi;
}

# *** Check command line parameters. ***
base_name=$1
backup_root=$2
full_interval=$3
full_diff_interval=$4

if test -z "$base_name" -o -z "$full_interval" || test -z "$full_diff_interval" ; then
   show_usage
   error_exit 1
fi

if test ! -d "$backup_root" ; then
  echo "Directory $backup_root not found."
  show_usage
  error_exit 1
fi

echo `date -Iseconds` Running `basename $0` for $base_name 
echo Using full Interval $full_interval and full_diff interval $full_diff_interval
echo Backed up directory is "$backup_root"

if test "$5" = "upload"  -o "$6" = "upload" ; then
  do_upload="upload"
  echo "Upload option set"
else
  unset do_upload
  echo "No upload option"
fi

if test "$5" = "no_validate" -o "$6" = "no_validate" ; then
   unset do_validate
   echo "no_validate option set" 
else 
  do_validate="validate"
  echo "No no_validate option"
fi

# *** Lock file to prevent parallel execution ***
lockfile="/var/run/dar_backup"
exec 200>$lockfile 
flock -n 200 || (echo "Cannot get exclusive lock on lock file $lockfile" && error_exit 1)
pid=$$
echo $pid 1>&200


# *** Prepare constants. ***
today_date=`date -I`
today_year=`echo $today_date | cut -d \- -f  1`
today_month=`echo $today_date | cut -d \- -f  2`
today_day=`echo $today_date | cut -d \- -f  3`
today_days_since=`expr \`date +%s\` \/ 24 \/ 60 \/ 60`
#echo $today_date = $today_days_since

echo `date -Iseconds` Searching for last dar backup set.
last_full_base_name=`ls -1 -r "${slices_dir}/${base_name}" | grep -E ".dar$" | grep $full_suffix | grep -v $diff_suffix | head -n 1 | cut -d . -f 1`
if test -n "$last_full_base_name" ; then 
	last_full_base_name=${slices_dir}/${base_name}/${last_full_base_name}
	dt_tmp=`echo $last_full_base_name | grep -Eo "20[0123456789][0123456789]-[0123456789][0123456789]\-([0123456789][0123456789])${full_suffix}\$" | cut -d _ -f 1`
	last_full_year=`echo $dt_tmp | cut -d \- -f  1`
	last_full_month=`echo $dt_tmp | cut -d \- -f  2`
	last_full_day=`echo $dt_tmp | cut -d \- -f  3`
	last_full_days_since=`expr \`date -d "$dt_tmp 00:00" +%s\` \/ 24 \/ 60 \/ 60`
else
	last_full_year=0
	last_full_month=0
	last_full_day=0
	last_full_days_since=0
fi
# echo $dt_tmp = $last_full_days_since

new_full_base_name=${slices_dir}/${base_name}/${base_name}_${today_date}${full_suffix}

last_full_diff_base_name=`ls -1 -r "${slices_dir}/${base_name}" | grep -E ".dar$" | grep $diff_suffix | grep $full_suffix | head -n 1 | cut -d . -f 1`
if test -n "$last_full_diff_base_name" ; then 
	last_full_diff_base_name=${slices_dir}/${base_name}/${last_full_diff_base_name}
	dt_tmp=`echo $last_full_diff_base_name | grep -Eo "20[0123456789][0123456789]-[0123456789][0123456789]\-([0123456789][0123456789])${full_suffix}${diff_suffix}\$" | cut -d _ -f 1`
	last_full_diff_year=`echo $dt_tmp | cut -d \- -f  1`
	last_full_diff_month=`echo $dt_tmp | cut -d \- -f  2`
	last_full_diff_day=`echo $dt_tmp | cut -d \- -f  3`
	last_full_diff_days_since=`expr \`date -d "$dt_tmp 00:00" +%s\` \/ 24 \/ 60 \/ 60`
else
	last_full_diff_year=0
	last_full_diff_month=0
	last_full_diff_day=0
	last_full_diff_days_since=0
fi
new_full_diff_base_name=${slices_dir}/${base_name}/${base_name}_${today_date}${full_suffix}${diff_suffix}

# Last diff, either diff_diff or full_diff.
last_diff_base_name=${slices_dir}/${base_name}/`ls -1 -r "$slices_dir/${base_name}" | grep -E ".dar$" | grep $diff_suffix | head -n 1 | cut -d . -f 1`
new_diff_diff_base_name=${slices_dir}/${base_name}/${base_name}_${today_date}${diff_suffix}${diff_suffix}

full_interval_num=`echo $full_interval | grep -Eo '^[0123456789]{1,}'`
full_interval_unit=`echo $full_interval | grep -Eo '[mMwWdDyY]{1,1}$'`

# Convert yearly or weekly intervals to monthly or daily.
if test "$full_interval_unit" = 'y' -o "$full_interval_unit" = 'Y' ; then
	full_interval_num=`expr $full_interval_num \* 12`
	full_interval_unit=m
elif test "$full_interval_unit" = 'w' -o "$full_interval_unit" = 'W' ; then
	full_interval_num=`expr $full_interval_num \* 7`
	full_interval_unit=d
fi

full_diff_interval_num=`echo $full_diff_interval | grep -Eo '^[0123456789]{1,}'`
full_diff_interval_unit=`echo $full_diff_interval | grep -Eo '[mMwWdDyY]{1,1}$'`

# Convert yearly or weekly intervals to monthly or daily.
if test "$full_diff_interval_unit" = 'y' -o "$full_diff_interval_unit" = 'Y' ; then
	full_diff_interval_num=`expr $full_diff_interval_num \* 12`
	full_diff_interval_unit=m
elif test "$full_diff_interval_unit" = 'w' -o "$full_diff_interval_unit" = 'W' ; then
	full_diff_interval_num=`expr $full_diff_interval_num \* 7`
	full_diff_interval_unit=d
fi

# *** Which backup type needs to be done? ***
# Check if a full backup needs to be done.
if test "$full_interval_unit" = 'm' -o "$full_interval_unit" = 'M' ; then
	if test -z "$last_full_base_name" \
		-o `expr $last_full_month + $full_interval_num` -lt `expr $today_month + 12 \* \( $today_year - $last_full_year  \)` \
		-o `expr $last_full_month + $full_interval_num` -eq `expr $today_month + 12 \* \( $today_year - $last_full_year  \)` \
			-a "$last_full_day" -le "$today_day" ; then
		backuptype=full
	fi 
elif test "$full_interval_unit" = 'd' -o "$full_interval_unit" = 'D' ; then
	if test -z "$last_full_base_name" -o `expr $last_full_days_since + $full_interval_num` -le $today_days_since ; then
		backuptype=full
	fi 
else
	echo "Unknown full interval unit $full_interval_unit"
	error_exit 1
fi
#echo `expr $last_full_days_since + $full_interval_num ` -le $today_days_since

if test -z $backuptype ; then
# If there is no full backup needed, check if we need a full_diff backup.
	if test "$full_diff_interval_unit" = 'm' -o "$full_diff_interval_unit" = 'M' ; then
		if test -z "$last_full_diff_base_name" \
			-o `expr $last_full_diff_month + $full_diff_interval_num` -lt `expr $today_month + 12 \* \( $today_year - $last_full_diff_year  \)` \
			-o `expr $last_full_diff_month + $full_diff_interval_num` -eq `expr $today_month + 12 \* \( $today_year - $last_full_diff_year  \)` \
				-a "$last_full_diff_day" -le "$today_day" ; then
			backuptype=full_diff
		fi ;
	elif test "$full_diff_interval_unit" = 'd' -o "$full_diff_interval_unit" = 'D' ; then
		if test -z "$last_full_diff_base_name" -o `expr $last_full_diff_days_since + $full_diff_interval_num ` -le $today_days_since ; then
			backuptype=full_diff
		fi ;
	else
	  echo Unknown full_diff interval unit $full_diff_interval_unit
	  error_exit 1
	fi
fi


# If no other backup has been done, then do a diff_diff backup
case "$backuptype" in
	full)
		echo `date -Iseconds` "Creating new full backup $new_full_base_name"
		$dar_binary -c "$new_full_base_name" -R "$backup_root" -B "$dar_config" -B "$dar_key_config" -Q || error_exit 1
		new_base_name="$new_full_base_name"
	;;
	full_diff)
		echo `date -Iseconds` "Creating new diff from full backup $last_full_base_name"
		$dar_binary -c "$new_full_diff_base_name" -A "$last_full_base_name" -R "$backup_root" -B "$dar_config" -B "$dar_key_config" -B "$dar_key_diff_config" -Q || error_exit 1
		new_base_name="$new_full_diff_base_name"
	;;
	*)
		echo `date -Iseconds` "Creating new diff from diff backup $last_diff_base_name"
		$dar_binary -c "$new_diff_diff_base_name" -A "$last_diff_base_name" -R "$backup_root" -B "$dar_config" -B "$dar_key_config" -B "$dar_key_diff_config" -Q || error_exit 1
		new_base_name="$new_diff_diff_base_name"
	;;
esac

status_file_path="${new_base_name}_status"
touch "$status_file_path"

if test -n "$do_validate" ; then
	# Validate archive.
	echo `date -Iseconds` "Validating archive $new_base_name."
	$dar_binary -t "${new_base_name}" -B "$dar_key_config" -Q 
	if test $? -eq 0 ; then
	  echo `date -Iseconds` "Archive is valid."
	  mv -f "${status_file_path}" "${status_file_path}_valid" || error_exit 1
	  status_file_path="${status_file_path}_valid"
	else
	  echo `date -Iseconds` "Archive ist not valid! Aborting..."
	  error_exit 1
	fi
else
	echo `date -Iseconds` "Not validating archive $new_base_name."
fi

# Delete if it is an empty Archive.
echo "Testing for empty archive."

if test 0 -eq `${dar_binary} -l "${new_base_name}" -as -B "${dar_config}" -B "${dar_key_config}" -Q 2> /dev/null | tail -n +4 | wc -l` ; then
  echo `date -Iseconds` "Archive ${new_base_name} is empty. Deleting..."
  rm -f "${new_base_name}.1.dar"
  mv "${status_file_path}" "${status_file_path}_empty-deleted" || error_exit 1
  status_file_path="${status_file_path}_empty-deleted"
else
  # Otherwise mark for upload to glacier vault.
  mv -f "${status_file_path}" "${status_file_path}_ready" || error_exit 1
  status_file_path="${status_file_path}_ready"  

  if test -n "$do_upload" ; then
	# Activate python virtualenv, if configured.
	if test -z "$venv_activate" ; then
		. ${venv_activate}
	fi

	echo `date -Iseconds` "Uploading archive..."
	for i in ${new_base_name}.*.dar ; do
	    archive_id=`env aws_access_key_id="$aws_access_key_id" aws_secret_access_key="$aws_secret_access_key" aws_region_name="$aws_region_name"  "${glacier_cmd}" $base_name "$i" | cut -c22-`
	    retcode=$?
	    if test $retcode -eq 0 ; then
		echo -e `basename ${i}`"\t$archive_id" >> "${slices_dir}/${base_name}/glacier_ids_${base_name}.csv"
		touch "${i}_uploaded"
		echo `date -Iseconds` "Slice $i successfully uploaded."
	    else
		echo `date -Iseconds` "Upload of slice $i failed. Retrying ..."
		sleep 120s
		archive_id=`env aws_access_key_id="$aws_access_key_id" aws_secret_access_key="$aws_secret_access_key" aws_region_name="$aws_region_name" "${glacier_cmd}" $base_name "$i" | cut -c22-`
		retcode=$?
		if test $retcode -eq 0 ; then
			echo -e `basename ${i}`"\t$archive_id" >> "${slices_dir}/${base_name}/glacier_ids_${base_name}.csv"
			touch "${i}_uploaded"
			echo `date -Iseconds` "Slice $i successfully uploaded."
		else
			echo `date -Iseconds` "Upload of slice $i failed. Giving up."
			error_exit 1
		fi
	    fi
	done
        mv -f "${status_file_path}" "${status_file_path}_uploaded" || error_exit 1
	status_file_path="${status_file_path}_uploaded"  
	echo "All slices have been uploaded."
  fi
#  mv -f "${status_file_path}" "${status_file_path}_uploaded" || error_exit 1
#  status_file_path="${status_file_path}_uploaded"  
fi

echo `date -Iseconds` Terminating successfull execution of `basename $0` for $base_name using full interval $full_interval and full_diff interval $full_diff_interval
