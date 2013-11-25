#/bin/bash

# Configure Config File
glance_config="/home/satin/openstack-backup/glanceBackup.config"

# Display Date with syslog format
date +"%h %d %H:%M:%S"

# Get Latest Version
script_dir=$(cat $glance_config | grep "^script_dir" | grep -E -o "[^=]*$" | head -1)
cd $script_dir
git pull

# Variables
admin_user=$(cat $glance_config | grep "^admin_username" | grep -E -o "[^=]*$" | head -1)
admin_pass=$(cat $glance_config | grep "^admin_password" | grep -E -o "[^=]*$" | head -1)
admin_tenant_ID=$(cat $glance_config | grep "^admin_tenantId" | grep -E -o "[^=]*$" | head -1)
API_endpoint_keystone=$(cat $glance_config | grep "^api_endpoint_identity_service" | grep -E -o "[^=]*$" | head -1)
API_endpoint_compute=$(cat $glance_config | grep "^api_endpoint_compute_service" | grep -E -o "[^=]*$" | head -1)
backup_list=$(cat $glance_config | grep -E "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}$")
glance_images_folder=$(cat $glance_config | grep "^glance_images_folder" | grep -E -o "[^=]*$" | head -1)
sources_file=$(cat $glance_config | grep "^sources_file" | grep -E -o "[^=]*$" | head -1)

# Get token (Admin account for all access)
token=$(curl -s -k -X 'POST' $API_endpoint_keystone/tokens \
-d '{"auth":{"passwordCredentials":{"username": "'$admin_user'", "password": "'$admin_pass'"}, "tenantId": "'$admin_tenant_ID'"}}' \
-H 'Content-type: application/json'|grep -E -o '[A-Za-z0-9\+\-]{100,}')

# Launch Backup for each VM
for line in $(echo $backup_list)
do
  backup_name=$(echo $line | cut -f1 -d ";" | grep -E -o "[A-Za-z0-9]*")
  backup_type=$(echo $line | cut -f2 -d ";" | grep -E -o "[A-Za-z0-9]*")
  backup_rotation=$(echo $line | cut -f3 -d ";" | grep -E -o "[0-9]*")
  backup_id=$(echo $line | cut -f4 -d ";" | grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
  curl -s -d '{"createBackup": {"name": "'$backup_name'","backup_type": "'$backup_type'","rotation": '$backup_rotation'}}' \
  -H "X-Auth-Token: $token " \
  -H "Content-type: application/json" $API_endpoint_compute/servers/$backup_id/action
done

# Sources for Glance commands
source $sources_file 

# New Backup ID
new_backup_ID=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued"|grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: New Backup : $new_backup_ID">> /var/log/syslog

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
echo "Backup Saved"

# Copy VM
for VM_ID in $new_backup_ID
do
  cp $glance_images_folder$VM_ID $HOME/VMBackup/
  if [[ $(echo $?) -gt 0 ]]
  then
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: VM : $VM_ID check in /glance/images/ ERROR">> /var/log/syslog

  else
    rm -f $HOME/VMBackup/$VM_ID
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: VM : $VM_ID Copied">> /var/log/syslog 
  fi
done

# Delete Old VM in CopyFolder
for VM_ID in $(ls $HOME/VMBackup/|grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
do
  ls $glance_images_folder$VM_ID $1>/dev/null
  if [[ $(echo $?) -gt 0 ]]
  then
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: VM : $VM_ID aren't in Glance images folder">> /var/log/syslog
    rm -f $HOME/VMBackup/$VM_ID
    echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: $VM_ID Removed" >> /var/log/syslog
  fi
done

# Log in Syslog File
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: Backup Finished" >> /var/log/syslog