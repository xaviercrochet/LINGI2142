#!/bin/sh
# qos.sh by neo73 - Last modified december 2007
#
# classes :
# 1 - ping, DNS, ack : super rapide
# 2 - jeux, SSH : haute priorité, stabilité
# 3 - serveurs locaux : un bon débit, temps de réponse acceptable
# 4 - utilisateurs : surf, ftp, msn, ... (classe par défaut)
# 5 - p2p : tout le reste

# Paramètres modifiables

MAX_DL=12000
MAX_DL_BURST=1000
MAX_UP=2000
MAX_UP_BURST=40

AVER_PRIO=200
MAX_PRIO=200

AVER_GAMING=300
MAX_GAMING=300

AVER_SERVERS=200
MAX_SERVERS=1000

AVER_USERS=300
MAX_USERS=1600

AVER_P2P=50
MAX_P2P=800

# séparez les IP des pollueurs de réseau par un espace (désactivé)
#IPS_P2P='192.168.12.9'
#PORTS_P2P='1024:4999'

#WAN=$(nvram get wan_ifname)
WAN=eth0

# Test debug
DEBUG=1
if [ $DEBUG = 1 ]; then
    log=/dev/tty
else
    log=/tmp/qos.log
    rm $log
fi

echo 'Chargement des modules' >> $log 2>> $log
insmod sch_htb >> $log 2>> $log
insmod sch_tbf >> $log 2>> $log
insmod sch_sfq >> $log 2>> $log
insmod cls_u32 >> $log 2>> $log
insmod cls_fw >> $log 2>> $log
insmod sch_ingress >> $log 2>> $log
insmod ipt_connmark >> $log 2>> $log
insmod ipt_CONNMARK >> $log 2>> $log
insmod ipt_ipp2p >> $log 2>> $log

echo 'Suppression des tables' >> $log 2>> $log
tc qdisc del dev $WAN root >> $log 2>> $log
tc qdisc del dev $WAN ingress >> $log 2>> $log

echo '*** Création des classes ***' >> $log 2>> $log

echo 'Création de la racine HTB' >> $log 2>> $log
tc qdisc add dev $WAN root handle 1: htb default 40 >> $log 2>> $log

echo 'Limitation globale du lien' >> $log 2>> $log
tc class add dev $WAN parent 1: classid 1:1 htb \
rate ${MAX_UP}kbit ceil ${MAX_UP}kbit burst ${MAX_UP_BURST}k >> $log 2>> $log

echo 'Classe ping' >> $log 2>> $log
tc class add dev $WAN parent 1:1 classid 1:10 htb \
rate ${AVER_PRIO}kbit ceil ${MAX_PRIO}kbit burst 50k prio 0 >> $log 2>> $log

echo 'Classe jeux' >> $log 2>> $log
tc class add dev $WAN parent 1:1 classid 1:20 htb \
rate ${AVER_GAMING}kbit ceil ${MAX_GAMING}kbit burst 50k prio 1 >> $log 2>> $log

echo 'Classe serveurs' >> $log 2>> $log
tc class add dev $WAN parent 1:1 classid 1:30 htb \
rate ${AVER_SERVERS}kbit ceil ${MAX_SERVERS}kbit burst 50k prio 2 >> $log 2>> $log

echo 'Classe utilisateurs' >> $log 2>> $log
tc class add dev $WAN parent 1:1 classid 1:40 htb \
rate ${AVER_USERS}kbit ceil ${MAX_USERS}kbit burst 2k prio 3 >> $log 2>> $log

echo 'Classe p2p' >> $log 2>> $log
tc class add dev $WAN parent 1:1 classid 1:50 htb \
rate ${AVER_P2P}kbit ceil ${MAX_P2P}kbit burst 5k prio 4 >> $log 2>> $log


echo 'Gestion des classes' >> $log 2>> $log
tc qdisc add dev $WAN parent 1:10 handle 10: sfq perturb 10 >> $log 2>> $log
tc qdisc add dev $WAN parent 1:20 handle 20: sfq perturb 10 >> $log 2>> $log
tc qdisc add dev $WAN parent 1:30 handle 30: sfq perturb 10 >> $log 2>> $log
tc qdisc add dev $WAN parent 1:40 handle 40: sfq perturb 10 >> $log 2>> $log
tc qdisc add dev $WAN parent 1:50 handle 50: sfq perturb 10 >> $log 2>> $log

echo '*** Création des filtres ***' >> $log 2>> $log
# 1 - ICMP, DNS, ACK, GRE
echo 'Classe 1' >> $log 2>> $log
echo ' - ICMP' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 0 \
u32 match ip protocol 1 0xff flowid 1:10 >> $log 2>> $log
echo ' - ACK' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 0 \
u32 match ip protocol 6 0xff \
match u8 0x05 0x0f at 0 \
match u16 0x0000 0xffc0 at 2 \
match u8 0x10 0xff at 33 \
flowid 1:10 >> $log 2>> $log
echo ' - DNS' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 0 \
u32 match ip dport 53 0xff flowid 1:10 >> $log 2>> $log
echo ' - VPN' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 1 u32 \
match ip dport 1723 0xffff flowid 1:10 >> $log 2>> $log

