#!/usr/bin/env python
import configparser
import glob
import json
import logging
import os
import re
import sys
import time
import urllib3

# Globals
INI_PATH = "./hassio.ini"
if os.path.exists(INI_PATH):
    ini = configparser.ConfigParser()
    ini.read(INI_PATH)
    LOG_LEVEL = ini["GENERAL"]["LOG_LEVEL"]
    LOG_TO_FILE = ini["GENERAL"]["LOG_TO_FILE"]
    LOG_TO_STDOUT = ini["GENERAL"]["LOG_TO_STDOUT"]
    POLL_TIME = ini["GENERAL"]["POLL_TIME"]

# Setup Logging
file_handler = logging.FileHandler(filename='/tmp/hassio.log', encoding='utf-8')
stdout_handler = logging.StreamHandler(stream=sys.stdout)
if LOG_TO_STDOUT:
    handlers = [stdout_handler]
if LOG_TO_FILE:
    handlers.append(file_handler)
numeric_level = getattr(logging, LOG_LEVEL.upper(), 10)
logging.basicConfig(
    level=numeric_level, 
    format='[%(asctime)s] {%(filename)s:%(lineno)d} %(levelname)s - %(message)s',
    handlers=handlers
    )
logger = logging.getLogger('hassio_logger')


class HomeAssistant:
    def __init__(self):
        self.hostname = ini["HA_INFO"]["HA_HOSTNAME"]
        self.protocol = ini["HA_INFO"]["HA_PROTOCOL"]
        self.port = ini["HA_INFO"]["HA_PORT"]
        self.game_entity_name = ini["HA_INFO"]["HA_GAME_ENTITY"]
        self.platform_entity_name = ini["HA_INFO"]["HA_PLATFORM_ENTITY"]
        self.current_hass_state_game = self.get_entity(self.game_entity_name)
        self.current_hass_state_platform = self.get_entity(self.platform_entity_name)
        self.token = ini["HA_INFO"]["HA_LONG_LIVED_TOKEN"]
        self.baseurl = "{}://{}:{}/api/".format(self.protocol, self.hostname, self.port)
        self.api_up = False
        if self.test_api() == 200:
            self.api_up = True
        return

    def test_api(self):
        try:
            logger.debug('Testing Home Assistant API.')
            http = urllib3.PoolManager()
            r = http.request(
                'GET', 
                self.baseurl,
                headers={
                    "authorization": 'Bearer ' + self.token,
                    "content-type": 'application/json'
                }
            )
            if r.status == 200:
                logger.debug('Home Assistant API is alive.')
            elif r.status == 401:
                logger.error('Home Assistant returned status code {}. You are unauthorized. Check your long lived token.'.format(str(r.status)))
            elif r.status == 403:
                logger.error('Home Assistant returned status code {}. You are forbidden. Check your long lived token and ip_bans.yaml.'.format(str(r.status)))
            else:
                logger.error('Home Assistant test api failed and returned status code {}'.format(str(r.status)))
            return r.status
        except Exception:
            logger.error(str(Exception))
            return None


    def get_entity(self, entity):
        try:
            logger.debug('Checking for {} entity'.format(entity))
            http = urllib3.PoolManager()
            r = http.request(
                'GET',
                "{}states/{}".format(self.baseurl, entity),
                headers={
                    "authorization": 'Bearer ' + self.token,
                    "content-type": 'application/json'
                }
            )
            if r.status == 200:
                logger.debug("{} entity was found.".format(entity))
                logger.debug(json.loads(r.data.decode('utf-8'))['state'])
                return json.loads(r.data.decode('utf-8'))
            elif r.status == 404:
                logger.debug("{} entity can't be found. Check readme for requirements.".format(entity))
            else:
                logger.debug("An unknown error has occurred.".format(entity))
        except Exception:
            logger.error(str(Exception))
        return


    def update_entity(self, entity: str, state: str, attributes: dict):
        http = urllib3.PoolManager()
        data = {
            'state': state,
            'attributes': attributes
            }
        encoded_data = json.dumps(data).encode('utf-8')
        r = http.request(
            'POST', 
            "{}states/{}".format(BASEURL, entity),
            body=encoded_data,
            headers= {
                "authorization": 'Bearer ' + HA_LONG_LIVED_TOKEN,
                "content-type": 'application/json'
            }
        )
        return

