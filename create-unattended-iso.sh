#!/usr/bin/env bash

# file names & paths
tmp="${tmp:-/tmp}"  # destination folder to store the final iso file
hostname="${hostname:-ubuntu.alpha.omega}"
timezone="${timezone:-Asia/Seoul}"
username="${username:-username}"
password="${password:-password}"
mirror="${mirror:-ftp.daumkakao.com}"
download="${download:-http://ftp.daumkakao.com/ubuntu-releases/}"
download_file="ubuntu-14.04.4-server-amd64.iso"             # filename of the iso to be downloaded
download_location="http://ftp.daumkakao.com/ubuntu-releases/14.04/"     # location of the file to be downloaded
new_iso_name="${download_file}.unattended.iso"   # filename of the new iso file to be created
autostart=true
seed_file="/vagrant/guided-lvm.seed"
seed_file_name="myfile.seed"
dir_iso="/vagrant"
outfile="/vagrant/$new_iso_name"

rm -rf $outfile

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

# print a pretty header
echo
echo " +---------------------------------------------------+"
echo " |            UNATTENDED UBUNTU ISO MAKER            |"
echo " +---------------------------------------------------+"
echo

if [ ${UID} -ne 0 ]; then
    echo " [-] This script must be runned with root privileges."
    echo " [-] sudo ${0}"
    echo
    exit 1
fi


echo "check dir $dir_iso/$download_file"
# download the ubunto iso
if [[ ! -f $dir_iso/$download_file ]]; then
    todown="$download_location$download_file"
    echo download "$todown to $dir_iso/$download_file"
    wget -nv -O $dir_iso/$download_file $todown
fi

cd $tmp

# install required packages
echo " installing required packages"
if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
    apt-get -y update
    apt-get -y install whois genisoimage

    # thanks to rroethof
    if [ -f /usr/bin/mkisofs ]; then
      ln -s /usr/bin/genisoimage /usr/bin/mkisofs
    fi
fi

# create working folders
echo " remastering your iso file"
mkdir -p $tmp
mkdir -p $tmp/iso_org
mkdir -p $tmp/iso_new


# mount the image
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    cp $dir_iso/$download_file /tmp/0.iso
    mount -o loop /tmp/0.iso $tmp/iso_org
fi

# copy the iso contents to the working directory
cp -rT $tmp/iso_org $tmp/iso_new

# set the language for the installation menu
cd $tmp/iso_new
echo en > $tmp/iso_new/isolinux/lang

# set timeout to 1 decisecond to skip language & boot menu option selection.
if $autostart ; then
    sed -i "s/timeout 0/timeout 1/" $tmp/iso_new/isolinux/isolinux.cfg
fi

# set late command
#late_command="chroot /target wget -O /home/$username/init.sh $github_repo/init.sh ;\
#    chroot /target chmod +x /home/$username/init.sh ;"

# copy the netson seed file to the iso
cp -rT $seed_file $tmp/iso_new/preseed/$seed_file_name

# include firstrun script
#echo "
## setup firstrun script
#d-i preseed/late_command                                    string      $late_command" >> $tmp/iso_new/preseed/$seed_file

# generate the password hash
pwhash=$(echo $password | mkpasswd -s -m sha-512)

# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" $tmp/iso_new/preseed/$seed_file_name
sed -i "s@{{pwhash}}@$pwhash@g" $tmp/iso_new/preseed/$seed_file_name
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso_new/preseed/$seed_file_name
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso_new/preseed/$seed_file_name
sed -i "s@{{mirror}}@$mirror@g" $tmp/iso_new/preseed/$seed_file_name


# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file_name)

# add the autoinstall option to the menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Unattended Ubuntu Server Install\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server-minimalvm.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/${seed_file_name} preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg

echo " creating the remastered iso"
cd $tmp/iso_new
mkisofs -D -r -V "Ubuntu server" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $outfile .

# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $outfile"
echo " your username is: $username"
echo " your password is: $password"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo


# cleanup
umount $tmp/iso_org
rm -rf $tmp/iso_new
rm -rf $tmp/iso_org
