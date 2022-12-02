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
INI_PATH = "/media/fat/Scripts/hassio.ini"
if os.path.exists(INI_PATH):
    ini = configparser.ConfigParser()
    ini.read(INI_PATH)


class HomeAssistant:
    def __init__(self, Mister, RetroAchievement=None):
        self.entity = {}
        self._baseurl = "{}://{}:{}/api/".format(ini["HA_INFO"]["HA_PROTOCOL"], ini["HA_INFO"]["HA_HOSTNAME"], ini["HA_INFO"]["HA_PORT"])
        self._token = ini["HA_INFO"]["HA_LONG_LIVED_TOKEN"]
        if self._test_api() == 200:
            self.entity = self.get_entity()
            if Mister.game.name != self.entity["state"]:
                self.update_entity(Mister, RetroAchievement)
        return

    def _test_api(self):
        try:
            logger.debug('Testing Home Assistant API.')
            http = urllib3.PoolManager()
            r = http.request(
                'GET', 
                self._baseurl,
                headers={
                    "authorization": 'Bearer ' + self._token,
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


    def get_entity(self):
        try:
            entity_id = ini["HA_INFO"]["HA_MISTER_ENTITY_ID"]
            logger.debug('Checking for {} entity'.format(entity_id))
            http = urllib3.PoolManager()
            print("{}states/{}".format(self._baseurl, entity_id))
            r = http.request(
                'GET',
                "{}states/{}".format(self._baseurl, entity_id),
                headers={
                    "authorization": 'Bearer ' + self._token,
                    "content-type": 'application/json'
                }
            )
            if r.status == 200:
                logger.debug("{} entity was found.".format(entity_id))
                logger.debug(json.loads(r.data.decode('utf-8'))['state'])
                return json.loads(r.data.decode('utf-8'))
            elif r.status == 404:
                logger.error("{} entity can't be found. Check readme for requirements.".format(entity_id))
            else:
                logger.error("An unknown error has occurred.".format(entity_id))
        except Exception:
            logger.error("Unexpected exception getting entity.")
            logger.error(str(Exception))
        return


    def update_entity(self, Mister, Ra):
        http = urllib3.PoolManager()
        attributes = self.entity["attributes"]
        attributes["platform"] = Mister.platform.name
        attributes["image"] = Ra.image_preferred
        data = {
            'state': Mister.game.name,
            'attributes': attributes
            }
        encoded_data = json.dumps(data).encode('utf-8')
        r = http.request(
            'POST', 
            "{}states/{}".format(self._baseurl, self.entity["entity_id"]),
            body=encoded_data,
            headers= {
                "authorization": 'Bearer ' + self._token,
                "content-type": 'application/json'
            }
        )
        return

class Mister:
    def __init__(self):
        self.game = ""
        self.platform = ""
        self.platform_names = []
        self.set_autostart()
        self.game, self.platform  = self.find_most_recent()
        return


    def find_most_recent(self):
        config_path = "/media/fat/config"
        cores_recent_path = config_path + "/cores_recent.cfg"
        sam_path = "/tmp/SAM_Game.txt"
        list_of_files = glob.glob(config_path + "/*_recent_*.cfg")
        list_of_files.append(cores_recent_path)
        if os.path.isfile(sam_path):
            list_of_files.append(sam_path)
        most_recent_file = max(list_of_files, key=os.path.getctime)
        if most_recent_file == sam_path:
            logger.debug('Determined SAM is most recent launch.')
            game, platform = self.get_game_from_sam(most_recent_file)
        elif most_recent_file == cores_recent_path:
            logger.debug('Determined most recent launched from menu.')
            game, platform = self.get_game_from_cores_recent(most_recent_file)
        else:
            logger.debug('Determined most recent launched from core {}.'.format(most_recent_file))
            game, platform = self.get_game_from_specific_cores_recent(most_recent_file)
        logger.info("Latest file: {}".format(most_recent_file))
        logger.info("Latest game: {}".format(game))
        logger.info("Latest platform: {}".format(platform))
        return Game(game), Platform(platform)


    def get_game_from_sam(self, file:str):
        with open(file) as f:
            line = f.readline()
        f.close
        arr = line.split('(')
        game = arr[0].strip()
        platform = arr[-1].split(')')[0]
        return game, platform


    def get_game_from_specific_cores_recent(self, file: str):
        with open(file) as f:
            game_path = f.readline().split('\x00')[0]
        f.close
        platform = game_path.split("/")[1]
        game = game_path.split("/")[2].split(".")[0]
        return game, platform


    def get_game_from_cores_recent(self, file:str):
        with open(file) as f:
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


    def set_autostart(self):
        startup_script_path = "/media/fat/linux/user-startup.sh"
        str = "\n# Startup Hass Watcher\n[[ -e /media/fat/Scripts/hassio.sh ]] && /media/fat/Scripts/hassio.sh refresh\n"
        if ini["GENERAL"]["SET_AUTOSTART"].lower().split(" ")[0] == "true":
            with open(startup_script_path , "r") as f:
                if str in f.read():
                    logger.debug('Startup entry already exists.')
                    return
            with open(startup_script_path , "a") as f:
                logger.debug('Adding script to startup.')
                f.write(str)
                f.close()
        else:
            if not os.path.exists(startup_script_path):
                return
            with open(startup_script_path , "r") as f:
                contents = f.read()
                new_contents = contents.replace(str, "")
                f.close
            if contents != new_contents:
                logger.debug('Removing script from startup.')
                with open(startup_script_path , "w") as f:
                    new_contents = contents.replace(str, "")
                    f.write(new_contents)
                    f.close
        return

class Game:
    def __init__(self, name: str):
        self.name = name

class Platform:
    def __init__(self, core: str):
        self.core = core
        self._names_data = self._get_names_csv()
        self.names = self._get_platform_names()
        self.name = self.get_friendly_platform_name()


    def _get_names_csv(self):
        ''' Downloads names.csv from github and stores data in the object. '''
        try:
            systems_url = "https://raw.githubusercontent.com/ThreepwoodLeBrush/Names_MiSTer/master/names.csv"
            http = urllib3.PoolManager()
            r = http.request("GET", systems_url)
            if r.status == 200:
                logger.debug('Retrieved names.csv file from github {}'.format(str(r.status)))
                data = "".join(map(chr,r.data))
                return data.split('\n')
            else:
                logger.error('Failed to retrieve names.csv file from github {}'.format(str(r.status)))
                return []
        except Exception as e:
            logger.error(str(e))
            return []


    def _get_preferred_platform_index(self):
        ''' Get your preferred platform name from names.csv.'''
        try:
            pref_format = ini["GENERAL"]["PREFERRED_PLATFORM_FORMAT"]
            clean_array = ' '.join(self._names_data[1].split()).replace(" ;", ";").lower().split(";")
            i = clean_array.index(pref_format.lower())
            logger.info('Idenfied prefered platform {} in index {} of names.csv file.'.format(pref_format, str(i)))  
            return i
        except Exception as e:
            logger.error(str(e))
            logger.error("Falling back to default index of names_char28_common_us")
            return 9


    def _get_platform_names(self):
        """
        Takes in the platform name from MiSTer. 
        Strips the names.csv file down to something cleaner.
        Attempts to match the MiSTER name to the names.csv using the index of the preferred platform name and returns it.
        This one gets a bit messy, clean this up later.
        This is later used for matching platform names against Retro Achievement API.
        """
        try:
            if (self.core.lower() == "arcade"):
                return [self.core]
            for row in self._names_data:
                clean_row = ' '.join(row.split()).replace(" ;", ";")
                rowArr = clean_row.split(";")
                if len(rowArr) == 1:
                    continue
                for i in rowArr:
                    if i.lower() == self.core.lower():
                        print(i)
                        logger.debug('Identified the following row match from names.txt')
                        logger.debug(rowArr)
                        return rowArr
        except Exception as e:
            logger.error(str(e))
            logger.error("Returning selected core {} as fallback platform name".format(self.core))
            return [self.core]


    def get_friendly_platform_name(self):
        logger.debug('Converting {} to preferred name.'.format(self.core))
        if self.core.lower() == "arcade": # Nothing in names.csv specifically for "Arcade".
            return "Arcade"
        elif len(self.names) > 1:
            idx = self._get_preferred_platform_index()
            return self.names[idx].split(":")[0]
        elif self.core == "sms":
            return "Sega Master System"
        elif self.core == "genesis":
            return "Sega Genesis"
        elif self.core == "nes":
            return "Nintendo Entertainment System"
        elif self.core == "snes":
            return "Super Nintendo Entertainment System"
        else:
            logger.debug('Could not find friendly name for {}. Returning as is.'.format(self.core))
            return self.core

class RetroAchievements:
    def __init__(self, game: str, platform_names: list[str]):
        self.released = ""
        self.image_title = "https://media.retroachievements.org/Images/000002.png"
        self.image_ingame = "https://media.retroachievements.org/Images/000002.png"
        self.image_boxart = "https://media.retroachievements.org/Images/000002.png"
        self.image_preferred = "https://media.retroachievements.org/Images/000002.png"
        self._baseurl = "https://ra.hfc-essentials.com/"
        self._universal_fields = {}

        if ini["RETRO_ACHIEVEMENTS"]["RA_ACTIVE"].lower().split(" ")[0] == "true":
            try:
                self._universal_fields = {
                    "user": ini["RETRO_ACHIEVEMENTS"]["RA_USER"],
                    "key": ini["RETRO_ACHIEVEMENTS"]["RA_API_KEY"],
                    "mode": "json"
                }
                console_ids = self._get_console_list()
                console_id = self._match_mister_platform_to_ra_id(platform_names, console_ids)
                game_list = self._get_game_list_from_console(console_id)
                game_id = self._match_mister_game_to_ra_id(game, game_list)
                self.get_game_info(game_id)
            except Exception as e:
                logger.error(str(e))
                return None


    def _get_console_list(self):
        try:
            logger.debug('Getting RA console ID list.')
            http = urllib3.PoolManager()
            r = http.request(
                'GET', 
                self._baseurl + "console_id.php",
                self._universal_fields
            )
            if r.status == 200:
                logger.debug('Retro Achievements API is alive.')
                logger.debug('Retro Achievements console_ids retrieved.')
                return json.loads(r.data.decode('utf-8'))['console'][0]
            else:
                logger.error('Retro Achievements test api failed and returned status code {}'.format(str(r.status)))
                return None
        except Exception as e:
            logger.error(str(e))
            return None


    def _get_game_list_from_console(self, console_id):
        try:
            logger.debug('Fetching game list data from Retro Achievements for console_id {}.'.format(console_id))
            http = urllib3.PoolManager()
            fields = self._universal_fields.copy()
            fields["console"] = console_id
            r = http.request(
                'GET', 
                self._baseurl + "game_list.php",
                fields
            )
            if r.status == 200:
                game_list = json.loads(r.data.decode('utf-8'))["game"][0]
                logger.debug('Retrieved {} games for console ID {}.'.format(len(game_list), console_id))
                return game_list
            else:
                logger.error('Retro Achievements returned status code {}'.format(str(r.status)))
                return None
        except Exception as e:
            logger.error(str(e))
            return None


    def get_game_info(self, game_id):
        try:
            logger.debug('Fetching game data from Retro Achievements for game_id {}.'.format(game_id))
            http = urllib3.PoolManager()
            fields = self._universal_fields.copy()
            fields["game"] = game_id
            r = http.request(
                'GET', 
                self._baseurl + "game_info.php",
                fields,
            )
            if r.status == 200:
                game_info = json.loads(r.data.decode('utf-8'))  
                logger.info('Retrieved game info from RA for {} with ID {}.'.format(game_info["Title"], game_id))
                media_url = "https://media.retroachievements.org"
                self.image_boxart = media_url + game_info["ImageBoxArt"]
                self.image_ingame = media_url + game_info["ImageIngame"] 
                self.image_title = media_url + game_info["ImageTitle"]
                self.released = game_info["Released"]
                self._set_preferred_image()
            else:
                logger.error('Retro Achievements returned status code {}'.format(str(r.status)))
                return None
        except Exception as e:
            logger.error(str(e))
            return None


    def _match_mister_platform_to_ra_id(self, platform_names, console_list):
        logger.debug("Attempting to match Mister console {} to RA ID.".format(platform_names[0]))
        for c in console_list:
            for p in platform_names:
                if (c["Name"].lower() == p.lower()):
                    id = c["ID"]
                    logger.info("Matched Mister console {} to RA ID: {}.".format(p, id))
                    return id
        logger.debug("Could not match Mister console {} to RA ID.".format(platform_names[0]))
        return None


    def _match_mister_game_to_ra_id(self, game, game_list):
        simple = trim_game_name(game)
        logger.debug("Attempting to match {} to RA game.".format(game))
        for g in game_list:
            g_arr = trim_game_name(g["Title"]).split(" | ") # some retroachievement games have two names, not sure why
            for i in g_arr:
                if simple == i:
                    logger.debug("Matched Mister game {} to RA ID: {}.".format(game, g["ID"]))
                    return g["ID"]
        logger.debug("Could not find matching game ID")
        return None


    def _set_preferred_image(self):
        '''Selects preferred image based on what is available and preferences from ini file'''
        try:
            pref = ini["RETRO_ACHIEVEMENTS"]["RA_PREFERRED_IMAGE"].lower().split(" ")[0]
            if pref == "title":
                self.image_preferred = self.image_title
            if pref == "ingame":
                self.image_preferred = self.image_ingame
            if pref == "box":
                self.image_preferred = self.image_boxart
            if len(self.image_preferred) == 0 and len(self.image_title) > 0:
                self.image_preferred = self.image_title
            if len(self.image_preferred) == 0 and len(self.image_ingame) > 0:
                self.image_preferred = self.image_ingame
            if len(self.image_preferred) == 0 and len(self.image_box) > 0:
                self.image_preferred = self.image_box
        except:
            logger.error("Could not set preferred image. Defaulting to title image.")
            self.image_preferred = self.image_title
        return


def trim_game_name(name: str):
    '''Atempts to remove some potential characters and words that could cause titles to not be matched.'''
    new_name = name.lower()
    new_name = new_name.replace("&", "and")
    new_name = new_name.replace(" vs", " versus")
    new_name = new_name.replace("the", "")
    new_name = new_name.replace("demo", "")
    new_name = new_name.replace("unlicensed", "")
    new_name = new_name.replace("prototype", "")
    new_name = new_name.replace("homebrew", "")
    new_name = new_name.replace("hack", "")
    remove_pattern = r"[-_:.,~']"
    new_name = re.sub(remove_pattern, '', new_name)
    new_name = re.sub(' +', ' ', new_name)
    return new_name.strip()

def set_logging():
    LOG_LEVEL = ini["GENERAL"]["LOG_LEVEL"].split(" ")[0]
    LOG_TO_FILE = ini["GENERAL"]["LOG_TO_FILE"].split(" ")[0]
    LOG_TO_STDOUT = ini["GENERAL"]["LOG_TO_STDOUT"].split(" ")[0]
    file_handler = logging.FileHandler(filename='/tmp/hassio.log', encoding='utf-8')
    stdout_handler = logging.StreamHandler(stream=sys.stdout)
    if LOG_TO_STDOUT:
        handlers = [stdout_handler]
    if LOG_TO_FILE:
        handlers.append(file_handler)
    try:
        if LOG_LEVEL.upper() == "DEBUG":
            numeric_level = 10
        elif LOG_LEVEL.upper() == "ERROR":
            numeric_level = 40
        else:
            raise Exception("Can not determine intended log level.")
    except Exception as e:
        numeric_level = 20
        pass
    logging.basicConfig(
        level=numeric_level, 
        format='[%(asctime)s] {%(filename)s:%(lineno)d} %(levelname)s - %(message)s',
        handlers=handlers
        )
    logging.getLogger('hassio_logger').info("Log level set to: {}".format(LOG_LEVEL))
    return logging.getLogger('hassio_logger')


logger = set_logging()
LOOP = ini["GENERAL"]["LOOP"].lower().split(" ")[0]
POLL_TIME = ini["GENERAL"]["POLL_TIME_SECONDS"].split(" ")[0]
last_game = None
while True:
    mister = Mister()
    if mister.game.name != last_game:
        ra = RetroAchievements(mister.game.name, mister.platform.names)
        ha = HomeAssistant(mister, ra)
    else:
        logger.debug("No change detected, skipping RA and HA updates.")
    if LOOP != "true":
        break
    print("Sleeping {} seconds...".format(POLL_TIME))
    time.sleep(int(POLL_TIME))
    last_game = mister.game.name 
