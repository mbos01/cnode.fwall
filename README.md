# cnode.fwall
Cardano node firewall

CNODE.FWALL is a firewall tool with which you can check the incoming connections on your Cardano node port for your RELAY NODES. Whenever the max connection threshold is exceeded for an ip address the script will place a temporary ban on the address and it will disconnect all established sessions. Ip bans are stored in a sql database to make sure they are also active after a server reboot. 

The script runs as a systemd service and acts as a persistant iptables solution. You define what rules you want to be always effective and on each reboot the script will first apply these rules for you and inserts the banned ip adresses on top of that. Settings are configured in a config file and once everything is setup it's all on auto-pilot. (I DID NOT TEST THIS WITH THE IPTABLES-PERSISTENT PACKAGE, for I am not using that)

Current version is the first take. It's created on Linux Ubuntu 20.04 and only tested in this environment. The script uses iptables, net-tools, sqlite3 and mailutils so be sure that these packages are installed prior to running the script. (mail is currently only used with new bans, if you choose to disable this just comment out the MAIL_EXE variable in the config file)

Always make sure to list your core producer in the exception list! You don't want it to be banned by your relay nodes.

# Prerequisites
*iptables
*net-tools
*sqlite3
*mailutils

# Installation
1. Installing dependencies
   > If you have the dependecies installed you can skip this step.
   ```
   sudo apt-get update
   sudo apt-get install iptables net-tools sqlite3 mailutils -y
   ```
   
2. Download `cnode.fwall`
   ```
   cd /opt
   sudo git clone https://github.com/mbos01/cnode.fwall.git
   cd cnode.fwall
   ```
   
3. Adjust config, MAKE SURE to exclude your core producer! (below is a default setup, feel free to adjust to your liking)
   ```
   sudo nano cnode.fwall.config
   ```
   ![alt text](https://github.com/mbos01/cnode.fwall/blob/main/cnode.fwall.config.jpg?raw=true)

   > I'm assuming mail config is in place, I only tested using `POSTFIX`. If you don't want to use the mail function comment out `MAIL_EXE` by placing a `#` in front of it: `#MAIL_EXE`.

4. Adjust the default iptables rules, these will always be active (limited ruleset included, adjust to your liking but be sure to keep the last 2 rules always at the bottom)
   ```
   sudo nano iptables.rules
   ```
   ![alt text](https://github.com/mbos01/cnode.fwall/blob/main/iptables.rules.jpg?raw=true)
   > Your NIC (Network Interface Card) will most likely be `eth0`.
   > 

5. Make executable
   ```
   sudo chmod +x cnode.fwall.sh
   ```
   
6. Install as a service
   ```
   sudo ./cnode.fwall.sh --install
   ```
   > Service is installed and started. You can check the status by running `sudo service cnode.fwall status` or by looking in the syslog `sudo cat /var/log/syslog`.
   > 

From here on the script is running on auto-pilot and it will kickban any ip address that crosses your connection threshold.

**ABSOLUTELY MAKE SURE THAT YOU DON'T LOCK YOURSELF OUT AND THAT YOUR CORE PRODUCER WILL NOT GET BANNED FROM YOUR RELAY NODES**

 
