# setup docker

# packages to install
sudo apt update; sudo DEBIAN_FRONTEND=noninteractive apt install build-essential btop \
lazygit git-gui git-lfs mtr-tiny wireshark meld telnet tcpdump valgrind strace gdb minicom \
starship ca-certificates curl gimp docker-ce docker-ce-cli containerd.io docker-buildx-plugin \
docker-compose-plugin -yq

curl -o /tmp/docker-desktop-amd64.deb https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb; sudo apt install -f /tmp/docker-desktop-amd64.deb -y
echo 'eval "$(starship init bash)"' >> ~/.bashrc
source ~/.bashrc
