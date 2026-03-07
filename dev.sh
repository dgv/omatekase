# setup docker

# packages to install
sudo apt update; sudo DEBIAN_FRONTEND=noninteractive apt install build-essential btop \
lazygit git-gui git-lfs mtr-tiny wireshark meld telnet tcpdump valgrind strace gdb minicom \
starship ca-certificates curl gimp -yq

# Add Docker's official GPG key:
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
curl -fsSL https://bun.com/install | bash
curl -o /tmp/docker-desktop-amd64.deb https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb; sudo apt install -f /tmp/docker-desktop-amd64.deb -y
echo 'eval "$(starship init bash)"' >> ~/.bashrc
source ~/.bashrc
