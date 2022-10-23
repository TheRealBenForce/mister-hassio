# mister-hassio
This script that can be run on a MiSTer FPGA that sends current game data to Home Assistant.
Feel free to leave suggestions on better ways of interacting with the two platforms.

This script is in early development and I have a few plans that will be breaking changes, but it is currently working.

This works by first registering itself as a startup script in MiSTer (thanks wizzo), and then polling on a regular interval, configured at 60 seconds by default.

![Home Assitant dashboard card](/images/dashboard.png)

# Setup
## Home Assistant
* Create a long lived token for API authorizations and add this to the hassio.ini file.
* Create a Helper of "text" type for your game. Default ini settings are mister_game.
* Create a Helper of "text" type for your platform. Default ini settings are mister_platform.
* Add the api integration.

To quickly do all these things, add the below to you configuration.yaml
```
# Integrations
api:

# Helpers
input_text:
  mister_game:
    name: Mister Game
    mode: text
    max: 255
    icon: mdi:controller-classic
  mister_platform:
    name: Mister Platform
    mode: text
    max: 255
    icon: mdi:television-classic
```

## MiSTer
* Set recents=1 in mister.ini.
* Update the hassio.ini file as needed. You will at lest need to add your long lived token.
* Place hassio.ini and hassio.sh in your /Scripts dir.

# Rendering in Home Assistant
Please share examples of how you are using this. I added some YAML to the samples folder to get you started.

# Future Updates
Some of my plans to improve off this proof of concept:
* Combine both entities into a single entity with metadata attributes
* Integrate with a 3rd party API to send game art and metadata.
* Change from polling to file watching. Maybe. 
* Improve game and platform name formatting.
* Improve logging