class Mister:
    def __init__(self):
        self.platform = ""
        self.startup_script_path = "/media/fat/linux/user-startup.sh"
        self.sam_path = "/tmp/SAM_Game.txt"
        self.sam_is_active = self.is_sam_active()
        self.config_path = "/media/fat/config"
        self.cores_recent_path = self.config_path + "/cores_recent.cfg"
        self.list_of_recent_files = glob.glob(self.config_path + "/*_recent_*.cfg")
        self.most_recent_file = self.find_most_recent_file()
        self.most_recent_game = self.find_most_recent_game()
        if ini["GENERAL"]["SET_AUTOSTART"].lower() == "true":
            self.try_add_to_startup()
        return


    def is_sam_active(self):
        if os.path.isfile(self.sam_path):
            logger.debug('Determined SAM is active on system.')
            return True


    def find_most_recent_file(self):
        list_of_files = self.list_of_recent_files
        list_of_files.append(self.cores_recent_path)
        if self.sam_is_active:
            list_of_files.append(self.sam_path)
        return max(list_of_files, key=os.path.getctime)


    def find_most_recent_game(self):
        if self.most_recent_file == self.sam_path:
            logger.debug('Determined SAM is most recent launch.')
            game, platform = self.get_game_from_sam()
        elif self.most_recent_file == self.cores_recent_path:
            logger.debug('Determined most recent launched from menu.')
            game, platform = self.get_game_from_cores_recent()
        else:
            logger.debug('Determined most recent launched from core {}.'.format(self.most_recent_file ))
            game, platform = self.get_game_from_specific_cores_recent()
        platform = self.get_friendly_platform_name(platform)
        logger.debug("Latest file: {}".format(self.most_recent_file))
        logger.debug("Latest game: {}".format(game))
        logger.debug("Latest platform: {}".format(platform))
        return Game(game, platform)


    def get_game_from_sam(self):
        logger.debug('Getting recent launched game from SAM')
        with open(self.most_recent_file) as f:
            line = f.readline()
        f.close
        arr = line.split('(')
        game = arr[0].strip()
        platform = arr[-1].split(')')[0]
        return game, platform


    def get_game_from_specific_cores_recent(self):
        logger.debug('Getting recent launched game from cores_recents')
        with open(self.most_recent_file) as f:
            game_path = f.readline().split('\x00')[0]
        f.close
        platform = game_path.split("/")[1]
        game = game_path.split("/")[2].split(".")[0]
        return game, platform


    def get_game_from_cores_recent(self):
        logger.debug('Getting recent launched game from {}'.format(self.most_recent_file))
        with open(self.most_recent_file) as f:
            data = f.readline()
        f.close
        arr = re.split('\x00+', data)
        print(arr)
        platform = arr[0].split('/')[0]
        if platform[0] == '_':
            platform = platform[1:]
        game = arr[1].split('.')[0]
        print(platform)
        print(game)
        return game, platform


    def get_friendly_platform_name(self, platform: str):
        logger.debug('Converting {} to a friendly name.'.format(platform))
        if platform.lower() == "arcade":
            return "Arcade"
        elif platform.lower() == "sms":
            return "Sega Master System"
        elif platform.lower() == "genesis":
            return "Sega Genesis"
        elif platform.lower() == "nes":
            return "Nintendo Entertainment System"
        elif platform.lower() == "snes":
            return "Super Nintendo Entertainment System"
        else:
            return platform


    def try_add_to_startup(self):
        logger.info('Adding script to startup.')
        if not os.path.exists(self.startup_script_path ):
            return
        with open(self.startup_script_path , "r") as f:
            if "Startup Hass Watcher" in f.read():
                return
        with open(self.startup_script_path , "a") as f:
            f.write(
                "\n# Startup Hass Watcher\n[[ -e /media/fat/Scripts/hassio.sh ]] && /media/fat/Scripts/hassio.sh refresh\n"
            )
        return

class Game:
    def __init__(self, name, platform):
        self.name = name
        self.platform = platform
        self.image = "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f7/Generic_error_message.png/220px-Generic_error_message.png"
        self.release_date = ""
        self.description = ""

while True:
    ha = HomeAssistant()
    if ha.api_up:
        mister = Mister()
        print(ha.game_entity_name)
        print(ha.platform_entity_name)
        print(mister.most_recent_game.name)
        print(mister.most_recent_game.platform)
        #ha.update_entity(ha.game_entity_name, mister.most_recent_game.name), current_hass_state_game['attributes'])
        #ha.update_entity(HA_PLATFORM_ENTITY, platform, current_hass_state_platform['attributes'])
    print("Sleeping {} seconds...".format(POLL_TIME))
    time.sleep(int(POLL_TIME))

