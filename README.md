# mister-hassio
This script that can be run on a MiSTer FPGA that sends current game data to Home Assistant.
Feel free to leave suggestions on better ways of interacting with the two platforms.

This works by first registering itself as a startup script in MiSTer (thanks wizzo), and then polling on a regular interval, configured at 5 seconds by default.

![Home Assitant dashboard card](/images/dashboard.png)

# Setup
## Home Assistant
* Create a long lived token for API authorizations and add this to the hassio.ini file.
* Create a Helper of "text" type for your game. Default ini settings are input_text.mister_fpga
* Add the api integration to your configuration.yaml

To quickly do all these things, add the below to you configuration.yaml
```
# Integrations
api:

# Helpers
input_text:
  mister_fpga:
    name: Mister FPGA
    mode: text
    max: 255
    icon: mdi:controller-classic
```

Optionally, you can also add a "Generic Camera" integration if you plan to use the retroachievement screenshot feature. This is the best way I've found to refresh the image in (near) realtime. You will need to set the Still Image URL as follows:
```
{{state_attr("input_text.mister_fpga", "image") }}
```

## MiSTer
* Set recents=1 in mister.ini.
* Update the hassio.ini file as needed. You will at least need to add your long lived token.
* Place hassio.ini and hassio.sh in your /Scripts dir.

# Rendering in Home Assistant
Feel free to share examples of how you are using this. I added some YAML to the samples folder to get you started.

# Future Updates
Some of my plans to improve off this proof of concept:
* More metadata from Retroachievements
* Change from polling to file watching. Maybe. 
* Improve logging.
* Better testing.