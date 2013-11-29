#/bin/bash

# Configure Config File
glance_config="/home/satin/openstack-backup/glanceBackup.config"

# Get Log
log=$(cat $glance_config | grep "^log" | grep -E -o "[^=]*$" | head -1)

# Get Latest Version
cd /home/satin/openstack-backup/
git_pull=$(git pull)
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: Start with Git Pull : $git_pull" >> $log

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
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: token GET" >> $log

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
done

# Launch Backup for each VM
echo "backup list : $backup_list" >> $log
for line in $backup_list
do
  backup_name=$(echo $line | cut -f1 -d ";" | grep -E -o "[A-Za-z0-9]*")
  backup_type=$(echo $line | cut -f2 -d ";" | grep -E -o "[A-Za-z0-9]*")
  backup_rotation=$(echo $line | cut -f3 -d ";" | grep -E -o "[0-9]*")
  backup_id=$(echo $line | cut -f4 -d ";" | grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
  curl -s -d '{"createBackup": {"name": "'$backup_name'","backup_type": "'$backup_type'","rotation": '$backup_rotation'}}' \
  -H "X-Auth-Token: $token " \
  -H "Content-type: application/json" $API_endpoint_compute/servers/$backup_id/action
  echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: VM : $backup_name : $backup_id : sendbackup on API" >> $log
  sleep 5
done
sleep 5

# Sleep when Create Backup Process
VM_queued=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued" | wc -c)
while [ $VM_queued -gt 0 ]
do
  sleep 5
  VM_queued=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued" | wc -c)
done

# Sleep when Saving Backup Process
VM_saving=$(glance image-list|grep -E -o ".*BackupAutoScript.*saving" | wc -c)
while [ $VM_saving -gt 0 ]
do
  sleep 5
  VM_saving=$(glance image-list|grep -E -o ".*BackupAutoScript.*saving" | wc -c)
done
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: Backup Saved" >> $log

sleep 10

# New Backup ID
# Exec regex for match all NEW backup ID
new_backup_list=$(nova image-list | grep -E "$regex_list" | cut -f2 -d "|" | grep -o "[^\ ]*")
echo "New Backup :" $new_backup_list >> $log
# Read Arry
i_max=$(echo $new_backup_list | wc -w)
for ((i = 0; i < $i_max; i += 1))
do
  for line in $new_backup_list
  do
    # IF new Backup is in last backup list THEN add in regex
    if [ "$line" = "${last_backup[$i]}" ]
    then
      regex_match_new_backup=$(echo "$regex_match_new_backup$line|")
    fi
  done
done
regex_match_new_backup=$(echo $regex_match_new_backup | sed "s/.$//")
# Match Regex (Same Backup ID) and we invert with -v
last_backup=$(echo "$new_backup_list" | grep -E -v $regex_match_new_backup)

# Copy VM
for VM_ID in $last_backup
do
  cp $glance_images_folder$VM_ID /glance/VMBackup/$VM_ID 
  if [[ $(echo $?) -gt 0 ]]
  then
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: VM : $VM_ID check in /glance/images/ ERROR">> $log

  else
    rm -f $$VM_ID
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: VM : $VM_ID Copied">> $log 
  fi
done

# Delete Old VM in CopyFolder
for VM_ID in $(ls $glance_images_backup|grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
do
  ls $glance_images_folder$VM_ID 2>/dev/null
  if [[ $(echo $?) -gt 0 ]]
  then
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: VM : $VM_ID aren't in Glance images folder">> $log
    rm -f $glance_images_backup$VM_ID
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: $VM_ID Removed" >> $log
  fi
done

# Log in Syslog File
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: Backup Finished" >> $log
