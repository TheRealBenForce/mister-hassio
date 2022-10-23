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

INI_PATH = "/media/fat/Scripts/hassio.ini"
if os.path.exists(INI_PATH):
    ini = configparser.ConfigParser()
    ini.read(INI_PATH)
    HA_HOSTNAME = ini["HA_INFO"]["HA_HOSTNAME"]
    HA_PROTOCOL = ini["HA_INFO"]["HA_PROTOCOL"]
    HA_PORT = ini["HA_INFO"]["HA_PORT"]
    HA_GAME_ENTITY = ini["HA_INFO"]["HA_GAME_ENTITY"]
    HA_PLATFORM_ENTITY = ini["HA_INFO"]["HA_PLATFORM_ENTITY"]
    HA_LONG_LIVED_TOKEN = ini["HA_INFO"]["HA_LONG_LIVED_TOKEN"]
    LOG_LEVEL = ini["GENERAL"]["LOG_LEVEL"]
    POLL_TIME = ini["GENERAL"]["POLL_TIME"]

file_handler = logging.FileHandler(filename='/tmp/hassio.log', encoding='utf-8')
stdout_handler = logging.StreamHandler(stream=sys.stdout)
handlers = [stdout_handler]
#handlers.append(file_handler)
numeric_level = getattr(logging, LOG_LEVEL.upper(), 10)
logging.basicConfig(
    level=numeric_level, 
    format='[%(asctime)s] {%(filename)s:%(lineno)d} %(levelname)s - %(message)s',
    handlers=handlers
)
logger = logging.getLogger('hassio_logger')


SAM_PATH = "/tmp/SAM_Game.txt"
CORES_RECENT_PATH = "/media/fat/config/cores_recent.cfg"
BASEURL = "{}://{}:{}/api/".format(HA_PROTOCOL, HA_HOSTNAME, HA_PORT)
STARTUP_SCRIPT = "/media/fat/linux/user-startup.sh"

#cmd = 'while inotifywait -e close_write /tmp/SAM_Game.txt; do /media/fat/Scripts/hassio.sh; done'
#os.system(cmd)


# run a refresh on each boot, thanks wizzo
def try_add_to_startup():
    logger.info('Adding script to startup.')
    if not os.path.exists(STARTUP_SCRIPT):
        return
    with open(STARTUP_SCRIPT, "r") as f:
        if "Startup Hass Watcher" in f.read():
            return
    with open(STARTUP_SCRIPT, "a") as f:
        f.write(
            "\n# Startup Hass Watcher\n[[ -e /media/fat/Scripts/hassio.sh ]] && /media/fat/Scripts/hassio.sh refresh\n"
        )
    return


def find_most_recent():
    list_of_files = glob.glob('/media/fat/config/*_recent_*.cfg')
    list_of_files.append(CORES_RECENT_PATH)
    if os.path.isfile(SAM_PATH):
        logger.debug('Determined SAM is active on system.')
        list_of_files.append(SAM_PATH)
    latest_file = max(list_of_files, key=os.path.getctime)
    if latest_file == SAM_PATH:
        logger.debug('Determined SAM is most recent launch.')
        game, platform = get_game_from_sam()
    elif latest_file == CORES_RECENT_PATH:
        logger.debug('Determined most recent launched from menu.')
        game, platform = get_game_from_cores_recent()
    else:
        logger.debug('Determined most recent launched from core {}.'.format(latest_file))
        game, platform = get_game_from_specific_cores_recent(latest_file)
    platform = get_friendly_platform_name(platform)
    logger.debug("Latest file: {}".format(latest_file))
    logger.debug("Latest game: {}".format(game))
    logger.debug("Latest platform: {}".format(platform))
    return game, platform


def get_game_from_sam():
    logger.debug('Getting recent launched game from SAM')
    with open(SAM_PATH) as f:
        line = f.readline()
    f.close
    arr = line.split('(')
    game = arr[0].strip()
    platform = arr[-1].split(')')[0]
    return game, platform


def get_game_from_specific_cores_recent(filepath: str):
    logger.debug('Getting recent launched game from cores_recents')
    with open(filepath) as f:
        game_path = f.readline().split('\x00')[0]
    f.close
    platform = game_path.split("/")[1]
    game = game_path.split("/")[2].split(".")[0]
    return game, platform


def get_game_from_cores_recent():
    logger.debug('Getting recent launched game from {}'.format(CORES_RECENT_PATH))
    with open(CORES_RECENT_PATH) as f:
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


def get_friendly_platform_name(platform: str):
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

def test_api():
    try:
        logger.debug('Testing Home Assistant API.')
        http = urllib3.PoolManager()
        r = http.request(
            'GET', 
            BASEURL,
            headers={
                "authorization": 'Bearer ' + HA_LONG_LIVED_TOKEN,
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

def get_entity(entity):
    try:
        logger.debug('Checking for {} entity'.format(entity))
        http = urllib3.PoolManager()
        r = http.request(
            'GET',
            "{}states/{}".format(BASEURL, entity),
            headers={
                "authorization": 'Bearer ' + HA_LONG_LIVED_TOKEN,
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


def update_entity(entity: str, state: str, attributes: dict):
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


try_add_to_startup()
while True:
    if test_api() == 200:
        current_hass_state_game = get_entity(HA_GAME_ENTITY)
        current_hass_state_platform = get_entity(HA_PLATFORM_ENTITY)
        if current_hass_state_game and current_hass_state_platform: 
            game, platform = find_most_recent()
            logger.info("Latest: {} - {}".format(platform, game))
            latest_game = game
            latest_platform = platform
            update_entity(HA_GAME_ENTITY, game, current_hass_state_game['attributes'])
            update_entity(HA_PLATFORM_ENTITY, platform, current_hass_state_platform['attributes'])
    print("Sleeping {} seconds...".format(POLL_TIME))
    time.sleep(int(POLL_TIME))