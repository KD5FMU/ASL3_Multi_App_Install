![MAPI Logo](https://github.com/KD5FMU/ASL3_Multi_App_Install/blob/main/MAIS.png)

# AllStarLink Multiple Application Install Script
This is a script file that will help install AllScan, DvSwitch Server, SkywarnPlus, Supermon 7.4 Fresh Install and the Upgradable Version. I mostly utilize this script to install these Apps once I setup a new ASL3 Install.

You now have the option to install, SkywarnPlus, DVSwitch Server, AllScan and Supermon 7.4+ Upgrade verison onto your AllStarLink version 3 node. As of this date (1/11/2025) This has been tested on the Raspberry Pi Appliance version of ASL 3,

This has also been tested on Debian 12 versions.



Once you have done a basic setup of the new ASL 3 node install you can now safely download and run the before mentioned script file. Go to the root directory by executing the following command:

```
cd
```

Then we can download the script file with this command:

```
wget https://raw.githubusercontent.com/KD5FMU/ASL3_Multi_App_Install/refs/heads/main/m_app.sh
```

Then once the download has finished we need to make the newly downloaded script file executable. We can do this with the following command:

```
chmod +x m_app.sh
```
You now have options that can be passed to the script to install the applications that you desire.
```
Usage: ./m-app.sh [OPTIONS]

Options:
  -a    Install allscan
  -s    Install supermon
  -w    Install skywarnplus
  -d    Install dvswitch
  -h    Display this help message

You can combine options to install multiple software (e.g., ./m_app.sh -a -s).
```

Then once that is down you can go ahead and run the script file with this command: This is an example please pick the applications you are wanting.

```
sudo ./m_app.sh -aswd
```

This will take a little while to install and you will encounter some prompts for information. Please answer them as you see needed but most of them, if not all, will most likely be a yes answer. But if you are a more advanced user then you can make whatever choice you wish.

This script will install AllScan, DVSwitch Server, SkywarnPlus and Supermon 7.4+ 

It is my wish that you find this script file useful.

73 DE KD5FMU

"Ham On Y'all" 

