sudo apt-get update -y
sudo apt-get install -y git
if [[ ! -f ubuntu-unattended ]]; then
  git clone https://github.com/fingul/ubuntu-unattended.git
fi
cd ubuntu-unattended
sudo username=m password=m ./create-unattended-iso.sh
cp /tmp/*unattended.iso /vagrant
