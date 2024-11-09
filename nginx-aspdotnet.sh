rg=ngnix-aspdotnet
location=centralindia

spoke1_vnet_name=spoke1
spoke1_vnet_address=10.11.0.0/16
spoke1_vm_subnet_name=vm
spoke1_vm_subnet_address=10.11.0.0/24

admin_username=$(whoami)
admin_password=Test#123#123
vm_size=Standard_B2ats_v2
vm_image=$(az vm image list -l $location -p Canonical -s 22_04-lts --all --query "[?offer=='0001-com-ubuntu-server-jammy'].urn" -o tsv | sort -u | tail -n 1) && echo $vm_image

cloudinit_file=~/cloudinit.txt
cat <<EOF > $cloudinit_file
#cloud-config
runcmd:
  - apt update && apt-get install -y dotnet-sdk-8.0 nginx git
  - mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
  - cd /etc/nginx/sites-available/ && curl -O https://raw.githubusercontent.com/wshamroukh/nginx-aspdotnet/refs/heads/main/default
  - git clone https://github.com/jelledruyts/InspectorGadget /var/www/InspectorGadget
  - mv /var/www/InspectorGadget/WebApp /var/www/ && rm -rf /var/www/InspectorGadget
  - cd /etc/systemd/system/ && curl -O https://raw.githubusercontent.com/wshamroukh/nginx-aspdotnet/refs/heads/main/inspectorg.service
  - systemctl enable inspectorg && systemctl start inspectorg
  - nginx -t && nginx -s reload
  - reboot
EOF

# Resource Groups
echo -e "\e[1;36mCreating $rg Resource Group...\e[0m"
az group create -l $location -n $rg -o none

# spoke1 vnet
echo -e "\e[1;36mCreating $spoke1_vnet_name VNet...\e[0m"
az network vnet create -g $rg -n $spoke1_vnet_name -l $location --address-prefixes $spoke1_vnet_address --subnet-name $spoke1_vm_subnet_name --subnet-prefixes $spoke1_vm_subnet_address -o none

# spoke1 vm
echo -e "\e[1;36mDeploying $spoke1_vnet_name VM...\e[0m"
az network public-ip create -g $rg -n $spoke1_vnet_name --sku basic --allocation-method Static -o none
az network nic create -g $rg -n $spoke1_vnet_name -l $location --vnet-name $spoke1_vnet_name --subnet $spoke1_vm_subnet_name --public-ip-address $spoke1_vnet_name -o none
az vm create -g $rg -n $spoke1_vnet_name -l $location --image $vm_image --nics $spoke1_vnet_name --os-disk-name $spoke1_vnet_name --size $vm_size --admin-username $admin_username --admin-password $admin_password --custom-data $cloudinit_file
spoke1_vm_ip=$(az network nic show -g $rg -n $spoke1_vnet_name --query ipConfigurations[0].privateIPAddress -o tsv) && echo $spoke1_vnet_name vm private ip: $spoke1_vm_ip
spoke1_vm_pip=$(az network public-ip show -g $rg -n $spoke1_vnet_name --query ipAddress -o tsv) && echo VM public IP: $spoke1_vm_pip
rm $cloudinit_file

# vm boot diagnostics
echo -e "\e[1;36mEnabling VM boot diagnostics for $spoke1_vnet_name...\e[0m"
az vm boot-diagnostics enable -g $rg -n $spoke1_vnet_name -o none

echo try to access the website after 2 minutes: http://$spoke1_vm_pip
