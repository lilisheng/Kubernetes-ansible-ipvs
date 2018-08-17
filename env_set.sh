#/bin/bash
set -e

[ `id -u` != '0' ] && \
    { echo -e '\e[32;1m Please run the script as root!!! \e[0m'
      exit 1; }

[ `grep -Po 'CentOS.+release \K\d' /etc/redhat-release` == 7 ] || { echo 'not support this os';exit 2; }

[[ `yum repolist` =~ '!epel/' ]]  || yum install -y epel-release
[[ `rpm -qa` =~ openssl ]] || yum install -y openssl

systemctl disable --now firewalld
systemctl disable --now NetworkManager

#disabled the selinux
setenforce 0
sed -ri '/^[^#]*SELINUX=/s#=.+$#=disabled#' /etc/selinux/config

mkdir -p /etc/docker/
cat>/etc/docker/daemon.json<<EOF
{
"registry-mirrors": ["https://fz5yth0r.mirror.aliyuncs.com"]
}
EOF
yum install -y epel-release bash-completion
\cp /usr/share/bash-completion/completions/docker /etc/bash_completion.d/
systemctl enable --now docker

[ -f '/etc/sysctl.d/k8s.conf' ] && mv /etc/sysctl.d/{,old_}k8s.conf

# set the Kernel forwarding
{
sysctl -a |& grep -wq 'net.ipv4.ip_forward = 1' || echo 'net.ipv4.ip_forward = 1'
sysctl -a |& grep -wq 'net.bridge.bridge-nf-call-ip6tables = 1' || echo 'net.bridge.bridge-nf-call-ip6tables = 1'
sysctl -a |& grep -wq 'net.bridge.bridge-nf-call-iptables = 1' || echo 'net.bridge.bridge-nf-call-iptables = 1'
sysctl -a |& grep -wq 'fs.may_detach_mounts = 1' || echo 'fs.may_detach_mounts = 1'
} > /etc/sysctl.d/k8s.conf
[ ! -s '/etc/sysctl.d/k8s.conf' ] && /bin/rm -f  /etc/sysctl.d/k8s.conf || sysctl -p /etc/sysctl.d/k8s.conf

#turn off the swap
swapoff -a && sysctl -w vm.swappiness=0
sed -ri '/^[^#]*swap/s@^@#@' /etc/fstab

# ipvs
yum install ipvsadm -y
:> /etc/modules-load.d/ipvs.conf
module=(
  ip_vs
  ip_vs_lc
  ip_vs_wlc
  ip_vs_rr
  ip_vs_wrr
  ip_vs_lblc
  ip_vs_lblcr
  ip_vs_dh
  ip_vs_sh
  ip_vs_fo
  ip_vs_nq
  ip_vs_sed
  ip_vs_ftp
  )
for kernel_module in ${module[@]};do
    /sbin/modinfo -F filename $kernel_module |& grep -qv ERROR && echo $kernel_module >> /etc/modules-load.d/ipvs.conf || :
done
systemctl enable --now systemd-modules-load.service
