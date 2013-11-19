#/bin/bash

# Get token (Admin account for all access)
token=$(curl -k -X 'POST' http://161.3.200.2:5000/v2.0/tokens \
-d '{"auth":{"passwordCredentials":{"username": "admin", "password":"admin_pass"}, "tenantId":"ac331507c10142f0a1a8cd881ccae3d1"}}' \
-H 'Content-type: application/json'|grep -E -o '[A-Za-z0-9\+\-]{100,}')

# Number of Backup

# Launch Backup for each VM
curl -d '{"createBackup": {"name": "DockerBackupAutoScript","backup_type": "daily","rotation": 2}}' \
-H "X-Auth-Token: $token " \
-H "Content-type: application/json" http://161.3.200.2:8774/v2/ac331507c10142f0a1a8cd881ccae3d1/servers/7364d36d-6f12-4e9d-8533-a0f43b64ba06/action

curl -d '{"createBackup": {"name": "LDAPBackupAutoScript","backup_type": "daily","rotation": 2}}' \
-H "X-Auth-Token: $token " \
-H "Content-type: application/json" http://161.3.200.2:8774/v2/ac331507c10142f0a1a8cd881ccae3d1/servers/6d50e386-4148-4048-aa07-c799f767c341/action

curl -d '{"createBackup": {"name": "DNSBackupAutoScript","backup_type": "daily","rotation": 2}}' \
-H "X-Auth-Token: $token " \
-H "Content-type: application/json" http://161.3.200.2:8774/v2/ac331507c10142f0a1a8cd881ccae3d1/servers/7af130a4-43c7-4ed5-be3b-0760f99472d7/action

echo "API Requested"

# Sources for Glance commands
source /home/satin/sources
echo "Sources Imported" 

# New Backup ID
NewBackupID=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued"|grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
echo "New Backup : "$NewBackupID

# Sleep when Create Backup Process
VMQueued=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued" | wc -c)
while [ $VMQueued -gt 0 ]
do
  sleep 5
  VMQueued=$(glance image-list|grep -E -o ".*BackupAutoScript.*queued" | wc -c)
done
echo "Backup Queued"

# Sleep when Saving Backup Process
VMSaving=$(glance image-list|grep -E -o ".*BackupAutoScript.*saving" | wc -c)
while [ $VMSaving -gt 0 ]
do
  sleep 5
  VMSaving=$(glance image-list|grep -E -o ".*BackupAutoScript.*saving" | wc -c)
done
echo "Backup Saved"

# Copie VM
for VMID in $NewBackupID
do
  cp /glance/images/$VMID $HOME/VMBackup/
  echo "VM : "$VMID" Copied"
done

# Delete Old VM in CopieFolder
for VMID in $(ls $HOME/VMBackup/|grep -E -o "[a-z0-9]{8}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{4}\-[a-z0-9]{12}")
do
  ls /glance/images/$VMID $1>/dev/null
  if [[ $(echo $?) -gt 0 ]]
  then
    rm -f $HOME/VMBackup/$VMID
    echo "VM : "$VMID" Removed"
  fi
done

# Log in Syslog File
echo "$(date +"%h %d %H:%M:%S") $HOSTNAME Backup_Openstack: Backup Finished" >> /var/log/syslog