#!/bin/bash

# Configure Config File
glance_config="/home/satin/openstack-backup/glanceBackup.config"

# Get Log
log=$(cat $glance_config | grep "^log" | grep -E -o "[^=]*$" | head -1)

# Variables
admin_user=$(cat $glance_config | grep "^admin_username" | grep -E -o "[^=]*$" | head -1)
admin_pass=$(cat $glance_config | grep "^admin_password" | grep -E -o "[^=]*$" | head -1)
admin_tenant_ID=$(cat $glance_config | grep "^admin_tenantId" | grep -E -o "[^=]*$" | head -1)
API_endpoint_keystone=$(cat $glance_config | grep "^api_endpoint_identity_service" | grep -E -o "[^=]*$" | head -1)
API_endpoint_compute=$(cat $glance_config | grep "^api_endpoint_compute_service" | grep -E -o "[^=]*$" | head -1)
backup_list=$(cat $glance_config | grep -E "^[^\ #].*[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}$")
glance_images_folder=$(cat $glance_config | grep "^glance_images_folder" | grep -E -o "[^=]*$" | head -1)
glance_images_backup=$(cat $glance_config | grep "^glance_images_backup" | grep -E -o "[^=]*$" | head -1)
sources_file=$(cat $glance_config | grep "^sources_file" | grep -E -o "[^=]*$" | head -1)

# Sources for Glance commands
source $sources_file

# Get token (Admin account for all access)
token=$(curl -s -k -X 'POST' $API_endpoint_keystone/tokens \
-d '{"auth":{"passwordCredentials":{"username": "'$admin_user'", "password": "'$admin_pass'"}, "tenantId": "'$admin_tenant_ID'"}}' \
-H 'Content-type: application/json'|grep -E -o '[A-Za-z0-9\+\-]{100,}')
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: token GET" >> $log

# Last Backup ID
for line in $backup_list
do
  backup_name=$(echo $line | cut -f1 -d ";" | grep -E -o "[A-Za-z0-9]*")
  # create regex for match all Backup ID
  regex_list="$regex_list $backup_name |"
done
regex_list=$(echo $regex_list | sed "s/.$//")
# Exec regex for match all Backup IP
last_backup_list=$(nova image-list | grep -E "$regex_list" | cut -f2 -d "|" | grep -o "[^\ ]*")
# Push in array all backup ID
for line in $last_backup_list
do
  last_backup[${#last_backup[*]}]=$line
	echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Last Backup : $line" >> $log
done

# Launch Backup for each VM
for line in $backup_list
do
  backup_name=$(echo $line | cut -f1 -d ";" | grep -E -o "[A-Za-z0-9]*")
  backup_type=$(echo $line | cut -f2 -d ";" | grep -E -o "[A-Za-z0-9]*")
  backup_rotation=$(echo $line | cut -f3 -d ";" | grep -E -o "[0-9]*")
  server_id=$(echo $line | cut -f4 -d ";" | grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
  # Send Backup
  curl -s -d '{"createBackup": {"name": "'$backup_name'","backup_type": "'$backup_type'","rotation": '$backup_rotation'}}' \
    -H "X-Auth-Token: $token " \
    -H "Content-type: application/json" $API_endpoint_compute/servers/$server_id/action
  echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: VM : $backup_name : $server_id : sendbackup on API" >> $log
  sleep 5
done
sleep 5

# Sleep when Create Backup Process
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Sleep when Create Backup Process" >> $log
VM_queued=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued" | wc -c)
i=0
while [ $VM_queued -gt 0 ]
do
  sleep 5
  VM_queued=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued" | wc -c)
	i=$(($i+1))
	if [[ $i -gt 360 ]]
	then
		for id in $(glance image-list|grep -E -o ".*BackupAutoScript.*queued"|cut -f2 -d"|"|grep -E -o "[0-9a-z\-]*")
		do
			echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Backup $id : Timeout" >> $log
			glance image-delete $id
			echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Backup $id : Delete Request Sent" >> $log
		done
	fi
done
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Backup Process Finished" >> $log

# Sleep when Saving Backup Process
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Sleep when Saving Backup Process" >> $log
VM_saving=$(glance image-list|grep -E -o ".*BackupAutoScript.*saving" | wc -c)
while [ $VM_saving -gt 0 ]
do
  sleep 5
  VM_saving=$(glance image-list|grep -E -o ".*BackupAutoScript.*saving" | wc -c)
done
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Backup Saved" >> $log
sleep 10
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Saving Process Finished" >> $log

# New Backup ID
# Exec regex for match all NEW backup ID
new_backup_list=$(nova image-list | grep -E "$regex_list" | cut -f2 -d "|" | grep -o "[^\ ]*")
# Read Array
i_max=$(echo $new_backup_list | wc -w)
for ((i = 0; i < $i_max; i += 1))
do
  for line in $new_backup_list
  do
    # IF new Backup is in last backup list THEN add in regex
    if [[ "$line" = "${last_backup[$i]}" ]]
    then
      regex_match_new_backup=$(echo "$regex_match_new_backup$line|")
    fi
  done
done
regex_match_new_backup=$(echo $regex_match_new_backup | sed "s/.$//")
# Match Regex (Same Backup ID) and we invert with -v
last_backup=$(echo "$new_backup_list" | grep -E -v $regex_match_new_backup)

# Copy VM Backup
for Backup_ID in $last_backup
do
  cp $glance_images_folder$Backup_ID /glance/VMBackup/$Backup_ID
  echo=$(echo $?)
  if [[ $echo -gt 0 ]]
  then
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Backup : $Backup_ID check in /glance/images/ ERROR $echo">> $log
		echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Backup : Command cp $glance_images_folder$Backup_ID /glance/VMBackup/$Backup_ID">> $log
  else
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Backup : $Backup_ID Copied">> $log
  fi
done

# Delete Old VM in CopyFolder
for Backup_ID in $(ls $glance_images_backup|grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
do
  ls $glance_images_folder$Backup_ID 2>/dev/null 1>/dev/null
  echo=$(echo $?)
  if [[ $echo -gt 0 ]]
  then
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Backup : $Backup_ID aren't in Glance images folder">> $log
    rm -f $glance_images_backup$Backup_ID
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: $Backup_ID Removed" >> $log
  fi
done

# Soft Rebbot VM Backup Fail (shutoff)
for line in $backup_list
do
	server_id=$(echo $line | cut -f4 -d ";" | grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
	status=$(nova show $server_id | grep -E "status"|cut -f3 -d"|"|grep -E -o "[A-Z]*")
	if [[ $status != "ACTIVE" ]]
	then
		nova reboot $server_id
		echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: VM : $server_id : ERROR, REBOOT Sent" >> $log
	fi
done

# Reset State when task is stay on backup
for line in $backup_list
do
  server_id=$(echo $line | cut -f4 -d ";" | grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
  status=$(nova show $server_id | grep -E "task_state"|cut -f3 -d"|"|grep -E -o "[a-z_]*")
  if [[ $status == "image_backup" ]]
  then
    nova reset-state --active $server_id
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: VM : $server_id : Backup task stay, nova reset-state Sent" >> $log
  fi
done

# Log in Syslog File
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup[$$]: Backup Finished" >> $log