# 2 - Jeux, SSH
echo 'Classe 2' >> $log 2>> $log
# le bit Délai Minimum du champ TOS (ssh, PAS scp) est dirigé vers 1:10
echo ' - Champ TOS' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip tos 0x10 0xff flowid 1:20 >> $log 2>> $log
echo ' - serveur SSH' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip dport 22 0xffff match ip tos 0x10 0xff flowid 1:20 >> $log 2>> $log
echo ' - client SSH' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip sport 22 0xffff match ip tos 0x10 0xff flowid 1:20 >> $log 2>> $log


echo ' - serveur DC' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip sport 14567 0xffff flowid 1:20 >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip sport 14667 0xffff flowid 1:20 >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip sport 14690 0xffff flowid 1:20 >> $log 2>> $log
echo ' - serveur CZ' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip sport 27015 0xffff flowid 1:20 >> $log 2>> $log
echo ' - serveur Q3' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip sport 27960 0xffff flowid 1:20 >> $log 2>> $log
echo ' - serveur TS' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip sport 8767 0xffff flowid 1:20 >> $log 2>> $log

echo ' - client DC' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip dport 14567 0xffff flowid 1:20 >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip dport 14667 0xffff flowid 1:20 >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip dport 14690 0xffff flowid 1:20 >> $log 2>> $log
echo ' - client CZ' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip dport 27015 0xffff flowid 1:20 >> $log 2>> $log
echo ' - client Q3' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip dport 27960 0xffff flowid 1:20 >> $log 2>> $log
echo ' - client TS' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 5 u32 \
match ip dport 8767 0xffff flowid 1:20 >> $log 2>> $log

# 3 - serveur Web et FTP
echo 'Classe 3' >> $log 2>> $log
echo ' - HTTP' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 10 u32 \
match ip sport 80 0xffff flowid 1:30 >> $log 2>> $log
echo ' - HTTPS' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 10 u32 \
match ip sport 443 0xffff flowid 1:30 >> $log 2>> $log
echo ' - FTP' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 10 u32 \
match ip sport 20 0xffff flowid 1:30 >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip prio 10 u32 \
match ip sport 21 0xffff flowid 1:30 >> $log 2>> $log
#tc filter add dev $WAN parent 1: protocol ip prio 10 u32 \
#match ip sport 49152 0xc000 flowid 1:30 >> $log 2>> $log
#tc filter add dev $WAN parent 1: protocol ip prio 10 u32 \
#match ip sport 65535 0xc000 flowid 1:30 >> $log 2>> $log

# 4 - Traffic utilisateur
echo 'Classe 4' >> $log 2>> $log
echo ' - Traffic utilisateur' >> $log 2>> $log
 
# 5 - p2p
echo 'Classe 5' >> $log 2>> $log
echo ' - initialisation mangle' >> $log 2>> $log
/usr/sbin/iptables -t mangle -F
/usr/sbin/iptables -t mangle -X
echo ' - Récupération du marquage des connexions' >> $log 2>> $log
/usr/sbin/iptables -t mangle -A PREROUTING -j CONNMARK --restore-mark
echo ' - Elimination des connexions déjà marquées' >> $log 2>> $log
/usr/sbin/iptables -t mangle -A PREROUTING -m mark ! --mark 0 -j ACCEPT

echo ' - Création des règles de gestion du traffic P2P'
/usr/sbin/iptables -t mangle -N p2p_mangle
# todo: set output interface.
/usr/sbin/iptables -t mangle -A PREROUTING -m ipp2p --ipp2p -j p2p_mangle

echo ' - Redirection des connexions TCP P2P marquées' >> $log 2>> $log
tc filter add dev $WAN parent 1: protocol ip handle 50 fw flowid 1:50

#echo ' - Marquage "pollueurs P2P"' >> $log 2>> $log
#for IP_P2P in $IPS_P2P; do
#  if [ $PORTS_P2P ]; then
#    /usr/sbin/iptables -t mangle -A p2p_mangle -p tcp -s $IP_P2P --sport $PORTS_P2P -j MARK --set-mark 50 >> $log 2>> $log
#  else
#    echo 'marquage '$IP_P2P >> $log 2>> $log
#    tc filter add dev $WAN parent 1: protocol ip u32 match ip src $IP_P2P/32 flowid 1:50 >> $log 2>> $log
#  fi
#done

echo ' - Marquage du traffic P2P' >> $log 2>> $log
/usr/sbin/iptables -t mangle -A p2p_mangle -m ipp2p --ipp2p -j MARK --set-mark 50 >> $log 2>> $log

echo ' - Sauvegarde des marques pour la durée de la connexion' >> $log 2>> $log
/usr/sbin/iptables -t mangle -A PREROUTING -j CONNMARK --save-mark


#echo '*** Limitation du download ***' >> $log 2>> $log
echo 'Création ingress' >> $log 2>> $log
tc qdisc add dev $WAN handle ffff: ingress >> $log 2>> $log
echo 'Limitation de la queue de téléchargement' >> $log 2>> $log
tc filter add dev $WAN parent ffff: protocol ip prio 1 u32 match ip src \
  0.0.0.0/0 police rate ${MAX_DL}kbit burst ${MAX_DL_BURST}k drop flowid :1 >> $log 2>> $log

