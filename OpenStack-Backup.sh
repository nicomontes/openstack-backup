#/bin/bash

# Variables
glance_config="./glanceBackup.config"
admin_user=$(cat $glance_config | grep "^admin_username" | grep -E -o "[^=]*$" | head -1)
admin_pass=$(cat $glance_config | grep "^admin_password" | grep -E -o "[^=]*$" | head -1)
admin_tenant_ID=$(cat $glance_config | grep "^admin_tenantId" | grep -E -o "[^=]*$" | head -1)
API_endpoint_keystone=$(cat $glance_config | grep "^api_endpoint_identity_service" | grep -E -o "[^=]*$" | head -1)
API_endpoint_compute=$(cat $glance_config | grep "^api_endpoint_compute_service" | grep -E -o "[^=]*$" | head -1)
backup_list=$(cat $glance_config | grep -E "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}$")
glance_images_folder=$(cat $glance_config | grep "^glance_images_folder" | grep -E -o "[^=]*$" | head -1)
sources_file=$(cat $glance_config | grep "^sources_file" | grep -E -o "[^=]*$" | head -1)

# Get token (Admin account for all access)
token=$(curl -k -X 'POST' $API_endpoint_keystone/tokens \
-d '{"auth":{"passwordCredentials":{"username": "'$admin_user'", "password": "'$admin_pass'"}, "tenantId": "'$admin_tenant_ID'"}}' \
-H 'Content-type: application/json'|grep -E -o '[A-Za-z0-9\+\-]{100,}')

# Launch Backup for each VM
for line in $(echo $backup_list)
do
  backup_name=$(echo $line | cut -f1 -d ";" | grep -E -o "[A-Za-z0-9]*")
  backup_type=$(echo $line | cut -f2 -d ";" | grep -E -o "[A-Za-z0-9]*")
  backup_rotation=$(echo $line | cut -f3 -d ";" | grep -E -o "[0-9]*")
  backup_id=$(echo $line | cut -f4 -d ";" | grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
  curl -d '{"createBackup": {"name": "'$backup_name'","backup_type": "'$backup_type'","rotation": '$backup_rotation'}}' \
  -H "X-Auth-Token: $token " \
  -H "Content-type: application/json" $API_endpoint_compute/servers/$backup_id/action
done

echo "API Requested"

# Sources for Glance commands
source $sources_file 
echo "Sources Imported" 

# New Backup ID
new_backup_ID=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued"|grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
echo "New Backup : "$new_backup_ID

# Sleep when Create Backup Process
VM_queued=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued" | wc -c)
while [ $VM_queued -gt 0 ]
do
  sleep 5
  VM_queued=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued" | wc -c)
done
echo "Backup Queued"

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
    echo "VM : "$VM_ID" check in /glance/images/ ERROR"
  else
    rm -f $HOME/VMBackup/$VM_ID
    echo "VM : "$VM_ID" Copied"
  fi
done

# Delete Old VM in CopyFolder
for VM_ID in $(ls $HOME/VMBackup/|grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
do
  ls $glance_images_folder$VM_ID $1>/dev/null
  if [[ $(echo $?) -gt 0 ]]
  then
    echo "VM : "$VM_ID" aren't in Glance images folder"
    rm -f $HOME/VMBackup/$VM_ID
    echo "VM : "$VM_ID" Removed"
  fi
done

# Log in Syslog File
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Openstack_Backup: Backup Finished" >> /var/log/syslog